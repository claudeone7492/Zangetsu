import 'package:flutter/services.dart';

import 'telegram_source.dart';

/// The native Telegram path.
///
/// A channel, not a plugin, for the same reason as `DubTtsBridge`: the app
/// owns the few calls it needs. The native side is TDLib (`TelegramTd`), and it
/// answers a login state plus a channel's videos. Every call degrades to
/// [TelegramUnavailable] when the channel is missing, so desktop and tests keep
/// working and the web preview can take over.
class TelegramBridge {
  TelegramBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('zangetsu/telegram');

  final MethodChannel _channel;
  bool _unavailable = false;

  Future<bool> isAvailable() async {
    if (_unavailable) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      _unavailable = true;
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// The login state, as the native side names it: `idle`, `starting`,
  /// `waitPhone`, `waitCode`, `waitPassword`, `waitRegistration`, `ready`,
  /// `closed`, `unavailable`.
  Future<String> authState() async {
    if (_unavailable) return 'unavailable';
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('auth');
      return '${raw?['state'] ?? 'idle'}';
    } on MissingPluginException {
      _unavailable = true;
      return 'unavailable';
    } on PlatformException {
      return 'unavailable';
    }
  }

  /// Why the client could not start, when [authState] says `unavailable`.
  Future<String?> unavailableReason() async {
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('auth');
      return raw?['reason'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<String> setCredentials(String apiId, String apiHash) =>
      _login('setCredentials', {'apiId': apiId, 'apiHash': apiHash});

  Future<String> submitPhone(String phone) =>
      _login('submitPhone', {'phone': phone});

  Future<String> submitCode(String code) => _login('submitCode', {'code': code});

  Future<String> submitPassword(String password) =>
      _login('submitPassword', {'password': password});

  Future<String> submitRegistration(String first, String last) =>
      _login('submitRegistration', {'firstName': first, 'lastName': last});

  Future<void> signOut() async {
    try {
      await _channel.invokeMethod<void>('signOut');
    } on MissingPluginException {
      _unavailable = true;
    } on PlatformException {
      // Nothing to undo if the client was never up.
    }
  }

  Future<String> _login(String method, Map<String, Object?> args) async {
    if (_unavailable) throw const TelegramUnavailable();
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(method, args);
      return '${raw?['state'] ?? 'idle'}';
    } on MissingPluginException {
      _unavailable = true;
      throw const TelegramUnavailable();
    } on PlatformException catch (e) {
      throw TelegramException(e.message ?? 'Telegram refused that step');
    }
  }

  Future<List<TelegramStream>> resolveChannel(
    String channel, {
    int? limit,
    int? messageId,
  }) async {
    if (_unavailable) throw const TelegramUnavailable();
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'resolveChannel',
        {'channel': channel, 'limit': ?limit, 'messageId': ?messageId},
      );
      return [
        for (final entry in raw ?? const <dynamic>[])
          if (entry is Map) TelegramStream.fromMap(entry),
      ];
    } on MissingPluginException {
      _unavailable = true;
      throw const TelegramUnavailable();
    } on PlatformException catch (e) {
      throw TelegramException(e.message ?? 'Telegram is unavailable');
    }
  }
}
