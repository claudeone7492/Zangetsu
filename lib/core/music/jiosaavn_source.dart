import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'music_config.dart';
import 'music_models.dart';
import 'music_prefs.dart';
import 'music_source.dart';

/// JioSaavn catalogue via the public `saavn.dev` API.
///
/// Chosen because it is keyless and reachable from the app with no user
/// account, which is what keeps music mode zero-input like the other modes. The
/// endpoints return JSON whose `data.results` / `data` fields hold the songs;
/// the parsing below is deliberately tolerant because the API is a community
/// mirror and its field names drift.
///
/// JioSaavn's `downloadUrl` entries are signed and expire (the API states an
/// `expiresAt`), which is why [streamFor] re-resolves by id instead of replaying
/// a URL from a cached listing.
class JioSaavnSource implements MusicSource {
  JioSaavnSource({
    Dio? dio,
    String? baseUrl,
    MusicQuality Function()? quality,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 20),
               headers: const {'Accept': 'application/json'},
             ),
           ),
       _baseUrl = baseUrl ?? kMusicApiBaseUrl,
       // Read per track, not captured once: the user can change quality while
       // a listing is already on screen, and the next track must honour it.
       _quality = quality ?? (() => MusicPrefs.quality);

  final Dio _dio;
  final String _baseUrl;
  final MusicQuality Function() _quality;

  @override
  String get id => kMusicSourceId;

  @override
  String get displayName => kMusicSourceName;

  @override
  bool get isConfigured => true;

  @override
  Future<List<MusicSection>> home() async {
    // Rows come from the shared config, so the catalogue, the service and the
    // UI never disagree about which rows exist or what they are called.
    final results = await Future.wait([
      for (final row in kMusicHomeRows)
        _section(
          row,
          () => _get('search/songs', {
            'query': row.query,
            'limit': kMusicRowLimit,
          }),
        ),
    ]);
    return results
        .where((s) => s != null && !s.isEmpty)
        .cast<MusicSection>()
        .toList();
  }

  Future<MusicSection?> _section(
    MusicHomeRow row,
    Future<List<MusicTrack>> Function() fetch,
  ) async {
    try {
      final tracks = await fetch();
      if (tracks.isEmpty) return null;
      return MusicSection(id: row.id, title: row.fallbackTitle, tracks: tracks);
    } catch (e) {
      // One dead row must not sink the page — same rule the video home uses.
      debugPrint('[music] row "${row.id}" failed: $e');
      return null;
    }
  }

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    return _get('search/songs', {
      'query': trimmed,
      'page': page,
      'limit': kMusicSearchLimit,
    });
  }

  @override
  Future<String?> streamFor(MusicTrack track) async {
    if (track.hasFreshStream) return track.streamUrl;
    try {
      final tracks = await _get('songs/${track.id}', null);
      if (tracks.isEmpty) return track.streamUrl;
      return tracks.first.streamUrl ?? track.streamUrl;
    } catch (e) {
      debugPrint('[music] refresh failed for ${track.id}: $e');
      // A stale URL sometimes still plays; better than nothing when refresh fails.
      return track.streamUrl;
    }
  }

  /// GET a path and parse whatever song list it returns.
  ///
  /// Tolerant by design: `search/songs` nests under `data.results`, the
  /// by-id endpoint returns a bare list under `data`, and a single-song
  /// response uses `data` as an object. All three are handled.
  Future<List<MusicTrack>> _get(
    String path,
    Map<String, dynamic>? query,
  ) async {
    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        '$_baseUrl/$path',
        queryParameters: query,
      );
    } on DioException catch (e) {
      throw MusicSourceException('Could not reach $displayName.', cause: e);
    }
    return _parseTracks(response.data);
  }

  List<MusicTrack> _parseTracks(dynamic payload) {
    final data = payload is Map<String, dynamic> ? payload['data'] : payload;
    dynamic raw;
    if (data is Map<String, dynamic>) {
      raw = data['results'] ?? data['songs'] ?? data['data'];
      // A single song object rather than a list.
      if (raw == null && (data['id'] != null || data['name'] != null)) {
        raw = data;
      }
    } else {
      raw = data;
    }
    final list = raw is List ? raw : (raw is Map ? [raw] : const []);
    final out = <MusicTrack>[];
    for (final entry in list) {
      if (entry is! Map) continue;
      final track = _parseTrack(Map<String, dynamic>.from(entry));
      if (track != null) out.add(track);
    }
    return out;
  }

  MusicTrack? _parseTrack(Map<String, dynamic> json) {
    final id = _asString(json['id']);
    final title = _asString(json['name'] ?? json['title']);
    if (id == null || title == null) return null;

    return MusicTrack(
      id: id,
      title: _decodeEntities(title),
      // This catalogue's own id — `this.id`, since the local `id` above is
      // the track's. A second catalogue must stamp its own tracks, because the
      // service routes playback back to a source by it.
      sourceId: this.id,
      artist: _artistOf(json),
      album: _asString(json['album']?['name'] ?? json['album']),
      artwork: _artworkOf(json),
      duration: _durationOf(json),
      year: _asInt(json['year']),
      language: _asString(json['language']),
      streamUrl: _streamOf(json, _quality()),
      streamExpiresAt: _expiryOf(json),
    );
  }

  /// `primaryArtists` is usually a comma-joined string, but some entries carry a
  /// list of `{name: …}` objects instead.
  static String? _artistOf(Map<String, dynamic> json) {
    final primary = json['primaryArtists'] ?? json['primaryArtistsId'];
    if (primary is String && primary.trim().isNotEmpty) {
      return _decodeEntities(primary);
    }
    final featured = json['featuredArtists'];
    if (featured is String && featured.trim().isNotEmpty) {
      return _decodeEntities(featured);
    }
    final artists = json['artists'];
    if (artists is Map && artists['primary'] is List) {
      final names = [
        for (final a in artists['primary'] as List)
          if (a is Map && a['name'] is String) a['name'] as String,
      ];
      if (names.isNotEmpty) return names.join(', ');
    }
    return null;
  }

  /// Artwork arrives as a list of `{quality, url}` (newest) or a `{quality: url}`
  /// map (older). Both are ordered smallest-first, so take the largest.
  static String? _artworkOf(Map<String, dynamic> json) {
    final image = json['image'];
    if (image is String && image.isNotEmpty) return image;
    if (image is List) {
      String? best;
      var bestSize = -1;
      for (final entry in image) {
        if (entry is! Map || entry['url'] is! String) continue;
        final url = entry['url'] as String;
        if (url.isEmpty) continue;
        final size = _bitrateOf(entry['quality']); // same "first number" parse
        if (size > bestSize) {
          bestSize = size;
          best = url;
        }
      }
      return best;
    }
    if (image is Map) {
      for (final key in const ['500x500', '150x150', '50x50']) {
        final url = image[key];
        if (url is String && url.isNotEmpty) return url;
      }
    }
    return null;
  }

  static Duration? _durationOf(Map<String, dynamic> json) {
    final seconds = _asInt(json['duration']);
    return seconds == null || seconds <= 0 ? null : Duration(seconds: seconds);
  }

  /// `downloadUrl` is a list of `{quality, url}`; older responses used a
  /// `{quality: url}` map.
  ///
  /// Saavn lists these LOWEST bitrate first (12kbps → 320kbps), so taking the
  /// first URL — the obvious reading — hands the player the worst copy of every
  /// song. Pick the best encoding the user's [MusicQuality] allows instead.
  ///
  /// Two fallbacks keep every song playable: an entry whose quality does not
  /// parse still counts (so a response with no labels behaves as before), and
  /// when nothing is at or below the ceiling the lowest advertised encoding is
  /// used rather than returning nothing.
  static String? _streamOf(Map<String, dynamic> json, MusicQuality quality) {
    final urls = json['downloadUrl'] ?? json['download_url'];
    final entries = <(int, String)>[];
    if (urls is List) {
      for (final entry in urls) {
        if (entry is! Map) continue;
        final url = entry['url'];
        if (url is! String || url.isEmpty) continue;
        entries.add((_bitrateOf(entry['quality']), url));
      }
    } else if (urls is Map) {
      for (final entry in urls.entries) {
        final url = entry.value;
        if (url is! String || url.isEmpty) continue;
        entries.add((_bitrateOf(entry.key), url));
      }
    } else if (urls is String && urls.isNotEmpty) {
      return urls;
    }
    if (entries.isEmpty) return null;
    return _pick(entries, quality.kbps);
  }

  /// The best of [entries] at or below [ceiling] kbps, else the smallest.
  ///
  /// Split out from [_streamOf] so the selection rule is testable without a
  /// response shape around it.
  @visibleForTesting
  static String? pickForQuality(List<(int, String)> entries, int ceiling) {
    if (entries.isEmpty) return null;
    (int, String)? best;
    (int, String)? smallest;
    for (final entry in entries) {
      // An unlabelled entry (-1) is treated as "any quality" so a response
      // that stopped advertising bitrates still plays.
      final bitrate = entry.$1 < 0 ? ceiling : entry.$1;
      if (bitrate <= ceiling && (best == null || bitrate > best.$1)) {
        best = (bitrate, entry.$2);
      }
      if (smallest == null || bitrate < smallest.$1) {
        smallest = (bitrate, entry.$2);
      }
    }
    return (best ?? smallest)?.$2;
  }

  static String? _pick(List<(int, String)> entries, int ceiling) =>
      pickForQuality(entries, ceiling);

  /// `"320kbps"` → 320. Returns -1 when the label carries no number, so a
  /// labelled entry always outranks an unlabelled one.
  static int _bitrateOf(Object? quality) {
    if (quality is! String) return -1;
    final match = RegExp(r'(\d+)').firstMatch(quality);
    return match == null ? -1 : int.tryParse(match.group(1)!) ?? -1;
  }

  static DateTime? _expiryOf(Map<String, dynamic> json) {
    final raw = json['expiresAt'] ?? json['expires_at'];
    final seconds = _asInt(raw);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is double) return value.toInt();
    return null;
  }

  static String? _asString(Object? value) {
    if (value is String && value.trim().isNotEmpty) return value.trim();
    if (value is num) return value.toString();
    return null;
  }

  /// Titles come back HTML-escaped (`&amp;`, `&#39;`). Decoding them here means
  /// every screen and the media notification show the real characters.
  static String _decodeEntities(String value) {
    if (!value.contains('&')) return value;
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }
}
