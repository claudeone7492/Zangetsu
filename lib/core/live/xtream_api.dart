import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'flat_json_scanner.dart';

/// One Xtream account. Credentials are per-account because a household often
/// holds more than one subscription (or a trial plus a paid line).
class XtreamAccount {
  const XtreamAccount({
    required this.id,
    required this.host,
    required this.username,
    required this.password,
    this.label = '',
  });

  /// Stable local id, derived from host+username so re-adding the same line
  /// updates it instead of duplicating it.
  final String id;

  /// Base URL, e.g. `http://example.tv:8080`. Normalised to no trailing slash.
  final String host;
  final String username;
  final String password;

  /// What the user calls this line ("Living room", "Trial").
  final String label;

  String get displayName =>
      label.trim().isNotEmpty ? label.trim() : '$username @ $host';

  Map<String, dynamic> toJson() => {
    'id': id,
    'host': host,
    'username': username,
    'password': password,
    if (label.isNotEmpty) 'label': label,
  };

  factory XtreamAccount.fromJson(Map<String, dynamic> j) => XtreamAccount(
    id: (j['id'] as String).trim(),
    host: (j['host'] as String).trim(),
    username: (j['username'] as String).trim(),
    password: (j['password'] as String?) ?? '',
    label: (j['label'] as String?) ?? '',
  );

  /// Normalises a host the user typed. Accepts `host:port`, `http://host:port`
  /// and a trailing slash, and defaults to http when no scheme is given —
  /// panels are frequently plain http on a LAN.
  static String normalizeHost(String raw) {
    var h = raw.trim();
    if (h.isEmpty) return '';
    if (!h.startsWith('http://') && !h.startsWith('https://')) {
      h = 'http://$h';
    }
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  static String idFor(String host, String username) =>
      '${normalizeHost(host)}|${username.trim()}';
}

/// A live channel, VOD title or series from an Xtream account.
class XtreamStream {
  const XtreamStream({
    required this.id,
    required this.name,
    required this.kind,
    this.icon = '',
    this.categoryId = '',
    this.epgChannelId = '',
    this.container = '',
    this.year = '',
    this.rating = '',
    this.plot = '',
  });

  final String id;
  final String name;
  final XtreamKind kind;
  final String icon;
  final String categoryId;

  /// `epg_channel_id` from the panel — the key into the account's own XMLTV.
  final String epgChannelId;
  final String container;
  final String year;
  final String rating;
  final String plot;
}

enum XtreamKind {
  live('live'),
  vod('vod'),
  series('series');

  const XtreamKind(this.wire);
  final String wire;
}

/// A category (group) the panel publishes.
class XtreamCategory {
  const XtreamCategory({required this.id, required this.name});

  final String id;
  final String name;
}

/// What a login tells us about the subscription.
class XtreamProfile {
  const XtreamProfile({
    required this.status,
    this.expiresAt,
    this.maxConnections,
    this.activeConnections,
    this.isTrial = false,
  });

  /// `Active`, `Expired`, `Banned`, … straight from the panel.
  final String status;
  final DateTime? expiresAt;
  final int? maxConnections;
  final int? activeConnections;
  final bool isTrial;

  bool get isActive => status.toLowerCase() == 'active';
  bool get isExpired =>
      status.toLowerCase() == 'expired' ||
      (expiresAt != null && expiresAt!.isBefore(DateTime.now()));

  /// Days left, or null when the panel published no expiry.
  int? get daysLeft {
    final e = expiresAt;
    if (e == null) return null;
    return e.difference(DateTime.now()).inDays;
  }
}

/// Raised when a panel rejects the credentials or the account is unusable.
class XtreamException implements Exception {
  XtreamException(this.message);
  final String message;
  @override
  String toString() => 'XtreamException: $message';
}

/// The Xtream Codes player API — the panel protocol most IPTV subscriptions
/// speak. One account gives live channels, VOD and series, plus its own XMLTV
/// guide, all over plain HTTP with the credentials as query parameters.
///
/// Every list endpoint is the same shape: `player_api.php?username=…&password=…`
/// plus an `action`. The parser is deliberately tolerant — panels disagree on
/// whether ids are numbers or strings, and a category with a missing name must
/// not sink the list — because a third-party panel is not ours to fix.
class XtreamApi {
  XtreamApi({required Dio dio, this.timeout = const Duration(seconds: 20)})
    : _dio = dio;

