import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/telegram/telegram_source.dart';
import 'package:watch_app/core/telegram/telegram_web.dart';

Dio _dioAnswering(
  Response<String> Function(RequestOptions options) respond,
) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) => handler.resolve(respond(options)),
    ),
  );
  return dio;
}

const _page = '''
<html><body>
<div class="tgme_widget_message" data-post="films/101">
  <a class="tgme_widget_message_photo_wrap"
     style="background-image:url('https://cdn.example/thumb1.jpg')"></a>
  <div class="tgme_widget_message_text">Big Buck Bunny
Second line</div>
  <time datetime="2026-11-20T10:00:00+00:00"></time>
  <video src="https://cdn.example/video1.mp4"></video>
</div>
<div class="tgme_widget_message" data-post="films/102">
  <div class="tgme_widget_message_text">Live stream</div>
  <time datetime="2026-11-21T10:00:00+00:00"></time>
  <a href="https://cdn.example/live.m3u8">watch</a>
</div>
<div class="tgme_widget_message" data-post="films/103">
  <div class="tgme_widget_message_text">No media here</div>
</div>
</body></html>
''';

void main() {
  group('parseChannelPage', () {
    test('finds videos and media links, newest first', () {
      final streams = TelegramWebClient.parseChannelPage(
        _page,
        channel: 'films',
      );
      expect(streams, hasLength(2));
      expect(streams.first.url, 'https://cdn.example/live.m3u8');
      expect(streams.first.container, SourceContainer.hls);
      expect(streams.first.title, 'Live stream');
      expect(streams.last.url, 'https://cdn.example/video1.mp4');
      expect(streams.last.container, SourceContainer.mp4);
      expect(streams.last.title, 'Big Buck Bunny');
      expect(streams.last.thumbnailUrl, 'https://cdn.example/thumb1.jpg');
      expect(streams.last.pageUrl, 'https://t.me/films/101');
      expect(streams.last.publishedAt, isNotNull);
    });

    test('honours a limit', () {
      final streams = TelegramWebClient.parseChannelPage(
        _page,
        channel: 'films',
        limit: 1,
      );
      expect(streams, hasLength(1));
      expect(streams.single.url, 'https://cdn.example/live.m3u8');
    });

    test('reads a lazy-loaded data-src player', () {
      final streams = TelegramWebClient.parseChannelPage(
        '<div class="tgme_widget_message" data-post="films/9">'
        '<div class="tgme_widget_message_text">Lazy</div>'
        '<div class="player" data-src="https://cdn.example/lazy.mp4"></div>'
        '</div>',
        channel: 'films',
      );
      expect(streams.single.url, 'https://cdn.example/lazy.mp4');
    });

    test('falls back to page media when there are no message wrappers', () {
      final streams = TelegramWebClient.parseChannelPage(
        '<html><body><div class="tgme_widget_message_text">Solo</div>'
        '<video src="https://cdn.example/solo.mp4"></video></body></html>',
        channel: 'films',
      );
      expect(streams.single.url, 'https://cdn.example/solo.mp4');
      expect(streams.single.title, 'Solo');
      expect(streams.single.pageUrl, 'https://t.me/films');
    });

    test('returns empty for empty, media-free, or non-HTML bodies', () {
      expect(
        TelegramWebClient.parseChannelPage('', channel: 'films'),
        isEmpty,
      );
      expect(
        TelegramWebClient.parseChannelPage(
          '<div class="tgme_widget_message"><div>hi</div></div>',
          channel: 'films',
        ),
        isEmpty,
      );
      expect(
        TelegramWebClient.parseChannelPage('not html at all', channel: 'films'),
        isEmpty,
      );
    });

    test('ignores links that are not media', () {
      final streams = TelegramWebClient.parseChannelPage(
        '<div class="tgme_widget_message" data-post="films/1">'
        '<a href="https://example.com/page">read</a>'
        '<a href="https://t.me/films/2">next</a>'
        '</div>',
        channel: 'films',
      );
      expect(streams, isEmpty);
    });
  });

  group('browse', () {
    test('fetches the preview URL and parses the body', () async {
      RequestOptions? seen;
      final client = TelegramWebClient(
        dio: _dioAnswering((options) {
          seen = options;
          return Response<String>(
            requestOptions: options,
            statusCode: 200,
            data: _page,
          );
        }),
      );

      final streams = await client.browse(
        const TelegramTarget(channel: 'films'),
      );

      expect(seen!.uri.toString(), 'https://t.me/s/films');
      expect(streams, hasLength(2));
    });

    test('maps 404 onto a private-or-missing message', () async {
      final client = TelegramWebClient(
        dio: _dioAnswering(
          (options) => Response<String>(
            requestOptions: options,
            statusCode: 404,
            data: '',
          ),
        ),
      );
      await expectLater(
        client.browse(const TelegramTarget(channel: 'films')),
        throwsA(
          isA<TelegramException>().having(
            (e) => e.message,
            'message',
            contains('private'),
          ),
        ),
      );
    });

    test('maps other status codes onto a readable error', () async {
      final client = TelegramWebClient(
        dio: _dioAnswering(
          (options) => Response<String>(
            requestOptions: options,
            statusCode: 500,
            data: '',
          ),
        ),
      );
      await expectLater(
        client.browse(const TelegramTarget(channel: 'films')),
        throwsA(
          isA<TelegramException>().having(
            (e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
    });
  });
}
