import 'package:flutter/foundation.dart';

import '../models/video_source.dart';

/// Telegram sources are named by a `tg:` URL. A channel, a post, or a plain
/// `t.me` link all normalise to a [TelegramTarget], so the rest of the app has
/// one shape to deal with.
const String kTelegramScheme = 'tg:';

/// Channels a fresh install can browse without adding anything.
///
/// Deliberately empty. Public channel names are deployment-specific, and a
/// hard-coded list of channels that stopped posting (or never existed) would
/// hand a new user dead rows. The screen accepts any public channel by name or
/// `t.me` link, which is the part that works with no login.
const List<String> kDefaultTelegramChannels = <String>[];

/// A public channel, optionally narrowed to one post.
@immutable
class TelegramTarget {
  const TelegramTarget({required this.channel, this.messageId});

  /// Channel username without the `@`.
  final String channel;

  /// Post id, when the link points at one message.
  final int? messageId;

  String get key => '@$channel';

  String get webUrl => 'https://t.me/s/$channel';

  String get pageUrl => messageId == null
      ? 'https://t.me/$channel'
      : 'https://t.me/$channel/$messageId';

  /// Parses `tg:@channel`, `tg://channel`, `t.me/channel`, `t.me/s/channel`,
  /// `t.me/channel/123`, or a bare `@channel`.
  ///
  /// Returns null for anything that is not a public channel reference. A
  /// private invite link (`t.me/+hash` or `t.me/joinchat/...`) is rejected on
  /// purpose: the public preview cannot read it, and pretending otherwise
  /// would fail later with a less useful message.
  static TelegramTarget? parse(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return null;

    if (value.toLowerCase().startsWith(kTelegramScheme)) {
      value = value.substring(kTelegramScheme.length);
      if (value.startsWith('//')) value = value.substring(2);
      if (value.startsWith('@')) value = value.substring(1);
      // `tg:films` and `tg://films` name a channel directly; anything with a
      // slash or dot is a URL and falls through to the parser below.
      if (!value.contains('/') &&
          !value.contains('.') &&
          _validChannel(value)) {
        return TelegramTarget(channel: value);
      }
    }

    if (value.startsWith('@')) {
      final channel = value.substring(1);
      return _validChannel(channel) ? TelegramTarget(channel: channel) : null;
    }

    final uri = Uri.tryParse(
      value.contains('://') ? value : 'https://$value',
    );
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host != 't.me' && host != 'telegram.me' && host != 'www.t.me') {
      return null;
    }

    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    var index = 0;
    if (segments[0].toLowerCase() == 's') index = 1;
    if (index >= segments.length) return null;

    final channel = segments[index];
    if (!_validChannel(channel) || _reserved.contains(channel.toLowerCase())) {
      return null;
    }
    final messageId = index + 1 < segments.length
        ? int.tryParse(segments[index + 1])
        : null;
    return TelegramTarget(channel: channel, messageId: messageId);
  }

  /// `t.me` paths that are app actions, not channels. `joinchat` looks like a
  /// valid username but is the invite-link prefix.
  static const Set<String> _reserved = {
    'joinchat',
    'addstickers',
    'addemoji',
    'share',
    'proxy',
    'login',
    'setlanguage',
    'contact',
    'confirmphone',
  };

  static bool _validChannel(String value) =>
      RegExp(r'^[A-Za-z][A-Za-z0-9_]{3,31}$').hasMatch(value);
}

/// True when [url] names a Telegram channel or post.
bool isTelegramUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.toLowerCase().startsWith(kTelegramScheme)) return true;
  final lower = trimmed.toLowerCase();
  if (!lower.contains('t.me/') && !lower.contains('telegram.me/')) {
    return false;
  }
  return TelegramTarget.parse(trimmed) != null;
}

/// One playable item from a channel.
@immutable
class TelegramStream {
  const TelegramStream({
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.pageUrl,
    this.publishedAt,
    this.container = SourceContainer.unknown,
  });

  /// The post's first line, or empty when the post has no text. The UI supplies
  /// a localised fallback rather than this layer inventing English copy.
  final String title;
  final String url;
  final String? thumbnailUrl;
  final String? pageUrl;
  final DateTime? publishedAt;
  final SourceContainer container;

  factory TelegramStream.fromMap(Map<dynamic, dynamic> map) {
    final url = '${map['url'] ?? ''}'.trim();
    return TelegramStream(
      title: '${map['title'] ?? ''}'.trim(),
      url: url,
      thumbnailUrl: _optional(map['thumbnail'] ?? map['thumbnailUrl']),
      pageUrl: _optional(map['pageUrl']),
      publishedAt: DateTime.tryParse('${map['publishedAt'] ?? ''}'),
      container: containerForUrl(url),
    );
  }

  static String? _optional(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}

/// The stream container a URL implies.
SourceContainer containerForUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? url.toLowerCase();
  if (path.endsWith('.m3u8')) return SourceContainer.hls;
  if (path.endsWith('.mp4') || path.endsWith('.m4v')) {
    return SourceContainer.mp4;
  }
  return SourceContainer.unknown;
}

/// Whether [url] looks like a media file the player can open.
bool isTelegramMediaUrl(String url) {
  final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
  return path.endsWith('.mp4') ||
      path.endsWith('.m4v') ||
      path.endsWith('.webm') ||
      path.endsWith('.mkv') ||
      path.endsWith('.mov') ||
      path.endsWith('.m3u8');
}

/// A Telegram failure with a message fit to show the viewer.
class TelegramException implements Exception {
  const TelegramException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The native path is not present on this build or platform.
class TelegramUnavailable extends TelegramException {
  const TelegramUnavailable()
    : super('Telegram streaming is not available on this build');
}
