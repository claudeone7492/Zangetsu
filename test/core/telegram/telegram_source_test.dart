import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/telegram/telegram_source.dart';

void main() {
  group('TelegramTarget.parse', () {
    test('accepts a bare @channel and a tg: channel', () {
      expect(TelegramTarget.parse('@films')!.channel, 'films');
      expect(TelegramTarget.parse('tg:@films')!.channel, 'films');
      expect(TelegramTarget.parse('tg://films')!.channel, 'films');
      expect(TelegramTarget.parse('TG:films')!.channel, 'films');
    });

    test('accepts t.me and telegram.me links, with or without a scheme', () {
      for (final raw in [
        'https://t.me/films',
        'http://t.me/films',
        't.me/films',
        'https://telegram.me/films',
        'https://www.t.me/films',
      ]) {
        expect(TelegramTarget.parse(raw)!.channel, 'films', reason: raw);
      }
    });

    test('accepts the public preview and a single post', () {
      final preview = TelegramTarget.parse('https://t.me/s/films')!;
      expect(preview.channel, 'films');
      expect(preview.messageId, isNull);

      final post = TelegramTarget.parse('https://t.me/films/123')!;
      expect(post.channel, 'films');
      expect(post.messageId, 123);
      expect(post.pageUrl, 'https://t.me/films/123');
    });

    test('normalises whitespace and trailing slashes', () {
      expect(TelegramTarget.parse('  @films  ')!.channel, 'films');
      expect(TelegramTarget.parse('https://t.me/films/')!.channel, 'films');
    });

    test('rejects private invites and non-Telegram hosts', () {
      expect(TelegramTarget.parse('https://t.me/+abc123'), isNull);
      expect(TelegramTarget.parse('https://t.me/joinchat/abc'), isNull);
      expect(TelegramTarget.parse('https://example.com/films'), isNull);
      expect(TelegramTarget.parse(''), isNull);
      expect(TelegramTarget.parse('films'), isNull);
    });

    test('rejects a channel name that Telegram could not issue', () {
      expect(TelegramTarget.parse('@ab'), isNull);
      expect(TelegramTarget.parse('@1films'), isNull);
      expect(TelegramTarget.parse('@films!'), isNull);
    });

    test('builds the preview URL', () {
      expect(
        const TelegramTarget(channel: 'films').webUrl,
        'https://t.me/s/films',
      );
    });
  });

  group('isTelegramUrl', () {
    test('recognises tg: and t.me sources', () {
      expect(isTelegramUrl('tg:@films'), isTrue);
      expect(isTelegramUrl('https://t.me/films'), isTrue);
      expect(isTelegramUrl('https://example.com/films'), isFalse);
      expect(isTelegramUrl('https://t.me/+invite'), isFalse);
    });
  });

  group('streams', () {
    test('infers the container from the URL', () {
      expect(
        containerForUrl('https://cdn/x.m3u8?token=1'),
        SourceContainer.hls,
      );
      expect(containerForUrl('https://cdn/x.mp4'), SourceContainer.mp4);
      expect(containerForUrl('https://cdn/x.bin'), SourceContainer.unknown);
    });

    test('recognises media extensions but not ordinary links', () {
      expect(isTelegramMediaUrl('https://cdn/x.MP4'), isTrue);
      expect(isTelegramMediaUrl('https://cdn/x.m3u8'), isTrue);
      expect(isTelegramMediaUrl('https://t.me/films/1'), isFalse);
      expect(isTelegramMediaUrl('https://example.com/page'), isFalse);
    });

    test('maps a native result and ignores empty optional fields', () {
      final stream = TelegramStream.fromMap({
        'title': 'Film',
        'url': 'https://cdn/x.mp4',
        'thumbnail': '',
        'publishedAt': '2026-11-20T10:00:00Z',
      });
      expect(stream.title, 'Film');
      expect(stream.container, SourceContainer.mp4);
      expect(stream.thumbnailUrl, isNull);
      expect(stream.publishedAt, DateTime.utc(2026, 11, 20, 10));
    });
  });
}
