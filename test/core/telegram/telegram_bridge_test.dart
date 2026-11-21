import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/telegram/telegram_bridge.dart';
import 'package:watch_app/core/telegram/telegram_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zangetsu/telegram');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reports unavailable when the channel is not implemented', () async {
    final bridge = TelegramBridge();
    expect(await bridge.isAvailable(), isFalse);
    await expectLater(
      bridge.resolveChannel('films'),
      throwsA(isA<TelegramUnavailable>()),
    );
  });

  test('parses native streams and passes the limit', () async {
    MethodCall? seen;
    messenger.setMockMethodCallHandler(channel, (call) async {
      seen = call;
      if (call.method == 'available') return true;
      if (call.method == 'resolveChannel') {
        return [
          {
            'title': 'Film',
            'url': 'https://cdn/x.mp4',
            'thumbnail': 'https://cdn/x.jpg',
            'pageUrl': 'https://t.me/films/1',
            'publishedAt': '2026-11-20T10:00:00Z',
          },
        ];
      }
      return null;
    });

    final bridge = TelegramBridge();
    expect(await bridge.isAvailable(), isTrue);
    final streams = await bridge.resolveChannel('films', limit: 5);

    expect(seen!.method, 'resolveChannel');
    expect(seen!.arguments, {'channel': 'films', 'limit': 5});
    expect(streams.single.title, 'Film');
    expect(streams.single.url, 'https://cdn/x.mp4');
  });

  test('surfaces a native platform error as a readable exception', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'available') return true;
      throw PlatformException(code: 'auth', message: 'Private channel');
    });

    final bridge = TelegramBridge();
    await expectLater(
      bridge.resolveChannel('films'),
      throwsA(
        isA<TelegramException>().having(
          (e) => e.message,
          'message',
          'Private channel',
        ),
      ),
    );
  });
}
