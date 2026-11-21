import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hive/safe_box.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../models/watch_status.dart';
import 'tracker.dart';

/// The device-code handshake Trakt's OAuth needs the user to see.
class TraktDeviceLogin {
  const TraktDeviceLogin({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    required this.intervalSec,
    required this.expiresInSec,
  });

  final String deviceCode;
  final String userCode;
  final String verificationUrl;
  final int intervalSec;
  final int expiresInSec;
}

/// Trakt tracker (films + series).
///
/// Device-code OAuth: no redirect URI, so the flow works on a phone and a TV
/// alike. The app ships a client id (Trakt calls these "API apps"); it is not
/// a secret and the device flow does not need the matching secret. Access
/// tokens last 90 days; this build does not refresh them because a refresh
/// needs that secret, so the account is re-linked when Trakt returns 401.
///
/// Trakt has no per-title "watching"/"paused" status: watching is derived from
/// history. [setStatus] therefore writes the watchlist for planning, history
/// for completed, and leaves watching/paused to the first scrobble.
class TraktService extends ChangeNotifier implements Tracker {
  TraktService(this._dio);

  final Dio _dio;

  static const String boxName = 'trakt';
  static const String clientId =
      'xEjFc5nG3iAzqghfVK_uaJFD6vkJedqZLNxyFnltz-M';
  static const String _api = 'https://api.trakt.tv';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
  }

  Box get _box => Hive.box(boxName);

  List<TrackerListItem>? _cache;
  DateTime? _cacheAt;

  @override
  String get displayName => 'Trakt';

  @override
  bool get supportsReading => false; // no manga/novel catalogue

  @override
  bool get isConnected =>
      (_box.get('accessToken') as String?)?.isNotEmpty == true &&
      _box.get('viewerName') != null;

  @override
  String? get viewerName => _box.get('viewerName') as String?;

  @override
  String? get viewerAvatar => _box.get('viewerAvatar') as String?;

  @override
  bool get autoSync => (_box.get('autoSync') as bool?) ?? true;

  @override
  set autoSync(bool value) {
    _box.put('autoSync', value);
    notifyListeners();
  }

  Map<String, String> get _publicHeaders => const {
    'trakt-api-key': clientId,
    'trakt-api-version': '2',
    'Content-Type': 'application/json',
  };

  Map<String, String> get _headers => {
    ..._publicHeaders,
    if ((_box.get('accessToken') as String?)?.isNotEmpty == true)
      'Authorization': 'Bearer ${_box.get('accessToken')}',
  };

  // ── Device-code sign-in ─────────────────────────────────────────────────────

  Future<TraktDeviceLogin?> beginDeviceLogin() async {
    final res = await _post(
      '/oauth/device/code',
      {'client_id': clientId},
      auth: false,
    );
    return deviceLoginFrom(res?.data);
  }

  @visibleForTesting
  static TraktDeviceLogin? deviceLoginFrom(Object? data) {
    if (data is! Map) return null;
    final deviceCode = '${data['device_code'] ?? ''}';
    final userCode = '${data['user_code'] ?? ''}';
    if (deviceCode.isEmpty || userCode.isEmpty) return null;
    return TraktDeviceLogin(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUrl: '${data['verification_url'] ?? 'https://trakt.tv/activate'}',
      intervalSec: (data['interval'] as num?)?.toInt() ?? 5,
      expiresInSec: (data['expires_in'] as num?)?.toInt() ?? 600,
    );
  }

  /// Polls until the code is approved, refused, or expires.
  Future<bool> pollDeviceLogin(TraktDeviceLogin login) async {
    final deadline = DateTime.now().add(Duration(seconds: login.expiresInSec));
    var wait = Duration(seconds: login.intervalSec.clamp(2, 30));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(wait);
      final res = await _post(
        '/oauth/device/token',
        {'code': login.deviceCode, 'client_id': clientId},
        auth: false,
      );
      if (res == null) return false;
      final data = res.data;
      final token = (data is Map) ? '${data['access_token'] ?? ''}' : '';
      if (token.isNotEmpty) {
        await _box.put('accessToken', token);
        final refresh = (data is Map) ? '${data['refresh_token'] ?? ''}' : '';
        if (refresh.isNotEmpty) await _box.put('refreshToken', refresh);
        final expiresIn =
            (data is Map) ? (data['expires_in'] as num?)?.toInt() ?? 0 : 0;
        if (expiresIn > 0) {
          await _box.put(
            'expiresAt',
            DateTime.now().millisecondsSinceEpoch + expiresIn * 1000,
          );
        }
        await _fetchViewer();
        notifyListeners();
        return viewerName != null;
      }
      switch (res.statusCode) {
        case 400: // authorization_pending
          continue;
        case 429: // slow_down
          wait = Duration(seconds: (wait.inSeconds + 5).clamp(2, 60));
          continue;
        case 409:
        case 410:
        case 418:
          return false;
        default:
          return false;
      }
    }
    return false;
  }

  @override
  Future<bool> connect() async {
    final login = await beginDeviceLogin();
    if (login == null) return false;
    // Copying the code means the generic call sites still work without a
    // dialog: the user pastes it on trakt.tv/activate.
    await Clipboard.setData(ClipboardData(text: login.userCode));
    await launchUrl(
      Uri.parse(login.verificationUrl),
      mode: LaunchMode.externalApplication,
    );
    return pollDeviceLogin(login);
  }

  Future<void> _fetchViewer() async {
    final res = await _get('/users/me?extended=full');
    final data = res?.data;
    if (data is! Map) return;
    final name = '${data['username'] ?? ''}';
    if (name.isNotEmpty) await _box.put('viewerName', name);
    final images = data['images'];
    if (images is Map) {
      final avatar = images['avatar'];
      if (avatar is Map && avatar['full'] is String) {
        await _box.put('viewerAvatar', avatar['full']);
      }
    }
  }

  @override
  Future<void> disconnect() async {
    for (final k in const [
      'accessToken',
      'refreshToken',
      'expiresAt',
      'viewerName',
      'viewerAvatar',
    ]) {
      await _box.delete(k);
    }
    _cache = null;
    notifyListeners();
  }

  // ── HTTP ────────────────────────────────────────────────────────────────────

  Future<Response<dynamic>?> _get(String path) async {
    try {
      final res = await _dio.get<dynamic>(
        '$_api$path',
        options: Options(
          headers: _headers,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return _check(res);
    } catch (e) {
      debugPrint('[trakt] GET $path failed: $e');
      return null;
    }
  }

  Future<Response<dynamic>?> _post(
    String path,
    Object? data, {
    bool auth = true,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '$_api$path',
        data: data,
        options: Options(
          headers: auth ? _headers : _publicHeaders,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return _check(res);
    } catch (e) {
      debugPrint('[trakt] POST $path failed: $e');
      return null;
    }
  }

  Response<dynamic>? _check(Response<dynamic> res) {
    if (res.statusCode == 401) {
      unawaited(disconnect());
      return null;
    }
    return res;
  }

  // ── Id resolution ───────────────────────────────────────────────────────────

  /// Trakt does not accept MAL ids. A pinned id wins; otherwise TMDB/IMDb are
  /// looked up, and a title search is the last resort (anime often has only a
  /// MAL id at the call site).
  Future<int?> _resolveId({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    String? pinnedId,
    MediaKind kind = MediaKind.anime,
  }) async {
    final pinned = int.tryParse(pinnedId ?? '');
    if (pinned != null) return pinned;
    final type = kind == MediaKind.movie ? 'movie' : 'show';
    final id = await _resolveFor(
      type,
      tmdbId: tmdbId,
      imdbId: imdbId,
      title: title,
    );
    if (id != null) return id;
    // An anime film is filed under movies on Trakt, but the call site only
    // says "anime"; retry the same ids/title against the movie catalogue.
    if (kind == MediaKind.anime) {
      return _resolveFor(
        'movie',
        tmdbId: tmdbId,
        imdbId: imdbId,
        title: title,
      );
    }
    return null;
  }

  Future<int?> _resolveFor(
    String type, {
    int? tmdbId,
    String? imdbId,
    String? title,
  }) async {
    if (imdbId != null && imdbId.isNotEmpty) {
      final id = await _lookup('/search/imdb/$imdbId?type=$type', type);
      if (id != null) return id;
    }
    if (tmdbId != null && tmdbId > 0) {
      final id = await _lookup('/search/tmdb/$tmdbId?type=$type', type);
      if (id != null) return id;
    }
    final q = (title ?? '').trim();
    if (q.isNotEmpty) {
      return _lookup(
        '/search/$type?query=${Uri.encodeComponent(q)}&limit=5&extended=full',
        type,
      );
    }
    return null;
  }

  Future<int?> _lookup(String path, String kind) async {
    final res = await _get(path);
    final data = res?.data;
    if (data is! List) return null;
    for (final entry in data) {
      if (entry is! Map) continue;
      final node = entry[kind];
      if (node is! Map) continue;
      final ids = node['ids'];
      final id = ids is Map ? _asInt(ids['trakt']) : null;
      if (id != null) return id;
    }
    return null;
  }

  // ── Writes ──────────────────────────────────────────────────────────────────

  @override
  Future<void> markWatching({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    MediaKind kind = MediaKind.anime,
  }) async {
    // Trakt derives "watching" from history; the first scrobble is what makes
    // a title current. There is no separate list write to send here.
  }

  @override
  Future<void> scrobble({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    required int episode,
    int? season,
    int? seasonEpisode,
    MediaKind kind = MediaKind.anime,
    bool novel = false,
  }) async {
    if (!isConnected || !autoSync || episode <= 0) return;
    final id = await _resolveId(
      malId: malId,
      title: title,
      tmdbId: tmdbId,
      tmdbIsTv: tmdbIsTv,
      imdbId: imdbId,
      kind: kind,
    );
    if (id == null) return;
    final body = historyBody(
      traktId: id,
      movie: kind == MediaKind.movie,
      season: season,
      episode: seasonEpisode ?? episode,
    );
    if (body != null) await _post('/sync/history', body);
    invalidateListCache();
  }

  @visibleForTesting
  static Map<String, dynamic>? historyBody({
    required int traktId,
    required bool movie,
    int? season,
    int? episode,
  }) {
    final ids = {'trakt': traktId};
    if (movie) return {'movies': [{'ids': ids}]};
    final ep = (episode != null && episode > 0) ? episode : 1;
    final s = (season != null && season > 0) ? season : 1;
    return {
      'shows': [
        {
          'ids': ids,
          'seasons': [
            {
              'number': s,
              'episodes': [
                {'number': ep},
              ],
            },
          ],
        },
      ],
    };
  }

  @override
  Future<void> setStatus({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    required WatchStatus status,
    MediaKind kind = MediaKind.anime,
  }) async {
    if (!isConnected) return;
    final id = await _resolveId(
      malId: malId,
      title: title,
      tmdbId: tmdbId,
      tmdbIsTv: tmdbIsTv,
      imdbId: imdbId,
      kind: kind,
    );
    if (id == null) return;
    final isMovie = kind == MediaKind.movie;
    final bucket = isMovie ? 'movies' : 'shows';
    final ids = {'trakt': id};
    if (status == WatchStatus.planning) {
      await _post('/sync/watchlist', {
        bucket: [
          {'ids': ids},
        ],
      });
    } else if (status == WatchStatus.completed) {
      await _post('/sync/watchlist/remove', {
        bucket: [
          {'ids': ids},
        ],
      });
      if (isMovie) {
        await _post('/sync/history', historyBody(traktId: id, movie: true));
      } else {
        await _markShowWatched(id);
      }
    } else if (status == WatchStatus.dropped) {
      await _post('/sync/watchlist/remove', {
        bucket: [
          {'ids': ids},
        ],
      });
    }
    // watching/paused: Trakt has no equivalent list; history is the state.
    invalidateListCache();
  }

  /// Marks every aired episode of a show watched, using the progress endpoint
  /// so a completed show does not have to guess its season/episode counts.
  Future<void> _markShowWatched(int id) async {
    final res = await _get('/shows/$id/progress/watched?extended=full');
    final data = res?.data;
    if (data is! Map) return;
    final seasons = data['seasons'];
    if (seasons is! List) return;
    final payload = <Map<String, dynamic>>[];
    for (final season in seasons) {
      if (season is! Map) continue;
      final number = _asInt(season['number']);
      final aired = _asInt(season['aired']);
      if (number == null || aired == null || aired <= 0) continue;
      payload.add({
        'number': number,
        'episodes': [
          for (var n = 1; n <= aired; n++) {'number': n},
        ],
      });
    }
    if (payload.isEmpty) return;
    await _post('/sync/history', {
      'shows': [
        {
          'ids': {'trakt': id},
          'seasons': payload,
        },
      ],
    });
  }

  @override
  Future<void> removeFromList({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    String? pinnedId,
    MediaKind kind = MediaKind.anime,
  }) async {
    if (!isConnected) return;
    final id = await _resolveId(
      malId: malId,
      title: title,
      tmdbId: tmdbId,
      tmdbIsTv: tmdbIsTv,
      imdbId: imdbId,
      pinnedId: pinnedId,
      kind: kind,
    );
    if (id == null) return;
    final bucket = kind == MediaKind.movie ? 'movies' : 'shows';
    final entry = {
      'ids': {'trakt': id},
    };
    await _post('/sync/watchlist/remove', {
      bucket: [entry],
    });
    await _post('/sync/history/remove', {
      bucket: [entry],
    });
    invalidateListCache();
  }

  // ── Library read-back ───────────────────────────────────────────────────────

  @override
  Future<List<TrackerListItem>> fetchList() async {
    if (!isConnected) return const [];
    final at = _cacheAt;
    if (_cache != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return _cache!;
    }
    final movies = await _get('/sync/watched/movies?extended=full,images');
    final shows = await _get('/sync/watched/shows?extended=full,images');
    final watch = await _get(
      '/sync/watchlist/movies,shows?extended=full,images',
    );
    final out = parseList(
      watchedMovies: movies?.data is List ? movies!.data as List : null,
      watchedShows: shows?.data is List ? shows!.data as List : null,
      watchlist: watch?.data is List ? watch!.data as List : null,
    );
    _cache = out;
    _cacheAt = DateTime.now();
    return out;
  }

  @visibleForTesting
  static List<TrackerListItem> parseList({
    List<dynamic>? watchedMovies,
    List<dynamic>? watchedShows,
    List<dynamic>? watchlist,
  }) {
    final out = <TrackerListItem>[];
    final seen = <int>{};

    void addMovie(Map media, {required WatchStatus status, DateTime? updated}) {
      final ids = media['ids'] is Map ? media['ids'] as Map : const {};
      final id = _asInt(ids['trakt']);
      if (id == null || !seen.add(id)) return;
      out.add(
        TrackerListItem(
          item: MediaItem(
            id: 'tracker:trakt:$id',
            title: '${media['title'] ?? 'Unknown'}',
            cover: _poster(media),
            url: '',
            type: ProviderType.movie,
            sourceId: '',
            tmdbId: _asInt(ids['tmdb']),
            imdbId: ids['imdb'] is String ? ids['imdb'] as String : null,
            year: _asInt(media['year']),
          ),
          status: status,
          updatedAt: updated,
        ),
      );
    }

    void addShow(
      Map media, {
      required WatchStatus status,
      int? progress,
      DateTime? updated,
    }) {
      final ids = media['ids'] is Map ? media['ids'] as Map : const {};
      final id = _asInt(ids['trakt']);
      if (id == null || !seen.add(id)) return;
      out.add(
        TrackerListItem(
          item: MediaItem(
            id: 'tracker:trakt:$id',
            title: '${media['title'] ?? 'Unknown'}',
            cover: _poster(media),
            url: '',
            type: ProviderType.movie,
            sourceId: '',
            tmdbId: _asInt(ids['tmdb']),
            imdbId: ids['imdb'] is String ? ids['imdb'] as String : null,
            tmdbIsTv: true,
            year: _asInt(media['year']),
          ),
          status: status,
          progress: progress,
          tmdbIsTv: true,
          totalEpisodes: _asInt(media['aired_episodes']),
          updatedAt: updated,
        ),
      );
    }

    for (final entry in watchedMovies ?? const []) {
      if (entry is! Map) continue;
      final movie = entry['movie'];
      if (movie is Map) {
        addMovie(
          movie,
          status: WatchStatus.completed,
          updated: _date(entry['last_watched_at']),
        );
      }
    }

    for (final entry in watchedShows ?? const []) {
      if (entry is! Map) continue;
      final show = entry['show'];
      if (show is! Map) continue;
      var progress = 0;
      final seasons = entry['seasons'];
      if (seasons is List) {
        for (final season in seasons) {
          if (season is! Map) continue;
          final episodes = season['episodes'];
          if (episodes is! List) continue;
          for (final ep in episodes) {
            if (ep is Map && (_asInt(ep['plays']) ?? 0) > 0) progress++;
          }
        }
      }
      final total = _asInt(show['aired_episodes']) ?? 0;
      addShow(
        show,
        status: total > 0 && progress >= total
            ? WatchStatus.completed
            : WatchStatus.watching,
        progress: progress,
        updated: _date(entry['last_watched_at']),
      );
    }

    for (final entry in watchlist ?? const []) {
      if (entry is! Map) continue;
      final movie = entry['movie'];
      final show = entry['show'];
      final listed = _date(entry['listed_at']);
      if (movie is Map) {
        addMovie(movie, status: WatchStatus.planning, updated: listed);
      }
      if (show is Map) {
        addShow(show, status: WatchStatus.planning, updated: listed);
      }
    }
    return out;
  }

  @override
  Future<TrackerEntry?> fetchEntry({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    String? pinnedId,
    MediaKind kind = MediaKind.anime,
    bool novel = false,
  }) async {
    if (!isConnected) return null;
    final pinned = int.tryParse(pinnedId ?? '');
    final isTv = tmdbIsTv || kind == MediaKind.tv;
    for (final it in await fetchList()) {
      final traktId = int.tryParse(
        it.item.id.replaceFirst('tracker:trakt:', ''),
      );
      final matchesPinned = pinned != null && traktId == pinned;
      final matchesTmdb =
          tmdbId != null && it.item.tmdbId == tmdbId && it.tmdbIsTv == isTv;
      final matchesTitle = tmdbId == null &&
          pinned == null &&
          title != null &&
          it.item.title.toLowerCase() == title.trim().toLowerCase();
      if (matchesPinned || matchesTmdb || matchesTitle) {
        return TrackerEntry(
          trackerName: displayName,
          onList: true,
          url: traktId == null
              ? null
              : 'https://trakt.tv/${it.tmdbIsTv ? 'shows' : 'movies'}/$traktId',
          title: it.item.title,
          status: it.status,
          score: it.score,
          progress: it.progress,
          maxEpisodes: it.totalEpisodes,
        );
      }
    }
    return null;
  }

  @override
  Future<void> updateEntry({
    int? malId,
    String? title,
    int? tmdbId,
    bool tmdbIsTv = false,
    String? imdbId,
    String? pinnedId,
    WatchStatus? status,
    double? score,
    int? progress,
    MediaKind kind = MediaKind.anime,
  }) async {
    if (status != null) {
      await setStatus(
        malId: malId,
        title: title,
        tmdbId: tmdbId,
        tmdbIsTv: tmdbIsTv,
        imdbId: imdbId,
        status: status,
        kind: kind,
      );
    }
    final id = await _resolveId(
      malId: malId,
      title: title,
      tmdbId: tmdbId,
      tmdbIsTv: tmdbIsTv,
      imdbId: imdbId,
      pinnedId: pinnedId,
      kind: kind,
    );
    if (id == null) return;
    final isMovie = kind == MediaKind.movie;
    if (score != null) {
      await _post('/sync/ratings', {
        isMovie ? 'movies' : 'shows': [
          {
            'ids': {'trakt': id},
            'rating': score.round().clamp(1, 10),
          },
        ],
      });
    }
    if (progress != null && progress > 0) {
      if (isMovie) {
        await _post('/sync/history', historyBody(traktId: id, movie: true));
      } else {
        await _post('/sync/history', {
          'shows': [
            {
              'ids': {'trakt': id},
              'seasons': [
                {
                  'number': 1,
                  'episodes': [
                    for (var n = 1; n <= progress; n++) {'number': n},
                  ],
                },
              ],
            },
          ],
        });
      }
    }
    invalidateListCache();
  }

  @override
  Future<List<TrackerSearchResult>> searchEntries(
    String query, {
    MediaKind kind = MediaKind.anime,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final wanted = kind == MediaKind.movie ? 'movie' : 'show';
    final res = await _get(
      '/search/$wanted?query=${Uri.encodeComponent(q)}&limit=12&extended=full',
    );
    final data = res?.data;
    if (data is! List) return const [];
    final out = <TrackerSearchResult>[];
    for (final entry in data) {
      if (entry is! Map) continue;
      final node = entry[wanted];
      if (node is! Map) continue;
      final ids = node['ids'];
      final id = ids is Map ? _asInt(ids['trakt']) : null;
      if (id == null) continue;
      out.add(
        TrackerSearchResult(
          trackerName: displayName,
          id: '$id',
          title: '${node['title'] ?? 'Unknown'}',
          cover: _poster(node),
          subtitle: node['year'] == null ? null : '${node['year']}',
          maxEpisodes: _asInt(node['aired_episodes']),
        ),
      );
    }
    return out;
  }

  void invalidateListCache() {
    _cache = null;
    _cacheAt = null;
  }

  // ── Session export/import (TV relay) ────────────────────────────────────────

  @override
  Map<String, dynamic>? exportSession() {
    if (!isConnected) return null;
    return {
      'accessToken': _box.get('accessToken'),
      'refreshToken': _box.get('refreshToken'),
      'expiresAt': _box.get('expiresAt'),
      'viewerName': _box.get('viewerName'),
      'viewerAvatar': _box.get('viewerAvatar'),
    };
  }

  @override
  Future<void> importSession(Map<String, dynamic> s) async {
    for (final k in const [
      'accessToken',
      'refreshToken',
      'expiresAt',
      'viewerName',
      'viewerAvatar',
    ]) {
      if (s.containsKey(k)) await _box.put(k, s[k]);
    }
    notifyListeners();
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('$v');
  }

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.tryParse('$v');

  static String? _poster(Map media) {
    final images = media['images'];
    if (images is! Map) return null;
    final poster = images['poster'];
    String? raw;
    if (poster is String) raw = poster;
    if (poster is List && poster.isNotEmpty && poster.first is String) {
      raw = poster.first as String;
    }
    if (poster is Map && poster['full'] is String) {
      raw = poster['full'] as String;
    }
    if (raw == null || raw.isEmpty) return null;
    return raw.startsWith('http') ? raw : 'https://$raw';
  }
}
