/// Catch-up (timeshift) URL construction.
///
/// Many providers keep a rolling window of past broadcasts and expose it by
/// appending a start time to the live URL. Every panel spells that differently,
/// which is why a channel that plays live can still fail to replay: the app has
/// to know which dialect the provider speaks.
library;

import 'dart:convert';

/// How a provider spells a catch-up request.
enum CatchupMode {
  /// No catch-up support.
  none,

  /// Append `?utc=<epoch>&lutc=<now>` — Xtream's default.
  appendQuery,

  /// Append `/<minutes offset>/<duration minutes>` to the path (Flussonic).
  pathOffset,

  /// Replace `{utc}` / `{lutc}` / `{start}` / `{end}` in a template URL.
  template,
}

/// A provider's catch-up declaration, usually parsed from an M3U
/// `catchup`/`catchup-source`/`catchup-days` attribute set.
class CatchupSpec {
  const CatchupSpec({
    this.mode = CatchupMode.none,
    this.template = '',
    this.days = 0,
  });

  final CatchupMode mode;

  /// For [CatchupMode.template]: the URL pattern with `{utc}`, `{lutc}`,
  /// `{start}` and `{end}` placeholders.
  final String template;

  /// How many days of catch-up the provider keeps. 0 when unspecified.
  final int days;

  bool get isSupported => mode != CatchupMode.none;
  bool get hasArchive => days > 0;

  /// Whether [when] falls inside the provider's retention window. An unknown
  /// window (0 days) is treated as "ask the provider" — the request may still
  /// work, and refusing locally would hide a channel that does.
  bool covers(DateTime when, {DateTime? now}) {
    if (days <= 0) return true;
    final n = now ?? DateTime.now();
    final age = n.difference(when);
    return !age.isNegative && age.inDays < days;
  }

  static const CatchupSpec none = CatchupSpec();

  /// Parse the catch-up attributes from an M3U channel line.
  ///
  /// Providers write these in the wild in several shapes:
  ///   catchup="default"  catchup-source="…?utc={utc}"  catchup-days="7"
  ///   catchup="append"   catchup-correction="-2"
  ///   catchup="shift"    (Flussonic path style)
  static CatchupSpec fromM3u(Map<String, String> attrs) {
    final days = int.tryParse(attrs['catchup-days'] ?? '') ?? 0;
    final source = attrs['catchup-source'] ?? '';
    final kind = (attrs['catchup'] ?? '').toLowerCase().trim();

    if (source.isNotEmpty && source.contains('{')) {
      return CatchupSpec(
        mode: CatchupMode.template,
        template: source,
        days: days,
      );
    }
    if (kind == 'shift' || kind == 'flussonic') {
      return CatchupSpec(mode: CatchupMode.pathOffset, days: days);
    }
    if (kind.isNotEmpty && kind != 'none' && kind != 'false') {
      // "default", "append", "1", "true" — all mean the query form.
      return CatchupSpec(mode: CatchupMode.appendQuery, days: days);
    }
    if (source.isNotEmpty) {
      return CatchupSpec(
        mode: CatchupMode.template,
        template: source,
        days: days,
      );
    }
    return CatchupSpec(days: days);
  }
}

