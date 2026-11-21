import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'music_models.dart';
import 'music_source.dart';

/// Lossless catalogue behind a user-supplied endpoint (Navidrome/Jellyfin/own).
/// Ships unconfigured because no public lossless catalogue is keyless.
class LosslessSource implements MusicSource {
  LosslessSource(this._dio, {String? baseUrl, String? apiKey})
    : _baseUrl = (baseUrl ?? _staticBase),
      _apiKey = (apiKey ?? _staticKey);

  final Dio _dio;
  String _baseUrl;
  String _apiKey;

  static String _staticBase = '';
  static String _staticKey = '';

  static const String boxName = 'lossless_endpoint';
  static const String _baseKey = 'baseUrl';
  static const String _apiKeyKey = 'apiKey';

  /// The saved endpoint, or '' while unconfigured.
  static String get baseUrl => _staticBase;
  static String get apiKey => _staticKey;

  static void configureStatic({required String baseUrl, String? apiKey}) {
    _staticBase = baseUrl.trim();
    _staticKey = apiKey?.trim() ?? '';
  }

  /// Reads the endpoint saved in Parity tools. Runs once at boot so the
  /// source the injector built is usable without a second trip to settings.
  static Future<void> load() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<String>(boxName);
    final box = Hive.box<String>(boxName);
    configureStatic(
      baseUrl: box.get(_baseKey, defaultValue: '') ?? '',
      apiKey: box.get(_apiKeyKey, defaultValue: ''),
    );
  }

  /// Saves and applies in one step; an empty [baseUrl] clears the endpoint.
  static Future<void> save({required String baseUrl, String? apiKey}) async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<String>(boxName);
    final box = Hive.box<String>(boxName);
    final base = baseUrl.trim();
    if (base.isEmpty) {
      await box.delete(_baseKey);
      await box.delete(_apiKeyKey);
    } else {
      await box.put(_baseKey, base);
      await box.put(_apiKeyKey, apiKey?.trim() ?? '');
    }
    configureStatic(baseUrl: base, apiKey: apiKey);
  }

  void configure({required String baseUrl, String? apiKey}) {
    _baseUrl = baseUrl.trim();
    _apiKey = apiKey?.trim() ?? '';
  }

  @override
  String get id => 'lossless';

  @override
  String get displayName => 'Lossless';

  // Falls back to the static endpoint so the singleton the injector builds at
  // startup still works after the user configures one in Parity tools.
  String get _base => _baseUrl.isNotEmpty ? _baseUrl : _staticBase;
  String get _key => _apiKey.isNotEmpty ? _apiKey : _staticKey;

  @override
  bool get isConfigured => _base.isNotEmpty;

  Map<String, String> get _headers => {
    if (_key.isNotEmpty) 'Authorization': 'Bearer $_key',
  };

  @override
  Future<List<MusicSection>> home() async {
    if (!isConfigured) return const [];
    final response = await _dio.get<Map<String, dynamic>>(
      '$_base/api/home',
      options: Options(headers: _headers),
    );
    final rows = response.data?['rows'];
    if (rows is! List) return const [];
    return [
      for (final row in rows)
        if (row is Map)
          MusicSection(
            title: (row['title'] ?? 'Lossless').toString(),
            tracks: _tracks(row['tracks']),
          ),
    ];
  }

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    if (!isConfigured) return const [];
    final response = await _dio.get<Map<String, dynamic>>(
      '$_base/api/search',
      queryParameters: {'q': query, 'page': page},
      options: Options(headers: _headers),
    );
    return _tracks(response.data?['tracks']);
  }

  @override
  Future<String?> streamFor(MusicTrack track) async {
    if (!isConfigured) return null;
    final response = await _dio.get<Map<String, dynamic>>(
      '$_base/api/stream/${Uri.encodeComponent(track.id)}',
      options: Options(headers: _headers),
    );
    return response.data?['url'] as String?;
  }

  List<MusicTrack> _tracks(dynamic raw) {
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is Map)
          MusicTrack(
            id: (entry['id'] ?? '').toString(),
            title: (entry['title'] ?? '').toString(),
            sourceId: id,
            artist: entry['artist'] as String?,
            album: entry['album'] as String?,
            artwork: entry['artwork'] as String?,
            duration: entry['duration'] is num
                ? Duration(seconds: (entry['duration'] as num).toInt())
                : null,
          ),
    ];
  }
}
