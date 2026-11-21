import '../models/video_source.dart';

/// Parses a quality label like `'1080p'` into a comparable int (height in px).
/// Unknown/empty → -1 so it sorts last.
int qualityRank(String? quality) {
  if (quality == null) return -1;
  final m = RegExp(r'(\d{3,4})').firstMatch(quality);
  if (m == null) return -1;
  return int.tryParse(m.group(1)!) ?? -1;
}

/// Returns [sources] sorted by quality high→low; unknown qualities last.
/// Stable for equal ranks (preserves input order).
List<VideoSource> sortByQuality(List<VideoSource> sources) {
  final indexed = sources.asMap().entries.toList();
  indexed.sort((a, b) {
    final r = qualityRank(
      b.value.quality,
    ).compareTo(qualityRank(a.value.quality));
    return r != 0 ? r : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

/// Distinct [AudioKind]s present in [sources], in first-seen order.
List<AudioKind> availableKinds(List<VideoSource> sources) {
  final seen = <AudioKind>[];
  for (final s in sources) {
    if (!seen.contains(s.kind)) seen.add(s.kind);
  }
  return seen;
}

/// Only the sources matching [kind].
List<VideoSource> sourcesForKind(List<VideoSource> sources, AudioKind kind) =>
    sources.where((s) => s.kind == kind).toList();

/// Approximate vertical resolution (px) named by a quality label. Handles the
/// 4K/2K/FHD shorthand as well as bare numbers. Null when the label names no
/// resolution at all — 'auto', 'highest', or a bare server name like
/// 'Doodstream'.
int? resolutionPx(String? label) {
  if (label == null) return null;
  final l = label.toLowerCase();
  if (l.contains('2160') || l.contains('4k') || l.contains('uhd')) return 2160;
  if (l.contains('1440') || l.contains('2k')) return 1440;
  if (l.contains('1080') || l.contains('fhd')) return 1080;
  if (l.contains('720')) return 720;
  if (l.contains('480')) return 480;
  if (l.contains('360')) return 360;
  if (l.contains('240')) return 240;
  final m = RegExp(r'(\d{3,4})').firstMatch(l);
  return m != null ? int.tryParse(m.group(1)!) : null;
}

/// Height named by free text, or null.
///
/// Stricter than [resolutionPx]: the number has to be followed by a `p`, so a
/// title's year ("2024") never reads as a resolution. Needed because providers
/// that ship one mirror per quality often put the resolution in the server's
/// own label ("HDHub · FSL [1080p]") and leave `quality` null.
int? heightFromText(String? text) {
  if (text == null || text.isEmpty) return null;
  final m = RegExp(
    r'(?<![0-9])(2160|1440|1080|720|576|480|360|240)\s*p',
    caseSensitive: false,
  ).firstMatch(text);
  if (m != null) return int.parse(m.group(1)!);
  final l = text.toLowerCase();
  if (RegExp(r'(^|[^a-z0-9])(4k|uhd)([^a-z0-9]|$)').hasMatch(l)) return 2160;
  if (RegExp(r'(^|[^a-z0-9])fhd([^a-z0-9]|$)').hasMatch(l)) return 1080;
  return null;
}

/// Resolution a source names: its [VideoSource.quality] first, then its
/// [VideoSource.label]. Null when it names none.
int? sourceHeight(VideoSource source) =>
    resolutionPx(source.quality) ?? heightFromText(source.label);

/// Best default source: highest quality of [prefer]; if none of that kind,
/// highest quality overall. Null only when [sources] is empty.
///
/// [preferQuality] is the user's saved resolution preference. When it names a
/// real resolution the source at or just below it wins (the lowest one above
/// when every server is taller), so a provider that ships one stream per
/// quality honours the preference by STARTING on the right stream.
/// Switching streams once playback is already running would be a different
/// file — different server, audio and subtitles — which is never what a
/// quality preference means.
VideoSource? pickDefault(
  List<VideoSource> sources, {
  AudioKind prefer = AudioKind.sub,
  String? preferQuality,
}) {
  if (sources.isEmpty) return null;
  final preferred = sortByQuality(sourcesForKind(sources, prefer));
  final pool = preferred.isNotEmpty ? preferred : sortByQuality(sources);

  final want = resolutionPx(preferQuality);
  if (want != null) {
    // Best at or below the wanted height; when everything is taller, the
    // lowest one above. A preference means "no worse than this", not "the
    // nearest number" — picking 1440p for a 1080p preference because it
    // happens to be arithmetically close costs bandwidth for nothing.
    final known = <(VideoSource, int)>[
      for (final s in pool)
        if (sourceHeight(s) case final h?) (s, h),
    ];
    if (known.isNotEmpty) {
      final below = known.where((e) => e.$2 <= want).map((e) => e.$2);
      final height = below.isEmpty
          ? known.map((e) => e.$2).reduce((a, b) => a < b ? a : b)
          : below.reduce((a, b) => a > b ? a : b);
      // Pool order (high->low, then discovery order) breaks a tie, so the
      // first server advertising that height wins.
      return known.firstWhere((e) => e.$2 == height).$1;
    }
  }
  // 'auto'/'highest', or nothing carried a resolution: the existing default.
  return pool.first;
}

/// Gives late CloudStream links a short chance to include the user's preferred
/// quality before [pickDefault] chooses an initial stream. This happens before
/// playback starts, so it never switches servers (and their audio/subtitles)
/// underneath the viewer. If the preference doesn't arrive within [maxWait],
/// the available links are returned and the saved preference remains intact.
Future<List<VideoSource>> waitForPreferredQuality({
  required List<VideoSource> initial,
  required String preferredQuality,
  required AudioKind preferredKind,
  required Future<({List<VideoSource> sources, bool done})> Function() poll,
  bool Function()? isStillCurrent,
  Duration maxWait = const Duration(seconds: 2),
  Duration pollInterval = const Duration(milliseconds: 250),
}) async {
  if (initial.isEmpty ||
      preferredQuality == 'auto' ||
      maxWait <= Duration.zero) {
    return initial;
  }

  final target = resolutionPx(preferredQuality);
  var collected = List<VideoSource>.of(initial);
  final seen = initial.map((source) => source.url).toSet();
  final timer = Stopwatch()..start();

  bool preferredQualityAvailable() {
    if (preferredQuality == 'highest') return false;
    if (target == null) return true;
    final inPreferredKind = preferredKind == AudioKind.unknown
        ? collected
        : sourcesForKind(collected, preferredKind);
    if (preferredKind != AudioKind.unknown && inPreferredKind.isEmpty) {
      return false;
    }
    return inPreferredKind.any(
      (source) => resolutionPx(source.quality) == target,
    );
  }

  while (timer.elapsed < maxWait) {
    if (isStillCurrent != null && !isStillCurrent()) return collected;
    if (preferredQualityAvailable()) return collected;
    final remaining = maxWait - timer.elapsed;
    late final ({List<VideoSource> sources, bool done}) result;
    try {
      result = await poll().timeout(
        remaining,
        onTimeout: () => (sources: const <VideoSource>[], done: true),
      );
    } catch (_) {
      return collected;
    }
    for (final source in result.sources) {
      if (seen.add(source.url)) collected.add(source);
    }
    if (preferredQualityAvailable() || result.done) return collected;

    final pause = maxWait - timer.elapsed;
    if (pause <= Duration.zero) break;
    await Future<void>.delayed(pollInterval < pause ? pollInterval : pause);
  }
  return collected;
}
