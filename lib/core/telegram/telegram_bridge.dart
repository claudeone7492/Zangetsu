import 'package:flutter/services.dart';

import 'telegram_source.dart';

/// The native Telegram path.
///
/// A channel, not a plugin, for the same reason as `DubTtsBridge`: the app
/// owns the few calls it needs, and the native side can grow a TDLib client
/// without changing Dart. Every call degrades to [TelegramUnavailable] when the
/// channel is missing, so desktop and tests keep working and the web preview
/// can take over.
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

  Future<List<TelegramStream>> resolveChannel(
    String channel, {
    int? limit,
  }) async {
    if (_unavailable) throw const TelegramUnavailable();
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'resolveChannel',
        {'channel': channel, 'limit': ?limit},
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
