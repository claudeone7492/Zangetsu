import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'telegram_source.dart';

/// Reads a public channel through Telegram's web preview (`t.me/s/<channel>`).
///
/// This is the path that works with no login, no API key and no native library:
/// public channels are rendered as ordinary HTML, and a post that carries a
/// video exposes its file URL in the markup. Private channels need TDLib and
/// are the native bridge's job; this client is the fallback that keeps the
/// feature usable everywhere.
class TelegramWebClient {
  TelegramWebClient({Dio? dio, this.timeout = const Duration(seconds: 30)})
    : _dio = dio ?? Dio();

  final Dio _dio;
  final Duration timeout;

  Future<List<TelegramStream>> browse(
    TelegramTarget target, {
    int? limit,
  }) async {
    final Response<String> response;
    try {
      response = await _dio.get<String>(
        target.webUrl,
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          headers: const {
            // The preview serves a lighter page to a phone user agent and does
            // not gate public channels behind the app shell.
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
      );
    } on DioException catch (e) {
      throw TelegramException(
        e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.receiveTimeout ||
                e.type == DioExceptionType.sendTimeout
            ? 'Telegram timed out'
            : 'Couldn\'t reach Telegram',
      );
    }

    final status = response.statusCode ?? 0;
    if (status == 404) {
      throw const TelegramException(
        'That channel is private or does not exist',
      );
    }
    if (status < 200 || status >= 300) {
      throw TelegramException('Telegram returned HTTP $status');
    }
    return parseChannelPage(
      response.data ?? '',
      channel: target.channel,
      limit: limit,
    );
  }

  /// Pulls playable items out of a channel page.
  ///
  /// Telegram changes its markup, so the parser looks in several places rather
  /// than one: a `<video src>`, a link to a media file, and `data-src` on a
  /// lazy-loaded player. A post with several files yields several streams.
  static List<TelegramStream> parseChannelPage(
    String html, {
    required String channel,
    int? limit,
  }) {
    if (html.trim().isEmpty) return const [];

    final document = html_parser.parse(html);
    final streams = <TelegramStream>[];
    for (final message in document.querySelectorAll('.tgme_widget_message')) {
      streams.addAll(_streamsFromMessage(message, channel));
    }
    // A single-post page (t.me/channel/123) can render without the message
    // wrapper, so fall back to any media on the page.
    if (streams.isEmpty) {
      streams.addAll(_mediaOnPage(document, channel));
    }

    streams.sort((a, b) {
      final at = a.publishedAt?.millisecondsSinceEpoch ?? 0;
      final bt = b.publishedAt?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });
    if (limit != null && limit > 0 && streams.length > limit) {
      return streams.sublist(0, limit);
    }
    return streams;
  }

  static List<TelegramStream> _streamsFromMessage(
    dom.Element message,
    String channel,
  ) {
    final post = message.attributes['data-post'];
    final text = message.querySelector('.tgme_widget_message_text')?.text.trim();
    final publishedAt = DateTime.tryParse(
      message.querySelector('time')?.attributes['datetime'] ?? '',
    );
    final thumbnail = _thumbnail(message);
    final pageUrl = post != null && post.isNotEmpty
        ? 'https://t.me/$post'
        : 'https://t.me/$channel';

    final urls = <String>{};
    for (final video in message.querySelectorAll('video')) {
      final src = video.attributes['src']?.trim();
      if (src != null && src.isNotEmpty) urls.add(src);
    }
    for (final link in message.querySelectorAll('a')) {
      final href = link.attributes['href']?.trim();
      if (href != null && isTelegramMediaUrl(href)) urls.add(href);
    }
    for (final element in message.querySelectorAll('[data-src]')) {
      final src = element.attributes['data-src']?.trim();
      if (src != null && isTelegramMediaUrl(src)) urls.add(src);
    }

    final title = _title(text);
    return [
      for (final url in urls)
        TelegramStream(
          title: title,
          url: url,
          thumbnailUrl: thumbnail,
          pageUrl: pageUrl,
          publishedAt: publishedAt,
          container: containerForUrl(url),
        ),
    ];
  }

  static List<TelegramStream> _mediaOnPage(dom.Document document, String channel) {
    final urls = <String>{};
    for (final video in document.querySelectorAll('video')) {
      final src = video.attributes['src']?.trim();
      if (src != null && src.isNotEmpty) urls.add(src);
    }
    for (final link in document.querySelectorAll('a')) {
      final href = link.attributes['href']?.trim();
      if (href != null && isTelegramMediaUrl(href)) urls.add(href);
    }
    final title = _title(
      document.querySelector('.tgme_widget_message_text')?.text,
    );
    final root = document.body ?? document.documentElement;
    return [
      for (final url in urls)
        TelegramStream(
          title: title,
          url: url,
          thumbnailUrl: root == null ? null : _thumbnail(root),
          pageUrl: 'https://t.me/$channel',
          container: containerForUrl(url),
        ),
    ];
  }

  static String _title(String? text) {
    final first = (text ?? '').split('\n').first.trim();
    if (first.isEmpty) return '';
    return first.length > 120 ? '${first.substring(0, 117)}…' : first;
  }

  static String? _thumbnail(dom.Element element) {
    final photo = element.querySelector('.tgme_widget_message_photo_wrap');
    final style = photo?.attributes['style'] ?? '';
    final match = RegExp(
      r"background-image:\s*url\('([^']+)'\)",
    ).firstMatch(style);
    if (match != null) return match.group(1);
    return element.querySelector('img')?.attributes['src'];
  }
}
