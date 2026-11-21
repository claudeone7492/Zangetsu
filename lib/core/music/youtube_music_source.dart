import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'music_config.dart';
import 'music_models.dart';
import 'music_source.dart';
import 'potoken.dart';

/// YouTube Music as a catalogue, ported from Hikari's `music/MusicApi.kt`.
///
/// Two halves, exactly as upstream: browsing and searching go through the
/// WEB_REMIX InnerTube endpoint, and playback goes through the `player`
/// endpoint with a chain of clients. The chain matters because each client is
/// served differently — the native ones (VR, iOS, Android Music) hand out an
/// audio URL with no proof of anything, and the web one wants a BotGuard PO
/// token ([YouTubePoToken]). Trying native first means a device that cannot
/// mint a token still plays; the web client is the fallback that needs one.
///
/// Catalogue ids are video ids, so a track remembered from yesterday still
/// resolves: [streamFor] asks the player endpoint again rather than replaying
/// the signed URL from the listing.
class YouTubeMusicSource implements MusicSource {
  YouTubeMusicSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 25),
              headers: const {'Accept': 'application/json'},
            ),
          );

  static const String _origin = 'https://music.youtube.com';
  static const String _base = '$_origin/youtubei/v1/';
  static const String _key = 'AIzaSyC9XL3ZjWddXya6X74dJoCTL-WEYFDNX30';
  static const String _clientVersion = '1.20250101.00.00';

  static const String _playerUrl =
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false';

  final Dio _dio;

  /// Signed audio URLs, keyed by video id.
  final Map<String, _Resolved> _streams = {};

  /// Clients that already refused a video, so a retry does not start over.
  final Set<String> _badClients = {};

  @override
  String get id => kYouTubeMusicSourceId;

  @override
  String get displayName => 'YouTube Music';

  @override
  bool get isConfigured => true;

  @override
  Future<List<MusicSection>> home() async {
    final root = await _post('browse', {'browseId': 'FEmusic_home'});
    return [
      for (final shelf in _parseShelves(root))
        if (shelf.tracks.isNotEmpty)
          MusicSection(
            title: shelf.title.isEmpty ? displayName : shelf.title,
            tracks: shelf.tracks.take(kMusicRowLimit).toList(),
          ),
    ];
  }

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    // No `params` filter: the song-only filter token the reference app used is
    // rejected now and answers "No results", while the unfiltered search
    // returns songs, albums and artists and the parser keeps the songs.
    final root = await _post('search', {'query': trimmed});
    final seen = <String>{};
    return [
      for (final shelf in _parseShelves(root))
        for (final track in shelf.tracks)
          if (seen.add(track.id)) track,
    ].take(kMusicSearchLimit).toList();
  }

  @override
  Future<String?> streamFor(MusicTrack track) async {
    final cached = _streams[track.id];
    if (cached != null && cached.isFresh) return cached.url;
    _streams.remove(track.id);

    for (final client in _clients) {
      final key = '${track.id}/${client.name}';
      if (_badClients.contains(key)) continue;
      final resolved = await _resolve(track.id, client);
      if (resolved != null) {
        _streams[track.id] = resolved;
        return resolved.url;
      }
      _badClients.add(key);
    }
    // Nothing answered: a stale URL sometimes still plays, a bare null never.
    return track.streamUrl;
  }

  /// One `player` call for one client. Null means "this client had nothing".
  Future<_Resolved?> _resolve(String videoId, _Client client) async {
    final streaming = client.webPoToken ? await YouTubePoToken.streaming() : null;
    if (client.webPoToken && streaming == null) return null;

    // The lookup and the stream want different tokens: the lookup's is bound
    // to the video, the stream's to the visitor.
    final lookupPot = client.webPoToken
        ? await YouTubePoToken.mint(videoId: videoId)
        : null;

    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        _playerUrl,
        data: {
          'context': {
            'client': {
              'clientName': client.name,
              'clientVersion': client.version,
              'userAgent': client.userAgent,
              'hl': 'en',
              'gl': 'US',
              'timeZone': 'UTC',
              'utcOffsetMinutes': 0,
              'visitorData': ?streaming?.visitor,
              ...client.extra,
            },
          },
          'videoId': videoId,
          'contentCheckOk': true,
          'racyCheckOk': true,
          'playbackContext': {
            'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
          },
          'serviceIntegrityDimensions': ?(lookupPot == null
              ? null
              : {'poToken': lookupPot}),
        },
        options: Options(
          headers: {
            'User-Agent': client.userAgent,
            'X-YouTube-Client-Name': client.numeric,
            'X-YouTube-Client-Version': client.version,
            'Origin': client.webPoToken
                ? 'https://m.youtube.com'
                : 'https://www.youtube.com',
            if (client.webPoToken) 'Referer': 'https://m.youtube.com/',
            if (streaming != null) 'X-Goog-Visitor-Id': streaming.visitor,
          },
        ),
      );
    } on DioException catch (e) {
      debugPrint('[youtube-music] ${client.name} lookup failed: $e');
      return null;
    }

    final root = response.data;
    if (root is! Map) return null;
    final status = root['playabilityStatus'];
    final state = status is Map ? '${status['status']}' : '';
    if (state != 'OK') {
      debugPrint(
        '[youtube-music] ${client.name}: $state '
        '${status is Map ? status['reason'] ?? '' : ''}',
      );
      if (state == 'UNPLAYABLE' && client.webPoToken) YouTubePoToken.rotate();
      return null;
    }

    final formats = (root['streamingData'] as Map?)?['adaptiveFormats'];
    if (formats is! List) return null;

    // AAC first (mp4, plays everywhere), then Opus (webm), highest bitrate in
    // the preferred container — Hikari's order, for the same reason.
    _Format? aac;
    _Format? opus;
    for (final raw in formats) {
      if (raw is! Map) continue;
      final url = raw['url'];
      if (url is! String || url.isEmpty) continue;
      final mime = '${raw['mimeType'] ?? ''}';
      final format = _Format(
        url: url,
        bitrate: raw['bitrate'] is int ? raw['bitrate'] as int : 0,
        expiresAt: _expiryOf(raw),
      );
      if (mime.startsWith('audio/mp4')) {
        if (aac == null || format.bitrate > aac.bitrate) aac = format;
      } else if (mime.startsWith('audio/webm')) {
        if (opus == null || format.bitrate > opus.bitrate) opus = format;
      }
    }
    final best = aac ?? opus;
    return best == null ? null : _Resolved(best.url, best.expiresAt);
  }

  /// `expire` (epoch seconds) or `expiresInSeconds`, whichever the format
  /// carries; the signed URL goes stale with it.
  static DateTime? _expiryOf(Map raw) {
    final expire = raw['expire'];
    if (expire is int) {
      return DateTime.fromMillisecondsSinceEpoch(expire * 1000);
    }
    final seconds = int.tryParse('${raw['expiresInSeconds'] ?? ''}');
    return seconds == null
        ? null
        : DateTime.now().add(Duration(seconds: seconds));
  }

  Future<Map<String, dynamic>> _post(
    String endpoint,
    Map<String, Object?> body,
  ) async {
    final visitor = await YouTubePoToken.visitorData();
    final Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        '$_base$endpoint?prettyPrint=false&key=$_key',
        data: {
          ...body,
          'context': {
            'client': {
              'clientName': 'WEB_REMIX',
              'clientVersion': _clientVersion,
              'hl': 'en',
              'gl': 'US',
              'visitorData': ?visitor,
            },
          },
        },
        options: Options(
          headers: {
            'Origin': _origin,
            'Referer': '$_origin/',
            'X-Origin': _origin,
            'X-Goog-Api-Format-Version': '1',
          },
        ),
      );
    } on DioException catch (e) {
      throw MusicSourceException('Could not reach $displayName.', cause: e);
    }
    final data = response.data;
    if (data is! Map) {
      throw MusicSourceException('$displayName sent something unexpected.');
    }
    return Map<String, dynamic>.from(data);
  }

  // ------------------------------------------------------------------ parsing

  /// Shelves of tracks, in document order, from any InnerTube response.
  ///
  /// The renderer name is the only stable thing across home, search and browse,
  /// so every object carrying one is read and everything else recursed into —
  /// the same walk Hikari does.
  static List<_Shelf> _parseShelves(Map<String, dynamic> root) {
    final out = <_Shelf>[];
    void walk(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          final key = '${entry.key}';
          final value = entry.value;
          if (value is Map &&
              (key == 'musicShelfRenderer' ||
                  key == 'musicPlaylistShelfRenderer' ||
                  key == 'musicCarouselShelfRenderer' ||
                  key == 'gridRenderer')) {
            final shelf = _parseShelf(key, value);
            if (shelf != null) out.add(shelf);
          } else {
            walk(value);
          }
        }
      } else if (node is List) {
        for (final child in node) {
          walk(child);
        }
      }
    }

    walk(root);
    return out;
  }

  static _Shelf? _parseShelf(String kind, Map<dynamic, dynamic> node) {
    final title = switch (kind) {
      'musicCarouselShelfRenderer' => _runsText(
        (node['header'] as Map?)?['musicCarouselShelfBasicHeaderRenderer'],
        'title',
      ),
      'musicShelfRenderer' => _runsText(node, 'title'),
      'gridRenderer' => _runsText(
        (node['header'] as Map?)?['gridHeaderRenderer'],
        'title',
      ),
      _ => '',
    }.trim();

    final entries = kind == 'gridRenderer' ? node['items'] : node['contents'];
    final tracks = <MusicTrack>[];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        final listItem = entry['musicResponsiveListItemRenderer'];
        if (listItem is Map) {
          final track = _parseListItem(listItem);
          if (track != null) tracks.add(track);
        }
        final card = entry['musicTwoRowItemRenderer'];
        if (card is Map) {
          final track = _parseTwoRow(card);
          if (track != null) tracks.add(track);
        }
      }
    }
    if (tracks.isEmpty) return null;
    return _Shelf(title, tracks);
  }

  /// The `musicResponsiveListItemRenderer` shape: a title column, subtitle
  /// columns, a thumbnail and an optional fixed duration column.
  static MusicTrack? _parseListItem(Map<dynamic, dynamic> item) {
    final columns = item['flexColumns'];
    List<String> columnRuns(int index) {
      if (columns is! List || index >= columns.length) return const [];
      final column = columns[index];
      if (column is! Map) return const [];
      final renderer =
          column['musicResponsiveListItemFlexColumnRenderer'] as Map?;
      return _runs(renderer?['text']);
    }

    final title = columnRuns(0).join().trim();
    if (title.isEmpty) return null;
    final parts = _cleanParts([...columnRuns(1), ...columnRuns(2)]);
    final thumb = _thumbOf(item['thumbnail']);

    final fixed = item['fixedColumns'];
    var durationHint = 0;
    if (fixed is List && fixed.isNotEmpty && fixed.first is Map) {
      durationHint = _parseDuration(
        _runsText(
          (fixed.first as Map)['musicResponsiveListItemFixedColumnRenderer'],
          'text',
        ),
      );
    }

    final nav = item['navigationEndpoint'] as Map?;
    final watchId = (nav?['watchEndpoint'] as Map?)?['videoId'];
    final playlistId = (item['playlistItemData'] as Map?)?['videoId'];
    var videoId = playlistId is String && playlistId.isNotEmpty
        ? playlistId
        : (watchId is String ? watchId : '');
    if (videoId.isEmpty && nav?['browseEndpoint'] == null) {
      final found = _findValue(item, 'videoId');
      if (found is String) videoId = found;
    }

    if (videoId.isEmpty) {
      // Albums, artists and playlists carry no video id. Hikari keeps them to
      // open a browse page; this app has no such page, so they would be dead
      // rows in the list.
      return null;
    }
    return _song(videoId, title, parts, thumb, durationHint);
  }

  /// The `musicTwoRowItemRenderer` shape used by carousels and grids.
  static MusicTrack? _parseTwoRow(Map<dynamic, dynamic> item) {
    final title = _runsText(item, 'title').trim();
    if (title.isEmpty) return null;
    final parts = _cleanParts(_runs(item['subtitle']));
    final thumb = _thumbOf(item['thumbnailRenderer']);

    final nav = item['navigationEndpoint'] as Map?;
    final videoId = (nav?['watchEndpoint'] as Map?)?['videoId'];
    if (videoId is! String || videoId.isEmpty) return null;
    return _song(videoId, title, parts, thumb, 0);
  }

  /// YouTube's subtitle parts, in its order: an optional type word, then
  /// artist, then album or a view count. A duration anywhere in there is the
  /// track's length, not a subtitle.
  static MusicTrack _song(
    String videoId,
    String title,
    List<String> parts,
    String thumb,
    int durationHint,
  ) {
    var rest = parts;
    if (rest.isNotEmpty && _typeWords.contains(rest.first)) {
      rest = rest.skip(1).toList();
    }
    var duration = durationHint;
    final kept = <String>[];
    for (final part in rest) {
      if (_duration.hasMatch(part)) {
        duration = _parseDuration(part);
      } else {
        kept.add(part);
      }
    }
    final album = kept.length > 1 ? kept[1] : '';
    return MusicTrack(
      id: videoId,
      title: title,
      sourceId: kYouTubeMusicSourceId,
      artist: kept.isEmpty ? null : kept.first,
      album: album.isEmpty || album.endsWith('plays') || album.endsWith('views')
          ? null
          : album,
      artwork: _hq(thumb),
      duration: duration > 0 ? Duration(seconds: duration) : null,
    );
  }

  static const Set<String> _typeWords = {
    'Song',
    'Video',
    'Album',
    'Single',
    'EP',
    'Playlist',
    'Artist',
    'Podcast',
    'Episode',
    'Profile',
  };

  static final RegExp _duration = RegExp(r'^\d{1,2}(:\d{2}){1,2}$');

  /// The text runs of a `{runs: [...]}` object, or its `simpleText`.
  static List<String> _runs(Object? text) {
    if (text is! Map) return const [];
    final runs = text['runs'];
    if (runs is! List) {
      final simple = text['simpleText'];
      return simple is String ? [simple] : const [];
    }
    return [
      for (final run in runs)
        if (run is Map && run['text'] is String) run['text'] as String,
    ];
  }

  static String _runsText(Object? holder, String key) {
    if (holder is! Map) return '';
    return _runs(holder[key]).join();
  }

  static List<String> _cleanParts(List<String> parts) => [
    for (final part in parts.map((p) => p.trim()))
      if (part.isNotEmpty && part != '•' && part != '·') part,
  ];

  static int _parseDuration(String text) {
    if (!_duration.hasMatch(text)) return 0;
    var total = 0;
    for (final part in text.split(':')) {
      total = total * 60 + (int.tryParse(part) ?? 0);
    }
    return total;
  }

  static String _thumbOf(Object? node) {
    final thumbnails = _findValue(node, 'thumbnails');
    if (thumbnails is! List || thumbnails.isEmpty) return '';
    final last = thumbnails.last;
    return last is Map && last['url'] is String ? last['url'] as String : '';
  }

  /// Google's thumbnail URLs carry a size in the path; asking for a bigger one
  /// costs nothing and stops the artwork looking soft on a television.
  static String _hq(String url, {int size = 544}) {
    if (url.isEmpty) return url;
    if (!url.contains('googleusercontent.com') && !url.contains('ggpht.com')) {
      return url;
    }
    return url.replaceAll(RegExp(r'=w\d+-h\d+[^&?]*'), '=w$size-h$size-l90-rj');
  }

  static Object? _findValue(Object? node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (final value in node.values) {
        final found = _findValue(value, key);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final value in node) {
        final found = _findValue(value, key);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Playback clients in the order Hikari tries them: native first, because
  /// they need no token, then the web client, which does.
  static const List<_Client> _clients = [
    _Client(
      name: 'ANDROID_VR',
      numeric: '28',
      version: '1.65.10',
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.65.10 '
          '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      extra: {
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'androidSdkVersion': 32,
        'osName': 'Android',
        'osVersion': '12L',
      },
    ),
    _Client(
      name: 'IOS',
      numeric: '5',
      version: '20.10.4',
      userAgent:
          'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 '
          'like Mac OS X;)',
      extra: {
        'deviceMake': 'Apple',
        'deviceModel': 'iPhone16,2',
        'osName': 'iPhone',
        'osVersion': '18.3.2.22D82',
      },
    ),
    _Client(
      name: 'ANDROID_MUSIC',
      numeric: '21',
      version: '8.12.53',
      userAgent:
          'com.google.android.apps.youtube.music/8.12.53 '
          '(Linux; U; Android 14; Pixel 8 Build/UQ1A.240205.004) gzip',
      extra: {
        'deviceMake': 'Google',
        'deviceModel': 'Pixel 8',
        'androidSdkVersion': 34,
        'osName': 'Android',
        'osVersion': '14',
      },
    ),
    _Client(
      name: 'MWEB',
      numeric: '2',
      version: '2.20250925.01.00',
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36',
      webPoToken: true,
      extra: {'platform': 'MOBILE'},
    ),
  ];
}

class _Client {
  const _Client({
    required this.name,
    required this.numeric,
    required this.version,
    required this.userAgent,
    this.webPoToken = false,
    this.extra = const {},
  });

  final String name;
  final String numeric;
  final String version;
  final String userAgent;

  /// True for the web-family client, which refuses a request without a token.
  final bool webPoToken;

  final Map<String, Object?> extra;
}

class _Shelf {
  const _Shelf(this.title, this.tracks);
  final String title;
  final List<MusicTrack> tracks;
}

class _Format {
  const _Format({
    required this.url,
    required this.bitrate,
    required this.expiresAt,
  });
  final String url;
  final int bitrate;
  final DateTime? expiresAt;
}

class _Resolved {
  const _Resolved(this.url, this.expiresAt);
  final String url;
  final DateTime? expiresAt;

  /// A minute of margin, since a URL that dies mid-song is a stall mid-song.
  bool get isFresh =>
      expiresAt == null ||
      expiresAt!.subtract(const Duration(minutes: 1)).isAfter(DateTime.now());
}
