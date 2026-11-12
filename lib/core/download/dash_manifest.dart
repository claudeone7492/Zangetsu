import 'package:xml/xml.dart';

/// One DASH track (video or audio) resolved from an MPD into concrete URLs.
///
/// DASH splits an episode into separate audio and video tracks far more often
/// than HLS does, so a track is downloaded on its own and muxed with its
/// counterpart afterwards. [segmentUrls] is the ordered media list; [initUrl]
/// is the fMP4 initialization segment (ftyp+moov) that must be written first.
class DashTrack {
  DashTrack({
    required this.mimeType,
    required this.segmentUrls,
    this.initUrl,
    this.codecs,
    this.width,
    this.height,
    this.bandwidth = 0,
    this.audioSamplingRate,
    this.lang,
  });

  final String mimeType;
  final List<String> segmentUrls;
  final String? initUrl;
  final String? codecs;
  final int? width;
  final int? height;
  final int bandwidth;
  final String? audioSamplingRate;
  final String? lang;

  bool get isVideo => mimeType.startsWith('video');
  bool get isAudio => mimeType.startsWith('audio');

  /// Height parsed from the video track's `height`, else null.
  int get heightPx => height ?? 0;
}

/// A parsed MPD: the one video track and one audio track to download.
///
/// A manifest with neither (or an unparseable one) yields null from
/// [parseDashManifest] rather than an empty object, so callers can fall back.
class DashManifest {
  DashManifest({this.video, this.audio});

  final DashTrack? video;
  final DashTrack? audio;

  bool get isEmpty => video == null && audio == null;
}

/// Resolves [ref] (relative or absolute) against [base].
String _resolve(String ref, String base) {
  final trimmed = ref.trim();
  if (trimmed.isEmpty) return base;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final b = Uri.parse(base);
  if (trimmed.startsWith('/')) {
    return b.replace(path: trimmed, query: '', fragment: '').toString();
  }
  return b.resolve(trimmed).toString();
}

/// ISO-8601 duration (`PT1H2M3.5S`) to seconds; null when unparseable.
double? parseIsoDuration(String? s) {
  if (s == null || s.isEmpty) return null;
  final m = RegExp(
    r'^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?)?$',
  ).firstMatch(s.trim());
  if (m == null) return null;
  final d = double.tryParse(m.group(1) ?? '0') ?? 0;
  final h = double.tryParse(m.group(2) ?? '0') ?? 0;
  final min = double.tryParse(m.group(3) ?? '0') ?? 0;
  final sec = double.tryParse(m.group(4) ?? '0') ?? 0;
  return d * 86400 + h * 3600 + min * 60 + sec;
}

/// The direct children of [node] matching [name] (namespace-insensitive).
Iterable<XmlElement> _children(XmlElement node, String name) =>
    node.childElements.where((e) => e.name.local == name);

/// The first direct child of [node] named [name], or null.
XmlElement? _child(XmlElement node, String name) {
  for (final e in node.childElements) {
    if (e.name.local == name) return e;
  }
  return null;
}

String? _attr(XmlElement? node, String name) =>
    node?.getAttribute(name) ?? node?.getAttribute('dash:$name');

/// Parses [mpd] (an MPD document fetched from [mpdUrl]) and selects the video
/// track closest to [quality] (or the highest for `best`/unknown) plus the
/// best audio track. Returns null when no downloadable track is found.
DashManifest? parseDashManifest(
  String mpd,
  String mpdUrl, {
  String quality = 'best',
}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(mpd);
  } catch (_) {
    return null;
  }
  final mpdNode = doc.rootElement;
  if (mpdNode.name.local != 'MPD') return null;

  // Encrypted (CENC) content downloads to unplayable bytes and would burn the
  // whole episode's bandwidth to find that out. A `cenc:default_KID` on a
  // ContentProtection element is the unambiguous signal; bail so the caller
  // falls back to another source instead.
  for (final cp in mpdNode.descendantElements) {
    if (cp.name.local != 'ContentProtection') continue;
    final kid = cp.getAttribute('default_KID') ??
        cp.getAttribute('cenc:default_KID');
    if (kid != null && kid.isNotEmpty) return null;
  }

  // MPD-level BaseURL applies to every Period.
  var base = mpdUrl;
  final mpdBase = _child(mpdNode, 'BaseURL');
  if (mpdBase != null) base = _resolve(mpdBase.innerText, base);

  // The first Period with an AdaptationSet is what we download. Multi-period
  // manifests (ad breaks, separate intros) are rare here and would need
  // timeline stitching; we take the main period rather than guessing.
  final period = _children(mpdNode, 'Period').firstWhere(
    (p) => _children(p, 'AdaptationSet').isNotEmpty,
    orElse: () => mpdNode,
  );
  final periodBase = _child(period, 'BaseURL');
  if (periodBase != null) base = _resolve(periodBase.innerText, base);
  final periodDuration =
      parseIsoDuration(_attr(period, 'duration')) ??
      parseIsoDuration(_attr(mpdNode, 'mediaPresentationDuration'));

  final videoSets = <XmlElement>[];
  final audioSets = <XmlElement>[];
  for (final set in _children(period, 'AdaptationSet')) {
    final mime = _attr(set, 'mimeType') ?? '';
    final contentType = _attr(set, 'contentType') ?? '';
    if (mime.startsWith('video') || contentType == 'video') {
      videoSets.add(set);
    } else if (mime.startsWith('audio') || contentType == 'audio') {
      audioSets.add(set);
    }
  }

  final video = _selectVideo(videoSets, base, quality, periodDuration);
  final audio = _selectAudio(audioSets, base, periodDuration);
  if (video == null && audio == null) return null;
  return DashManifest(video: video, audio: audio);
}

