import 'package:flutter/foundation.dart';

import 'telegram_bridge.dart';
import 'telegram_source.dart';
import 'telegram_web.dart';

/// Which path produced a channel's streams.
enum TelegramBackend { native, web }

/// A channel's current page of playable items.
@immutable
class TelegramChannelPage {
  const TelegramChannelPage({
    required this.target,
    required this.streams,
    required this.backend,
  });

  final TelegramTarget target;
  final List<TelegramStream> streams;
  final TelegramBackend backend;
}

/// Browses a public channel, native first and web second.
///
/// The native bridge (TDLib) is the path that can read private channels and
/// full history, and it needs a sign-in. When it is absent — every desktop
/// build — or signed out, the public web preview still lists the channel's
/// posts. A native failure falls through rather than hiding a public channel
/// the preview can read.
class TelegramService {
  TelegramService({TelegramBridge? bridge, TelegramWebClient? web})
    : _bridge = bridge ?? TelegramBridge(),
      _web = web ?? TelegramWebClient();

  final TelegramBridge _bridge;
  final TelegramWebClient _web;

  /// Whether this build has the TDLib client at all.
  Future<bool> nativeAvailable() => _bridge.isAvailable();

  /// The TDLib login state (`idle`, `waitPhone`, `waitCode`, `ready`, …).
  Future<String> authState() => _bridge.authState();

  Future<String?> unavailableReason() => _bridge.unavailableReason();

  Future<String> setCredentials(String apiId, String apiHash) =>
      _bridge.setCredentials(apiId, apiHash);

  Future<String> submitPhone(String phone) => _bridge.submitPhone(phone);

  Future<String> submitCode(String code) => _bridge.submitCode(code);

  Future<String> submitPassword(String password) =>
      _bridge.submitPassword(password);

  Future<String> submitRegistration(String first, String last) =>
      _bridge.submitRegistration(first, last);

  Future<void> signOut() => _bridge.signOut();

  Future<TelegramChannelPage> browse(String raw, {int? limit}) async {
    final target = TelegramTarget.parse(raw);
    if (target == null) {
      throw const TelegramException('That is not a Telegram channel');
    }

    // Only a signed-in client can answer; an idle one would fail every call
    // and fall through to the preview anyway, at the cost of a round trip.
    if (await _bridge.isAvailable() && await _bridge.authState() == 'ready') {
      try {
        final streams = await _bridge.resolveChannel(
          target.channel,
          limit: limit,
          messageId: target.messageId,
        );
        if (streams.isNotEmpty) {
          return TelegramChannelPage(
            target: target,
            streams: streams,
            backend: TelegramBackend.native,
          );
        }
      } on TelegramUnavailable {
        // The channel is not there after all; use the preview.
      } on TelegramException {
        // A native failure must not hide a channel the preview can read.
      }
    }

    final streams = await _web.browse(target, limit: limit);
    return TelegramChannelPage(
      target: target,
      streams: streams,
      backend: TelegramBackend.web,
    );
  }
}
