import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'subtitle_text_codec.dart';
import 'subtitle_text_normalizer.dart';

/// One subtitle a catalogue offers for a title.
///
/// [label] is the release the caption was timed against, which is the single
/// most useful thing to show because a caption for a different cut will drift.
/// [title] is the name of the work itself, so a merged list can say which film a
/// row belongs to; [language] is the language spelled out, which is what a viewer
/// actually reads, and [lang] is the code.
class FrameXSubtitle {
  const FrameXSubtitle({
    required this.url,
    this.label,
    this.title,
    this.lang,
    this.language,
    this.format,
    this.source,
    this.isDefault = false,
  });

  final String url;
  final String? label;
  final String? title;
  final String? lang;
  final String? language;
  final String? format;
  final String? source;
  final bool isDefault;

  /// The most readable label: the release, else the language, else a generic.
  String get displayName {
    final l = label?.trim();
    if (l != null && l.isNotEmpty) return l;
    final g = language?.trim();
    if (g != null && g.isNotEmpty) return g;
    return 'Subtitle';
  }
}

/// One title from the provider's own catalogue search, which is how a film is
/// found by name.
class FrameXTitle {
  const FrameXTitle({required this.id, this.title, this.type, this.year});

  final String id;
  final String? title;
  final String? type;
  final String? year;
}