/// The video track closest to the requested quality (or the tallest for
/// `best`/unknown). A track that cannot be downloaded never wins.
DashTrack? _selectVideo(
  List<XmlElement> sets,
  String base,
  String quality,
  double? periodDuration,
) {
  final want = int.tryParse(
    RegExp(r'(\d{3,4})').firstMatch(quality)?.group(1) ?? '',
  );
  DashTrack? best;
  var bestDelta = 1 << 30;
  var bestHeight = -1;
  for (final set in sets) {
    for (final rep in _children(set, 'Representation')) {
      final track = _buildTrack(set, rep, base, periodDuration);
      if (track == null || track.segmentUrls.isEmpty) continue;
      final h = track.heightPx;
      if (want == null || quality == 'best') {
        if (h > bestHeight) {
          bestHeight = h;
          best = track;
        }
      } else {
        final delta = (h - want).abs();
        if (delta < bestDelta || (delta == bestDelta && h > bestHeight)) {
          bestDelta = delta;
          bestHeight = h;
          best = track;
        }
      }
    }
  }
  return best;
}

/// The audio track with the highest bandwidth that can actually be downloaded.
DashTrack? _selectAudio(
  List<XmlElement> sets,
  String base,
  double? periodDuration,
) {
  DashTrack? best;
  for (final set in sets) {
    for (final rep in _children(set, 'Representation')) {
      final track = _buildTrack(set, rep, base, periodDuration);
      if (track == null || track.segmentUrls.isEmpty) continue;
      if (best == null || track.bandwidth > best.bandwidth) best = track;
    }
  }
  return best;
}

/// Builds one track from an AdaptationSet + Representation pair, inheriting
/// attributes/templates the set declares down to the representation.
DashTrack? _buildTrack(
  XmlElement set,
  XmlElement rep,
  String base,
  double? periodDuration,
) {
  // BaseURL can appear at set, representation (and inside SegmentBase). The
  // most specific one wins.
  var trackBase = base;
  final setBase = _child(set, 'BaseURL');
  if (setBase != null) trackBase = _resolve(setBase.innerText, trackBase);
  final repBase = _child(rep, 'BaseURL');
  if (repBase != null) trackBase = _resolve(repBase.innerText, trackBase);

  final mime =
      _attr(rep, 'mimeType') ??
      _attr(set, 'mimeType') ??
      (mimeFromContentType(_attr(set, 'contentType')) ?? '');
  final codecs = _attr(rep, 'codecs') ?? _attr(set, 'codecs');
  final width = int.tryParse(_attr(rep, 'width') ?? _attr(set, 'width') ?? '');
  final height = int.tryParse(
    _attr(rep, 'height') ?? _attr(set, 'height') ?? '',
  );
  final bandwidth =
      int.tryParse(_attr(rep, 'bandwidth') ?? _attr(set, 'bandwidth') ?? '') ??
      0;
  final sampleRate =
      _attr(rep, 'audioSamplingRate') ?? _attr(set, 'audioSamplingRate');
  final lang = _attr(rep, 'lang') ?? _attr(set, 'lang');

  final repId = _attr(rep, 'id') ?? '';

  // SegmentTemplate (number or time), SegmentList, or SegmentBase (single
  // file). The most specific of rep/set wins; SegmentTemplate may also be
  // nested in a SegmentList-free set.
  final template =
      _child(rep, 'SegmentTemplate') ?? _child(set, 'SegmentTemplate');
  final list = _child(rep, 'SegmentList') ?? _child(set, 'SegmentList');
  final segmentBase =
      _child(rep, 'SegmentBase') ?? _child(set, 'SegmentBase');

  String? initUrl;
  final segments = <String>[];

  if (template != null) {
    final resolved = _segmentsFromTemplate(
      template,
      trackBase,
      repId,
      bandwidth,
      periodDuration: periodDuration,
    );
    initUrl = resolved.initUrl;
    segments.addAll(resolved.urls);
  } else if (list != null) {
    final init = _child(list, 'Initialization');
    final initSrc = _attr(init, 'sourceURL') ?? _attr(init, 'media');
    if (initSrc != null) initUrl = _resolve(initSrc, trackBase);
    for (final seg in _children(list, 'SegmentURL')) {
      final media = _attr(seg, 'media');
      if (media != null) segments.add(_resolve(media, trackBase));
    }
  } else if (segmentBase != null) {
    // Single-file representation: the whole file is the media. Its
    // Initialization/byte ranges only matter to a segment-aware client; we
    // download the file whole.
    segments.add(trackBase);
  } else {
    // No segment info at all — a plain BaseURL to a single file, if any.
    segments.add(trackBase);
  }

  if (segments.isEmpty) return null;
  return DashTrack(
    mimeType: mime,
    segmentUrls: segments,
    initUrl: initUrl,
    codecs: codecs,
    width: width,
    height: height,
    bandwidth: bandwidth,
    audioSamplingRate: sampleRate,
    lang: lang,
  );
}