  final Dio _dio;
  final Duration timeout;

  /// Log in and read the subscription profile.
  ///
  /// Throws [XtreamException] when the panel rejects the credentials
  /// (`auth: 0`) or is unreachable, so the Add-account flow can show the real
  /// reason rather than an empty channel list.
  Future<XtreamProfile> login(XtreamAccount account) async {
    final body = await _get(account, null);
    final userInfo = body['user_info'];
    if (userInfo is! Map) {
      throw XtreamException('Panel did not return account information');
    }
    // Panels disagree on where the auth flag lives: some put it at the top
    // level, others nest it inside `user_info`. A rejected login is reported
    // as `auth: 0` in either place, so both are checked.
    final auth = body['auth'] ?? userInfo['auth'];
    if (auth == 0 || auth == '0' || auth == false) {
      throw XtreamException('Invalid username or password');
    }

    DateTime? expires;
    final exp = userInfo['exp_date'];
    if (exp != null) {
      final seconds = int.tryParse('$exp');
      if (seconds != null && seconds > 0) {
        expires = DateTime.fromMillisecondsSinceEpoch(
          seconds * 1000,
          isUtc: true,
        );
      }
    }

    return XtreamProfile(
      status: '${userInfo['status'] ?? 'Unknown'}',
      expiresAt: expires,
      maxConnections: int.tryParse('${userInfo['max_connections'] ?? ''}'),
      activeConnections: int.tryParse('${userInfo['active_cons'] ?? ''}'),
      isTrial: '${userInfo['is_trial'] ?? '0'}' == '1',
    );
  }

  /// Categories for [kind]. Empty on failure rather than throwing — a panel
  /// that answers channels but not categories should still list channels.
  Future<List<XtreamCategory>> categories(
    XtreamAccount account,
    XtreamKind kind,
  ) async {
    final action = switch (kind) {
      XtreamKind.live => 'get_live_categories',
      XtreamKind.vod => 'get_vod_categories',
      XtreamKind.series => 'get_series_categories',
    };
    final body = await _get(account, action, tolerateErrors: true);
    final list = _asList(body);
    return [
      for (final raw in list)
        if (raw is Map)
          XtreamCategory(
            id: '${raw['category_id'] ?? ''}',
            name: '${raw['category_name'] ?? 'Unnamed'}',
          ),
    ];
  }

  /// Streams for [kind], optionally narrowed to one category.
  Future<List<XtreamStream>> streams(
    XtreamAccount account,
    XtreamKind kind, {
    String? categoryId,
  }) async {
    final action = switch (kind) {
      XtreamKind.live => 'get_live_streams',
      XtreamKind.vod => 'get_vod_streams',
      XtreamKind.series => 'get_series',
    };
    // Big panels answer 100,000+ titles; this reads them straight off the
    // socket instead of holding bytes, text and a parsed tree at once.
    final out = <XtreamStream>[];
    await _scan(
      account,
      action,
      params: categoryId == null || categoryId.isEmpty
          ? null
          : {'category_id': categoryId},
      onObject: (fields) => out.add(_streamFromFields(fields, kind)),
    );
    return out;
  }

  /// Streams [action]'s answer through [FlatJsonScanner], one item at a time.
  Future<void> _scan(
    XtreamAccount account,
    String action, {
    Map<String, String>? params,
    required void Function(Map<String, String> fields) onObject,
  }) async {
    final query = StringBuffer(
      '?username=${Uri.encodeQueryComponent(account.username)}'
      '&password=${Uri.encodeQueryComponent(account.password)}'
      '&action=${Uri.encodeQueryComponent(action)}',
    );
    for (final e in (params ?? const <String, String>{}).entries) {
      query.write('&${e.key}=${Uri.encodeQueryComponent(e.value)}');
    }
    final scanner = FlatJsonScanner(onObject);
    try {
      final res = await _dio.get<ResponseBody>(
        '${account.host}/player_api.php$query',
        options: Options(
          responseType: ResponseType.stream,
          validateStatus: (c) => c != null && c < 500,
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
      );
      final body = res.data;
      if (body == null) return;
      await for (final chunk in body.stream) {
        scanner.feed(chunk);
      }
      scanner.finish();
    } on DioException catch (e) {
      debugPrint('[xtream] $action failed: $e');
    } on StateError catch (e) {
      // Truncated answer: the items read so far are still good.
      debugPrint('[xtream] $action ended early: $e');
    } on FormatException catch (e) {
      debugPrint('[xtream] $action unreadable: $e');
    }
  }

  XtreamStream _streamFromFields(Map<String, String> raw, XtreamKind kind) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = raw[k];
        if (v != null && v.isNotEmpty) return v;
      }
      return '';
    }