/// Build a catch-up URL for [when] from a channel's [liveUrl].
///
/// Returns null when the provider declares no catch-up, or when [when] is
/// outside the retention window — better to say "not available" than to hand
/// the player a URL that 404s.
String? buildCatchupUrl({
  required String liveUrl,
  required CatchupSpec spec,
  required DateTime when,
  DateTime? now,
  int durationMinutes = 0,
}) {
  if (!spec.isSupported) return null;
  final at = when.toUtc();
  final ref = (now ?? DateTime.now()).toUtc();
  if (!spec.covers(at, now: ref)) return null;

  final utc = at.millisecondsSinceEpoch ~/ 1000;
  final lutc = ref.millisecondsSinceEpoch ~/ 1000;
  final start = at;
  final end = at.add(Duration(minutes: durationMinutes));

  switch (spec.mode) {
    case CatchupMode.none:
      return null;

    case CatchupMode.appendQuery:
      final sep = liveUrl.contains('?') ? '&' : '?';
      return '$liveUrl${sep}utc=$utc&lutc=$lutc';

    case CatchupMode.pathOffset:
      // Flussonic: /<offset seconds from now>/<duration seconds>/index.m3u8
      final offset = ref.difference(at).inSeconds;
      final duration = durationMinutes > 0 ? durationMinutes * 60 : 3600;
      final base = liveUrl.endsWith('/')
          ? liveUrl.substring(0, liveUrl.length - 1)
          : liveUrl;
      return '$base/$offset/$duration/index.m3u8';

    case CatchupMode.template:
      var out = spec.template;
      if (!out.startsWith('http')) {
        // A relative template resolves against the live URL's origin.
        final uri = Uri.tryParse(liveUrl);
        if (uri == null) return null;
        out = '${uri.scheme}://${uri.authority}'
            '${out.startsWith('/') ? '' : '/'}$out';
      }
      return out
          .replaceAll('{utc}', '$utc')
          .replaceAll('{lutc}', '$lutc')
          .replaceAll('{start}', start.toIso8601String())
          .replaceAll('{end}', end.toIso8601String())
          .replaceAll('{start_timestamp}', '$utc')
          .replaceAll('{end_timestamp}', '${end.millisecondsSinceEpoch ~/ 1000}')
          .replaceAll('{duration}', '${durationMinutes * 60}');
  }
}

/// Parse a `#EXTINF` attribute list into a map.
///
/// M3U attributes are `key="value"` pairs after the comma-separated duration;
/// values may contain spaces and `=` but not an unescaped quote. A hand-written
/// regex beats a full parser here because provider files are frequently
/// slightly malformed and we want the pairs we can read, not an exception.
Map<String, String> parseM3uAttributes(String extinf) {
  final out = <String, String>{};
  final re = RegExp(r'([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"');
  for (final m in re.allMatches(extinf)) {
    out[m.group(1)!.toLowerCase()] = m.group(2)!;
  }
  return out;
}

/// A channel's catch-up availability, decoded from its M3U attributes and
/// carried alongside the channel.
class CatchupInfo {
  const CatchupInfo({
    required this.spec,
    this.correctionSeconds = 0,
  });

  final CatchupSpec spec;

  /// Providers sometimes publish times a few seconds off; `catchup-correction`
  /// shifts the requested start so the replay lands on the programme, not in
  /// the ad break before it.
  final int correctionSeconds;

  bool get isAvailable => spec.isSupported;

  /// Build the URL, applying [correctionSeconds].
  String? urlFor({
    required String liveUrl,
    required DateTime when,
    DateTime? now,
    int durationMinutes = 0,
  }) => buildCatchupUrl(
    liveUrl: liveUrl,
    spec: spec,
    when: when.add(Duration(seconds: correctionSeconds)),
    now: now,
    durationMinutes: durationMinutes,
  );

  static const CatchupInfo unavailable = CatchupInfo(spec: CatchupSpec.none);

  factory CatchupInfo.fromM3u(String extinf) {
    final attrs = parseM3uAttributes(extinf);
    return CatchupInfo(
      spec: CatchupSpec.fromM3u(attrs),
      correctionSeconds:
          int.tryParse(attrs['catchup-correction'] ?? '') ?? 0,
    );
  }
}

/// Encode/decode catch-up declarations for the source cache.
String encodeCatchup(CatchupInfo info) => jsonEncode({
  'mode': info.spec.mode.name,
  'template': info.spec.template,
  'days': info.spec.days,
  'correction': info.correctionSeconds,
});

CatchupInfo decodeCatchup(String raw) {
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return CatchupInfo.unavailable;
    return CatchupInfo(
      spec: CatchupSpec(
        mode: CatchupMode.values.firstWhere(
          (m) => m.name == j['mode'],
          orElse: () => CatchupMode.none,
        ),
        template: '${j['template'] ?? ''}',
        days: (j['days'] as num?)?.toInt() ?? 0,
      ),
      correctionSeconds: (j['correction'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    return CatchupInfo.unavailable;
  }
}
