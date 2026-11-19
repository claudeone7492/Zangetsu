import 'dart:async';
import 'dart:io' show gzip;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'xmltv_parser.dart';

/// Where a guide comes from and how long it is trusted.
class EpgSource {
  const EpgSource({
    required this.url,
    this.name = '',
    this.channelIdPrefix = '',
    this.maxAgeHours = 12,
  });

  /// XMLTV (`.xml`/`.xmltv`) document URL. Gzipped guides are fetched and
  /// decoded by Dio transparently.
  final String url;

  /// Human label for Settings ("Freeview UK", "epg.pw").
  final String name;

  /// Prefix prepended to a guide's own channel ids when matching. Some
  /// playlists namespace their `tvg-id`s (`iptv-org` uses bare ids, others
  /// prefix the country), so a source can declare the mapping instead of
  /// shipping a rewritten guide.
  final String channelIdPrefix;

  /// How stale a cached copy may get before a refresh is attempted.
  final int maxAgeHours;

  Map<String, dynamic> toJson() => {
    'url': url,
    if (name.isNotEmpty) 'name': name,
    if (channelIdPrefix.isNotEmpty) 'channelIdPrefix': channelIdPrefix,
    'maxAgeHours': maxAgeHours,
  };

  factory EpgSource.fromJson(Map<String, dynamic> j) => EpgSource(
    url: (j['url'] as String).trim(),
    name: (j['name'] as String?) ?? '',
    channelIdPrefix: (j['channelIdPrefix'] as String?) ?? '',
    maxAgeHours: (j['maxAgeHours'] as num?)?.toInt() ?? 12,
  );
}

/// The EPG cache: fetch a set of XMLTV guides, merge them, persist the result,
/// and answer "what's on this channel now / next / tonight".
///
/// Mirrors the shape of the other stores in `core/live`: a `ChangeNotifier`
/// over one Hive box, refreshed in the background, read synchronously by the UI.
/// Guides are cached rather than fetched per view because a full XMLTV file is
/// several megabytes and every channel row would otherwise re-download it.
class EpgStore extends ChangeNotifier {
  EpgStore({required Dio dio}) : _dio = dio;

  static const String boxName = 'epg_guides';

  /// Guides shipped by default so a fresh install has a populated TV guide
  /// with nothing for the user to configure. All are public, no-key feeds.
  static const List<EpgSource> kDefaultSources = [
    EpgSource(
      url: 'https://iptv-org.github.io/epg/guides/uk.xml',
      name: 'United Kingdom',
    ),
    EpgSource(
      url: 'https://iptv-org.github.io/epg/guides/us.xml',
      name: 'United States',
    ),
    EpgSource(
      url: 'https://iptv-org.github.io/epg/guides/in.xml',
      name: 'India',
    ),
    EpgSource(
      url: 'https://iptv-org.github.io/epg/guides/ca.xml',
      name: 'Canada',
    ),
  ];

  final Dio _dio;
  final XmltvParser _parser = const XmltvParser();