    final name = pick(const ['name', 'title']);
    return XtreamStream(
      id: pick(const ['stream_id', 'series_id']),
      name: name.isEmpty ? 'Unnamed' : name,
      kind: kind,
      icon: pick(const ['stream_icon', 'cover']),
      categoryId: pick(const ['category_id']),
      epgChannelId: pick(const ['epg_channel_id']),
      container: pick(const ['container_extension']),
      year: pick(const ['year']),
      rating: pick(const ['rating', 'rating_5based']),
      plot: pick(const ['plot']),
    );
  }

  /// The playable URL for a live channel.
  ///
  /// Live channels are addressed by id (`/<user>/<pass>/<id>`); VOD and
  /// episodes carry a container extension. Panels accept both forms for live,
  /// so the extension-less form is used, which is what every player expects.
  String liveUrl(XtreamAccount account, XtreamStream stream) =>
      '${account.host}/live/${account.username}/${account.password}/'
      '${stream.id}.${stream.container.isEmpty ? 'm3u8' : stream.container}';

  String vodUrl(XtreamAccount account, XtreamStream stream) =>
      '${account.host}/movie/${account.username}/${account.password}/'
      '${stream.id}.${stream.container.isEmpty ? 'mp4' : stream.container}';

  /// The account's own XMLTV guide, for [EpgStore] to consume.
  String epgUrl(XtreamAccount account) =>
      '${account.host}/xmltv.php?username=${account.username}'
      '&password=${account.password}';

  /// A short-lived stream URL for one series episode.
  Future<String> episodeUrl(
    XtreamAccount account, {
    required String episodeId,
    String container = 'mp4',
  }) async => '${account.host}/series/${account.username}/'
      '${account.password}/$episodeId.${container.isEmpty ? 'mp4' : container}';

  Future<Map<String, dynamic>> _get(
    XtreamAccount account,
    String? action, {
    Map<String, String>? params,
    bool tolerateErrors = false,
  }) async {
    final query = StringBuffer(
      '?username=${Uri.encodeQueryComponent(account.username)}'
      '&password=${Uri.encodeQueryComponent(account.password)}',
    );
    if (action != null) {
      query.write('&action=${Uri.encodeQueryComponent(action)}');
    }
    for (final e in (params ?? const <String, String>{}).entries) {
      query.write('&${e.key}=${Uri.encodeQueryComponent(e.value)}');
    }

    try {
      final res = await _dio.get<dynamic>(
        '${account.host}/player_api.php$query',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (c) => c != null && c < 500,
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
      );
      final data = res.data;
      if (data is List) return {'__list__': data};
      if (data is Map) return Map<String, dynamic>.from(data);
      final text = '${data ?? ''}'.trim();
      if (text.isEmpty) return {};
      final decoded = jsonDecode(text);
      if (decoded is List) return {'__list__': decoded};
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } on DioException catch (e) {
      if (tolerateErrors) {
        debugPrint('[xtream] $action failed: $e');
        return {};
      }
      throw XtreamException(
        e.type == DioExceptionType.connectionError
            ? 'Cannot reach ${account.host}'
            : 'Panel error: ${e.message}',
      );
    } on FormatException {
      // A panel behind a captive portal answers HTML; treat as no data.
      if (tolerateErrors) return {};
      throw XtreamException('Panel returned an unexpected response');
    }
  }

  /// Endpoints answer either a bare array or an object wrapping one. Both are
  /// normalised here so callers only ever see a list.
  static List<dynamic> _asList(Map<String, dynamic> body) {
    final wrapped = body['__list__'];
    if (wrapped is List) return wrapped;
    for (final value in body.values) {
      if (value is List) return value;
    }
    return const [];
  }
}
