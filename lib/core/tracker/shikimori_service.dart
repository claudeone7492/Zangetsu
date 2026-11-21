import 'package:dio/dio.dart';

/// Shikimori tracker (OAuth only).
class ShikimoriService {
  ShikimoriService(this._dio);

  static const String baseUrl = 'https://shikimori.one';
  static const String authorizeUrl = '$baseUrl/oauth/authorize';
  static const String tokenUrl = '$baseUrl/oauth/token';
  static const String clientId = String.fromEnvironment('SHIKIMORI_CLIENT_ID');
  static const String clientSecret = String.fromEnvironment('SHIKIMORI_CLIENT_SECRET');

  final Dio _dio;
  String? _token;

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get isConnected => _token != null;

  Uri authorizeUri({required String redirectUri}) => Uri.parse(authorizeUrl).replace(
    queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'user_rates',
    },
  );

  Future<void> exchangeCode({required String code, required String redirectUri}) async {
    if (!isConfigured) throw StateError('Shikimori is not configured');
    final response = await _dio.post<Map<String, dynamic>>(
      tokenUrl,
      data: {
        'grant_type': 'authorization_code',
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
      },
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final token = response.data?['access_token'] as String?;
    if (token == null) throw StateError('Shikimori refused the code');
    _token = token;
  }

  Future<void> updateRate({
    required int targetId,
    required String targetType,
    required int episodes,
  }) async {
    await _dio.post<void>(
      '$baseUrl/api/v2/user_rates',
      data: {
        'user_rate': {
          'target_id': targetId,
          'target_type': targetType,
          'episodes': episodes,
        },
      },
      options: Options(headers: {
        if (_token != null) 'Authorization': 'Bearer $_token',
      }),
    );
  }
}
