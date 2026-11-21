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
/// full history. When it is absent — every desktop build, and Android/iOS
/// until the TDLib library is linked — the public web preview still lists the
/// channel's posts. A native failure falls through rather than hiding a public
/// channel the preview can read.
class TelegramService {
  TelegramService({TelegramBridge? bridge, TelegramWebClient? web})
    : _bridge = bridge ?? TelegramBridge(),
      _web = web ?? TelegramWebClient();

  final TelegramBridge _bridge;
  final TelegramWebClient _web;

  Future<TelegramChannelPage> browse(String raw, {int? limit}) async {
    final target = TelegramTarget.parse(raw);
    if (target == null) {
      throw const TelegramException('That is not a Telegram channel');
    }

    if (await _bridge.isAvailable()) {
      try {
        final streams = await _bridge.resolveChannel(
          target.channel,
          limit: limit,
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
