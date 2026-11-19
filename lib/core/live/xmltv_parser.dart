import 'package:xml/xml.dart';

/// One programme in an EPG guide.
class EpgProgramme {
  const EpgProgramme({
    required this.channelId,
    required this.title,
    required this.start,
    required this.stop,
    this.description = '',
    this.category = '',
    this.iconUrl = '',
    this.episodeNumber = '',
  });

  /// XMLTV `channel` attribute — the guide's own channel id, matched to a
  /// playlist entry through [EpgGuide.channelNames].
  final String channelId;
  final String title;

  /// UTC start/stop. XMLTV timestamps are local-with-offset; both are stored
  /// normalised to UTC so comparisons across guides are safe.
  final DateTime start;
  final DateTime stop;

  final String description;
  final String category;
  final String iconUrl;

  /// `xmltv_ns` "series.episode.part" when the guide publishes one.
  final String episodeNumber;

  Duration get duration => stop.difference(start);

  bool isLiveAt(DateTime when) =>
      !when.isBefore(start) && when.isBefore(stop);

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'title': title,
    'start': start.toIso8601String(),
    'stop': stop.toIso8601String(),
    if (description.isNotEmpty) 'description': description,
    if (category.isNotEmpty) 'category': category,
    if (iconUrl.isNotEmpty) 'iconUrl': iconUrl,
    if (episodeNumber.isNotEmpty) 'episodeNumber': episodeNumber,
  };

  factory EpgProgramme.fromJson(Map<String, dynamic> j) => EpgProgramme(
    channelId: (j['channelId'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    start: DateTime.parse(j['start'] as String).toUtc(),
    stop: DateTime.parse(j['stop'] as String).toUtc(),
    description: (j['description'] as String?) ?? '',
    category: (j['category'] as String?) ?? '',
    iconUrl: (j['iconUrl'] as String?) ?? '',
    episodeNumber: (j['episodeNumber'] as String?) ?? '',
  );
}

/// A parsed XMLTV guide: the channel-id → display-name map plus each channel's
/// programmes, sorted by start time.
class EpgGuide {
  EpgGuide({required this.channelNames, required this.programmes});

  /// XMLTV channel id → display names. A playlist entry carries
  /// `tvg-id="bbc1.uk"`; that id keys into this map to find the guide's rows.
  final Map<String, List<String>> channelNames;

  /// Channel id → programmes, ascending by start.
  final Map<String, List<EpgProgramme>> programmes;

  bool get isEmpty => programmes.isEmpty;

  /// Programmes airing at [when] for [channelId].
  EpgProgramme? nowOn(String channelId, {DateTime? at}) {
    final when = (at ?? DateTime.now()).toUtc();
    for (final p in programmes[channelId] ?? const <EpgProgramme>[]) {
      if (p.isLiveAt(when)) return p;
    }
    return null;
  }

  /// The programme starting next on [channelId], or null when the guide has
  /// run out.
  EpgProgramme? nextOn(String channelId, {DateTime? at}) {
    final when = (at ?? DateTime.now()).toUtc();
    for (final p in programmes[channelId] ?? const <EpgProgramme>[]) {
      if (p.start.isAfter(when)) return p;
    }
    return null;
  }

  /// Everything on [channelId] from [from] to [to], ascending.
  List<EpgProgramme> between(
    String channelId, {
    required DateTime from,
    required DateTime to,
  }) {
    final f = from.toUtc();
    final t = to.toUtc();
    return [
      for (final p in programmes[channelId] ?? const <EpgProgramme>[])
        if (p.stop.isAfter(f) && p.start.isBefore(t)) p,
    ];
  }

  Map<String, dynamic> toJson() => {
    'channelNames': channelNames,
    'programmes': {
      for (final e in programmes.entries)
        e.key: [for (final p in e.value) p.toJson()],
    },
  };

  factory EpgGuide.fromJson(Map<String, dynamic> j) {
    final names = <String, List<String>>{};
    final rawNames = (j['channelNames'] as Map?) ?? const {};
    for (final e in rawNames.entries) {
      final v = e.value;
      if (v is List) {
        names['${e.key}'] = v.map((x) => '$x').toList();
      }
    }
    final progs = <String, List<EpgProgramme>>{};
    final rawProgs = (j['programmes'] as Map?) ?? const {};
    for (final e in rawProgs.entries) {
      final v = e.value;
      if (v is! List) continue;
      final list = <EpgProgramme>[];
      for (final raw in v) {
        if (raw is Map) {
          try {
            list.add(EpgProgramme.fromJson(Map<String, dynamic>.from(raw)));
          } catch (_) {
            // A single malformed row must not sink the guide.
          }
        }
      }
      list.sort((a, b) => a.start.compareTo(b.start));
      if (list.isNotEmpty) progs['${e.key}'] = list;
    }
    return EpgGuide(channelNames: names, programmes: progs);
  }
}

/// Parses XMLTV (`tv.dtd`) documents — the format every free EPG publishes.
///
/// Written by hand against the DTD rather than with a generated model because
/// the format is loose in practice: guides omit `stop`, use several timestamp
/// dialects, and repeat `<title>` in multiple languages. The parser is
/// deliberately forgiving — a row it can't read is skipped, never fatal, so a
/// partly broken guide still yields a usable schedule.
class XmltvParser {
  const XmltvParser();

  /// Parse [body] into a guide. Never throws: malformed XML yields an empty
  /// guide, since a guide is an enhancement over "no guide".
  EpgGuide parse(String body) {
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      return EpgGuide(channelNames: {}, programmes: {});
    }

    final names = <String, List<String>>{};
    for (final ch in doc.findAllElements('channel')) {
      final id = ch.getAttribute('id')?.trim() ?? '';
      if (id.isEmpty) continue;
      final display = <String>[];
      for (final name in ch.findElements('display-name')) {
        final text = name.innerText.trim();
        if (text.isNotEmpty) display.add(text);
      }
      if (display.isNotEmpty) names[id] = display;
    }

    final programmes = <String, List<EpgProgramme>>{};
    for (final node in doc.findAllElements('programme')) {
      final channelId = node.getAttribute('channel')?.trim() ?? '';
      final startRaw = node.getAttribute('start');
      if (channelId.isEmpty || startRaw == null) continue;

      final start = parseTimestamp(startRaw);
      if (start == null) continue;

      // `stop` is optional in the DTD. Without it the row still has a start,
      // so give it a nominal slot rather than dropping the programme — a guide
      // that only says "what's on now" is still worth showing.
      var stop = parseTimestamp(node.getAttribute('stop'));
      if (stop == null || !stop.isAfter(start)) {
        stop = start.add(const Duration(minutes: 30));
      }

      programmes
          .putIfAbsent(channelId, () => [])
          .add(
            EpgProgramme(
              channelId: channelId,
              title: _firstText(node, 'title'),
              start: start,
              stop: stop,
              description: _firstText(node, 'desc'),
              category: _firstText(node, 'category'),
              iconUrl: _firstIcon(node),
              episodeNumber:
                  node.getElement('episode-num')?.getAttribute('system') ==
                      'xmltv_ns'
                  ? (node.getElement('episode-num')?.innerText.trim() ?? '')
                  : '',
            ),
          );
    }

    for (final list in programmes.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return EpgGuide(channelNames: names, programmes: programmes);
  }

  static String _firstText(XmlElement node, String tag) {
    for (final e in node.findElements(tag)) {
      final text = e.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _firstIcon(XmlElement node) {
    for (final e in node.findElements('icon')) {
      final src = e.getAttribute('src')?.trim() ?? '';
      if (src.isNotEmpty) return src;
    }
    return '';
  }

  /// Parse an XMLTV timestamp: `YYYYMMDDhhmmss +hhmm` (offset optional).
  ///
  /// Returns UTC. Guides in the wild use both a numeric offset and a bare
  /// local time; a bare time is read as UTC, which is what the DTD specifies
  /// when no offset is given.
  static DateTime? parseTimestamp(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.length < 8) return null;

    int part(int start, int length) {
      final end = start + length;
      if (end > s.length) return 0;
      return int.tryParse(s.substring(start, end)) ?? -1;
    }

    final year = part(0, 4);
    final month = part(4, 2);
    final day = part(6, 2);
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final hour = part(8, 2);
    final minute = part(10, 2);
    final second = part(12, 2);
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    DateTime utc;
    try {
      utc = DateTime.utc(year, month, day, hour < 0 ? 0 : hour,
          minute < 0 ? 0 : minute, second < 0 ? 0 : second);
    } catch (_) {
      return null;
    }

    // Trailing ` +hhmm` / ` -hhmm` shifts the value to UTC. Find it after the
    // 14-char timestamp body so a stray digit inside the date can't match.
    final rest = s.length > 14 ? s.substring(14).trim() : '';
    if (rest.isEmpty) return utc;
    final m = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(rest);
    if (m == null) return utc;
    final sign = m.group(1) == '-' ? -1 : 1;
    final offsetMinutes =
        sign * (int.parse(m.group(2)!) * 60 + int.parse(m.group(3)!));
    return utc.subtract(Duration(minutes: offsetMinutes));
  }
}
