import 'package:dio/dio.dart';

/// Kitsu tracker. Kitsu requires an app-specific client id; while it is empty
/// the service reports unconfigured and the UI hides it.
class KitsuService {
  KitsuService(this._dio);

  static const String baseUrl = 'https://kitsu.io/api/edge';
  static const String tokenUrl = 'https://kitsu.io/api/oauth/token';
  static const String clientId = String.fromEnvironment('KITSU_CLIENT_ID');
  static const String clientSecret = String.fromEnvironment('KITSU_CLIENT_SECRET');

  final Dio _dio;
  String? _token;

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get isConnected => _token != null;

  Map<String, String> get _headers => {
    'Accept': 'application/vnd.api+json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  Future<void> login({required String email, required String password}) async {
    if (!isConfigured) throw StateError('Kitsu is not configured');
    final response = await _dio.post<Map<String, dynamic>>(
      tokenUrl,
      data: {
        'grant_type': 'password',
        'username': email,
        'password': password,
        'client_id': clientId,
        'client_secret': clientSecret,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final token = response.data?['access_token'] as String?;
    if (token == null) throw StateError('Kitsu refused the login');
    _token = token;
  }

  Future<List<Map<String, dynamic>>> search(String query, {String kind = 'anime'}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$baseUrl/$kind',
      queryParameters: {'filter[text]': query, 'page[limit]': 20},
      options: Options(headers: _headers),
    );
    final data = response.data?['data'];
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<void> updateProgress({required String libraryId, required int progress}) async {
    await _dio.patch<void>(
      '$baseUrl/library-entries/$libraryId',
      data: {
        'data': {
          'id': libraryId,
          'type': 'libraryEntries',
          'attributes': {'progress': progress},
        },
      },
      options: Options(headers: {..._headers, 'Content-Type': 'application/vnd.api+json'}),
    );
  }
}