/// Fetches subtitles from FrameX TV (framextv.cc).
///
/// The provider is a public, keyless aggregator: it resolves a title to a set of
/// subtitle files and serves each one through its own proxy, so the app never has
/// to know which upstream a given file came from. That is the whole reason for
/// using it rather than talking to OpenSubtitles directly, which needs an API key
/// and a per-user quota.
///
/// Two calls matter. A title is identified by its TMDB id — the same id the app
/// already holds for the film being played — and `/api/stream` returns the
/// sources *and* the subtitle list for it. When the viewer wants a different
/// title, `/api/search` resolves a name to an id first.
///
/// The provider runs on four interchangeable hosts and the frontend picks one by
/// reachability, so the same is done here: the first host that answers is used for
/// the session, and a host that fails is not retried for every file.
class FrameXSubtitleSource {
  FrameXSubtitleSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
            ),
          );

  final Dio _dio;

  /// The provider's interchangeable API hosts, in the order its own frontend
  /// tries them.
  static const List<String> hosts = [
    'https://api.framextv.tech',
    'https://api.framextv.cc',
    'https://api.framextv.xyz',
    'https://api.framextv.pro',
  ];

  /// The identity the app sends; FrameX's relay refuses a request with no
  /// User-Agent.
  static const String _userAgent = 'zangetsu/1.0';

  /// The host in use, replaced by whichever answered.
  String _baseUrl = hosts.first;

  /// The hosts to try, the remembered one first and the rest behind it.
  List<String> get _bases => [_baseUrl, ...hosts.where((h) => h != _baseUrl)];

  /// The subtitles the provider holds for a title.
  ///
  /// [id] is a TMDB id (the app's own mediaId); [type] is `movie` or `tv`. A
  /// series needs its season and episode, because the provider keys an episode's
  /// subtitles on all three.
  Future<List<FrameXSubtitle>> subtitlesFor(
    String id, {
    String type = 'movie',
    int? season,
    int? episode,
  }) async {
    if (id.trim().isEmpty) return const [];
    final query = StringBuffer('id=${Uri.encodeQueryComponent(id.trim())}')
      ..write('&type=${Uri.encodeQueryComponent(type)}');
    if (type == 'tv' && season != null && episode != null) {
      query
        ..write('&season=$season')
        ..write('&episode=$episode');
    }
    try {
      final body = await _fetch('/api/stream?$query');
      final subs = _parseSubtitles(body);
      if (subs.isNotEmpty) return subs;
    } catch (_) {
      // Fall through to the dedicated endpoint below.
    }
    return _subtitlesFromEndpoint(id, type: type, season: season, episode: episode);
  }

  /// The provider's standalone subtitle endpoint, used when a stream response
  /// carries none.
  ///
  /// `/api/stream` only returns the subtitles of the provider that answered, so
  /// a title whose stream resolved without tracks still has a full set at
  /// `/api/subtitles`. It keys on the same TMDB id and also accepts an IMDb id.
  Future<List<FrameXSubtitle>> _subtitlesFromEndpoint(
    String id, {
    required String type,
    int? season,
    int? episode,
  }) async {
    final query = StringBuffer('id=${Uri.encodeQueryComponent(id.trim())}')
      ..write('&type=${Uri.encodeQueryComponent(type)}');
    if (type == 'tv' && season != null && episode != null) {
      query
        ..write('&season=$season')
        ..write('&episode=$episode');
    }
    try {
      final body = await _fetch('/api/subtitles?$query');
      return _parseSubtitles(body);
    } catch (_) {
      return const [];
    }
  }

  /// Resolves a title name to the provider's own catalogue entry, newest match
  /// first.
  Future<List<FrameXTitle>> searchTitles(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final body = await _fetch(
        '/api/search?q=${Uri.encodeQueryComponent(trimmed)}',
      );
      return _parseTitles(body);
    } catch (_) {
      return const [];
    }
  }

  /// Downloads one subtitle file as normalised WebVTT text, or null on failure.
  ///
  /// The provider's own proxy is used rather than the upstream URL, because the
  /// upstream link is not always CORS- or agent-friendly and the proxy normalises
  /// the encoding to UTF-8 on the way out. A link that already points at a relay
  /// is fetched directly instead.
  Future<String?> downloadText(String url) async {
    if (url.trim().isEmpty) return null;
    final bytes = await _fetchBytes(url);
    if (bytes == null || bytes.isEmpty) return null;
    final decoded = SubtitleTextCodec.decode(bytes);
    return SubtitleTextNormalizer.normalize(decoded);
  }

  /// Downloads [url] and writes the normalised caption to a temp `.vtt` file,
  /// returning its path, or null on failure.
  Future<String?> downloadToFile(String url, {String? name}) async {
    final text = await downloadText(url);
    if (text == null || text.trim().isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final stem = (name ?? 'framex').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final out = File('${dir.path}/framex_${stem}_${url.hashCode}.vtt');
    await out.writeAsString(text, flush: true);
    return out.path;
  }

  /// Fetches [path] from the first host that answers, and remembers it.
  ///
  /// Each host is tried in turn because the provider's four hosts are not equally
  /// reachable: a host blocked in one region answers on another. The one that
  /// worked is kept, so the failover cost is paid once rather than on every call.
  Future<String> _fetch(String path) async {
    Object? lastError;
    for (final base in _bases) {
      try {
        final res = await _dio.get<String>(
          '$base$path',
          options: Options(
            responseType: ResponseType.plain,
            headers: {'User-Agent': _userAgent},
          ),
        );
        final body = res.data ?? '';
        if (body.trim().isEmpty) {
          lastError = 'FrameX returned an empty body';
          continue;
        }
        _baseUrl = base;
        return body;
      } catch (e) {
        lastError = e;
      }
    }
    throw FrameXSubtitleException('FrameX is unreachable: $lastError');
  }

  /// The same failover as [_fetch], but keeps the body as bytes.
  ///
  /// A caption is text, but the proxy may hand back a non-UTF-8 encoding, so the
  /// bytes are taken whole and decoded by the caller.
  Future<List<int>?> _fetchBytes(String url) async {
    final requestUrl = _proxiedSubtitleUrl(url);
    Object? lastError;
    for (final base in _bases) {
      try {
        final res = await _dio.get<List<int>>(
          requestUrl != null ? '$base$requestUrl' : url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'User-Agent': _userAgent, 'Referer': '$base/'},
            validateStatus: (s) => s != null && s < 400,
          ),
        );
        final bytes = res.data;
        if (bytes == null || bytes.isEmpty) {
          lastError = 'FrameX returned an empty body';
          continue;
        }
        if (requestUrl != null) _baseUrl = base;
        return bytes;
      } catch (e) {
        lastError = e;
      }
    }
    if (requestUrl != null) {
      // The proxy failed everywhere — try the upstream link directly.
      return _fetchBytesDirect(url);
    }
    throw FrameXSubtitleException('Subtitle download failed: $lastError');
  }

  Future<List<int>?> _fetchBytesDirect(String url) async {
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'User-Agent': _userAgent},
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      return res.data;
    } catch (_) {
      return null;
    }
  }

  /// The path to fetch a caption from, appended to one of the hosts.
  ///
  /// A caption is always routed through the provider's subtitle relay when it
  /// can be, because that is the endpoint that normalises the encoding to UTF-8.
  /// Null is returned for a link that must be fetched directly.
  static String? _proxiedSubtitleUrl(String url) {
    if (url.trim().isEmpty) return null;
    if (url.startsWith('file:') || url.startsWith('content:')) return null;
    if (url.contains('/proxy') ||
        url.startsWith('blob:') ||
        url.startsWith('data:')) {
      return null;
    }
    return '/api/subtitles/proxy?url=${Uri.encodeQueryComponent(url)}';
  }

  List<FrameXSubtitle> _parseSubtitles(String body) {
    final json = _decodeJson(body);
    if (json == null) return const [];
    final list = json['subtitles'];
    if (list is! List) return const [];
    final out = <FrameXSubtitle>[];
    final seen = <String>{};
    for (final item in list) {
      if (item is! Map) continue;
      final url = (item['url'] as String?)?.trim() ?? '';
      if (!url.startsWith('http') || !seen.add(url)) continue;
      out.add(
        FrameXSubtitle(
          url: url,
          label: (item['label'] as String?)?.trim(),
          title: (item['title'] as String?)?.trim(),
          lang: (item['lang'] as String?)?.trim(),
          language: (item['language'] as String?)?.trim(),
          format: (item['format'] as String?)?.trim(),
          source: (item['source'] as String?)?.trim(),
          isDefault: item['isDefault'] == true,
        ),
      );
    }
    return out;
  }

  List<FrameXTitle> _parseTitles(String body) {
    final json = _decodeJson(body);
    if (json == null) return const [];
    final list = json['results'];
    if (list is! List) return const [];
    final out = <FrameXTitle>[];
    for (final item in list) {
      if (item is! Map) continue;
      final id = (item['id'] as String?)?.trim() ?? '';
      if (id.isEmpty) continue;
      out.add(
        FrameXTitle(
          id: id,
          title: (item['title'] as String?)?.trim(),
          type: (item['type'] as String?)?.trim(),
          year: (item['year'] as String?)?.trim(),
        ),
      );
    }
    return out;
  }

  Map<String, dynamic>? _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}

/// Thrown for a user-actionable FrameX failure so the UI can surface a readable
/// message.
class FrameXSubtitleException implements Exception {
  const FrameXSubtitleException(this.message);
  final String message;
  @override
  String toString() => message;
}