String? mimeFromContentType(String? contentType) {
  switch (contentType) {
    case 'video':
      return 'video/mp4';
    case 'audio':
      return 'audio/mp4';
    default:
      return null;
  }
}

({String? initUrl, List<String> urls}) _segmentsFromTemplate(
  XmlElement template,
  String base,
  String repId,
  int bandwidth, {
  double? periodDuration,
}) {
  final initTpl = _attr(template, 'initialization');
  final mediaTpl = _attr(template, 'media');
  final timescale = int.tryParse(_attr(template, 'timescale') ?? '') ?? 1;
  final startNumber = int.tryParse(_attr(template, 'startNumber') ?? '') ?? 1;

  String expand(String tpl, {int? number, int? time}) {
    var out = tpl;
    out = out.replaceAll(r'$RepresentationID$', repId);
    out = out.replaceAll(r'$Bandwidth$', '$bandwidth');
    out = out.replaceAllMapped(
      RegExp(r'\$Number(?:%0(\d+)d)?\$'),
      (m) {
        final n = number ?? startNumber;
        final width = m.group(1);
        if (width == null) return '$n';
        return n.toString().padLeft(int.parse(width), '0');
      },
    );
    out = out.replaceAllMapped(
      RegExp(r'\$Time(?:%0(\d+)d)?\$'),
      (m) => '${time ?? 0}',
    );
    return _resolve(out, base);
  }

  final initUrl = initTpl == null ? null : expand(initTpl);

  // SegmentTimeline (time-based) takes precedence when present.
  final timeline = _child(template, 'SegmentTimeline');
  if (timeline != null) {
    final urls = <String>[];
    var time = 0;
    for (final s in _children(timeline, 'S')) {
      final t = int.tryParse(_attr(s, 't') ?? '');
      if (t != null) time = t;
      final d = int.tryParse(_attr(s, 'd') ?? '') ?? 0;
      final r = int.tryParse(_attr(s, 'r') ?? '') ?? 0;
      for (var i = 0; i <= r; i++) {
        if (mediaTpl != null) urls.add(expand(mediaTpl, time: time));
        time += d;
      }
    }
    return (initUrl: initUrl, urls: urls);
  }

  // Number-based: how many segments fit in the period.
  if (mediaTpl == null || !mediaTpl.contains(r'$Number')) {
    return (initUrl: initUrl, urls: const []);
  }
  final segDur = int.tryParse(_attr(template, 'duration') ?? '') ?? 0;
  if (segDur <= 0 || periodDuration == null || periodDuration <= 0) {
    // Without a period length we cannot know the count. Return nothing so the
    // caller can fall back rather than guessing a wrong segment list.
    return (initUrl: initUrl, urls: const []);
  }
  final totalSec = periodDuration;
  final segSec = segDur / timescale;
  final count = (totalSec / segSec).ceil();
  final urls = [
    for (var i = 0; i < count; i++) expand(mediaTpl, number: startNumber + i),
  ];
  return (initUrl: initUrl, urls: urls);
}