  final List<EpgSource> _sources = [];
  EpgGuide _guide = EpgGuide(channelNames: {}, programmes: {});
  final Map<String, DateTime> _fetchedAt = {};
  final Set<String> _refreshing = {};
  var _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    final box = await _box();
    final rawSources = box.get('__sources__');
    if (rawSources is List) {
      for (final raw in rawSources) {
        if (raw is Map) {
          try {
            _sources.add(EpgSource.fromJson(Map<String, dynamic>.from(raw)));
          } catch (e) {
            debugPrint('[epg] stored source invalid, dropping: $e');
          }
        }
      }
    }
    final rawGuide = box.get('__guide__');
    if (rawGuide is Map) {
      try {
        _guide = EpgGuide.fromJson(Map<String, dynamic>.from(rawGuide));
      } catch (e) {
        debugPrint('[epg] stored guide unreadable, starting empty: $e');
      }
    }
    final rawTimes = box.get('__fetched__');
    if (rawTimes is Map) {
      for (final e in rawTimes.entries) {
        final parsed = DateTime.tryParse('${e.value}');
        if (parsed != null) _fetchedAt['${e.key}'] = parsed;
      }
    }
    _initialized = true;
  }

  List<EpgSource> get sources => List.unmodifiable(_sources);
  EpgGuide get guide => _guide;
  bool get isEmpty => _guide.isEmpty;
  bool isRefreshing(String url) => _refreshing.contains(url);

  /// True when [url]'s cached copy is older than its [EpgSource.maxAgeHours].
  bool isStale(EpgSource source) {
    final at = _fetchedAt[source.url];
    if (at == null) return true;
    return DateTime.now().difference(at).inHours >= source.maxAgeHours;
  }

  /// Everything currently cached for [channelId], sorted by start.
  List<EpgProgramme> schedule(String channelId) =>
      _guide.programmes[channelId] ?? const [];

  EpgProgramme? nowOn(String channelId, {DateTime? at}) =>
      _guide.nowOn(channelId, at: at);

  EpgProgramme? nextOn(String channelId, {DateTime? at}) =>
      _guide.nextOn(channelId, at: at);

  /// The next [hours] of programming for [channelId] — the guide grid's row.
  List<EpgProgramme> upcoming(String channelId, {int hours = 6}) => _guide
      .between(
        channelId,
        from: DateTime.now().toUtc(),
        to: DateTime.now().toUtc().add(Duration(hours: hours)),
      )
      .toList();

  /// Resolves a playlist channel to the guide's channel id.
  ///
  /// Playlists name a channel three different ways — `tvg-id`, `tvg-name`, or
  /// only a display name — so matching tries the id first, then the guide's own
  /// display names. Returns null when the guide simply doesn't cover it, which
  /// is the normal case for most of the long tail of IPTV channels.
  String? resolveChannelId({
    String? tvgId,
    String? tvgName,
    String? displayName,
  }) {
    final candidates = [
      if (tvgId != null && tvgId.trim().isNotEmpty) tvgId.trim(),
      if (tvgName != null && tvgName.trim().isNotEmpty) tvgName.trim(),
      if (displayName != null && displayName.trim().isNotEmpty)
        displayName.trim(),
    ];
    if (candidates.isEmpty) return null;

    for (final candidate in candidates) {
      if (_guide.programmes.containsKey(candidate)) return candidate;
      for (final source in _sources) {
        final prefixed = '${source.channelIdPrefix}$candidate';
        if (source.channelIdPrefix.isNotEmpty &&
            _guide.programmes.containsKey(prefixed)) {
          return prefixed;
        }
      }
    }

    // Fall back to a display-name match, case-insensitively.
    final wanted = candidates.map((c) => c.toLowerCase()).toSet();
    for (final entry in _guide.channelNames.entries) {
      for (final name in entry.value) {
        if (wanted.contains(name.trim().toLowerCase())) {
          if (_guide.programmes.containsKey(entry.key)) return entry.key;
        }
      }
    }
    return null;
  }

  /// Add a guide source. Idempotent on the URL. The guide is fetched straight
  /// away so the caller can report success.
  Future<bool> addSource(EpgSource source) async {
    if (_sources.any((s) => s.url == source.url)) return false;
    _sources.add(source);
    await _persistSources();
    notifyListeners();
    return refresh(source: source);
  }

  Future<void> removeSource(String url) async {
    _sources.removeWhere((s) => s.url == url);
    _fetchedAt.remove(url);
    await _persistSources();
    notifyListeners();
  }

  /// Install the shipped defaults (idempotent, and a no-op once any source is
  /// configured so a user who removed one doesn't get it back every boot).
  Future<void> installDefaults() async {
    if (_sources.isNotEmpty) return;
    _sources.addAll(kDefaultSources);
    await _persistSources();
    notifyListeners();
  }

  /// Fetch and merge every stale guide. Safe to call on every guide open: a
  /// fresh cache short-circuits and an in-flight fetch is not restarted.
  Future<void> refreshAll() async {
    final stale = _sources.where(isStale).toList();
    for (final source in stale) {
      await refresh(source: source);
    }
  }

  /// Fetch one source and merge its programmes into the cached guide.
  ///
  /// Returns false when the fetch failed (the previous cache is kept, so a
  /// transient network failure never blanks the guide). A source already
  /// being refreshed is not fetched twice concurrently.
  Future<bool> refresh({EpgSource? source}) async {
    final targets = source != null ? [source] : _sources;
    var anySucceeded = false;
    for (final s in targets) {
      if (!_refreshing.add(s.url)) continue;
      notifyListeners();
      try {
        final res = await _dio.get<List<int>>(
          s.url,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (c) => c != null && c < 400,
          ),
        );
        final bytes = res.data ?? const <int>[];
        if (bytes.isEmpty) continue;
        final parsed = _parser.parse(_decode(bytes));
        if (parsed.isEmpty) continue;

        // Merge per channel: the freshest guide wins for the channels it
        // covers, while channels only the old cache knew about survive.
        final merged = Map<String, List<EpgProgramme>>.from(
          _guide.programmes,
        );
        for (final entry in parsed.programmes.entries) {
          final id = '${s.channelIdPrefix}${entry.key}';
          merged[id] = entry.value;
        }
        final names = Map<String, List<String>>.from(_guide.channelNames);
        for (final entry in parsed.channelNames.entries) {
          names['${s.channelIdPrefix}${entry.key}'] = entry.value;
        }
        _guide = EpgGuide(channelNames: names, programmes: merged);
        _fetchedAt[s.url] = DateTime.now();
        anySucceeded = true;
      } catch (e) {
        debugPrint('[epg] fetch failed for ${s.url}: $e');
      } finally {
        _refreshing.remove(s.url);
        notifyListeners();
      }
    }
    if (anySucceeded) await _persist();
    return anySucceeded;
  }

  /// Decode a guide body. Handles plain XML and gzip (many XMLTV feeds are
  /// served gzipped without the transport doing it for us).
  String _decode(List<int> bytes) {
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return String.fromCharCodes(gzip.decode(bytes));
    }
    return String.fromCharCodes(bytes);
  }

  Future<void> clear() async {
    _guide = EpgGuide(channelNames: {}, programmes: {});
    _fetchedAt.clear();
    final box = await _box();
    await box.delete('__guide__');
    await box.delete('__fetched__');
    notifyListeners();
  }

  Future<Box> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box(boxName)
      : await openBoxSafely<dynamic>(boxName);

  Future<void> _persistSources() async {
    final box = await _box();
    await box.put('__sources__', [for (final s in _sources) s.toJson()]);
  }

  Future<void> _persist() async {
    final box = await _box();
    await box.put('__guide__', _guide.toJson());
    await box.put('__fetched__', {
      for (final e in _fetchedAt.entries) e.key: e.value.toIso8601String(),
    });
  }
}
