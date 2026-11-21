import 'package:dio/dio.dart';

import 'music_models.dart';
import 'music_source.dart';

/// Lossless catalogue behind a user-supplied endpoint (Navidrome/Jellyfin/own).
/// Ships unconfigured because no public lossless catalogue is keyless.
class LosslessSource implements MusicSource {
  LosslessSource(this._dio, {String? baseUrl, String? apiKey})
    : _baseUrl = baseUrl ?? '',
      _apiKey = apiKey ?? '';

  final Dio _dio;
  String _baseUrl;
  String _apiKey;

  void configure({required String baseUrl, String? apiKey}) {
    _baseUrl = baseUrl.trim();
    _apiKey = apiKey?.trim() ?? '';
  }

  @override
  String get id => 'lossless';

  @override
  String get displayName => 'Lossless';

  @override
  bool get isConfigured => _baseUrl.isNotEmpty;

  Map<String, String> get _headers => {
    if (_apiKey.isNotEmpty) 'Authorization': 'Bearer $_apiKey',
  };

  @override
  Future<List<MusicSection>> home() async {
    if (!isConfigured) return const [];
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/api/home',
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
      '$_baseUrl/api/search',
      queryParameters: {'q': query, 'page': page},
      options: Options(headers: _headers),
    );
    return _tracks(response.data?['tracks']);
  }

  @override
  Future<String?> streamFor(MusicTrack track) async {
    if (!isConfigured) return null;
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl/api/stream/${Uri.encodeComponent(track.id)}',
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
