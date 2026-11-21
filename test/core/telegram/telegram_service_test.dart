import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/telegram/telegram_bridge.dart';
import 'package:watch_app/core/telegram/telegram_service.dart';
import 'package:watch_app/core/telegram/telegram_source.dart';
import 'package:watch_app/core/telegram/telegram_web.dart';

const _nativeStream = TelegramStream(
  title: 'Native',
  url: 'https://cdn/native.mp4',
);
const _webStream = TelegramStream(title: 'Web', url: 'https://cdn/web.mp4');

class _FakeBridge extends TelegramBridge {
  _FakeBridge({
    this.available = false,
    this.streams = const [],
    this.error,
    this.state = 'ready',
  });

  final bool available;
  final List<TelegramStream> streams;
  final Object? error;
  final String state;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<String> authState() async => state;

  @override
  Future<List<TelegramStream>> resolveChannel(
    String channel, {
    int? limit,
    int? messageId,
  }) async {
    if (error != null) throw error!;
    return streams;
  }
}

class _FakeWeb extends TelegramWebClient {
  _FakeWeb(this.streams);

  final List<TelegramStream> streams;
  int calls = 0;

  @override
  Future<List<TelegramStream>> browse(
    TelegramTarget target, {
    int? limit,
  }) async {
    calls++;
    return streams;
  }
}

void main() {
  test('uses the native path when it has streams', () async {
    final web = _FakeWeb(const [_webStream]);
    final service = TelegramService(
      bridge: _FakeBridge(available: true, streams: const [_nativeStream]),
      web: web,
    );

    final page = await service.browse('@films');

    expect(page.backend, TelegramBackend.native);
    expect(page.streams.single.title, 'Native');
    expect(web.calls, 0);
  });

  test('falls back to the web preview when native is unavailable', () async {
    final web = _FakeWeb(const [_webStream]);
    final service = TelegramService(bridge: _FakeBridge(), web: web);

    final page = await service.browse('https://t.me/films');

    expect(page.backend, TelegramBackend.web);
    expect(page.streams.single.title, 'Web');
    expect(page.target.channel, 'films');
  });

  test('falls back to the web preview when native fails', () async {
    final web = _FakeWeb(const [_webStream]);
    final service = TelegramService(
      bridge: _FakeBridge(
        available: true,
        error: const TelegramException('TDLib said no'),
      ),
      web: web,
    );

    final page = await service.browse('@films');

    expect(page.backend, TelegramBackend.web);
    expect(web.calls, 1);
  });

  test('falls back when native returns an empty page', () async {
    final web = _FakeWeb(const [_webStream]);
    final service = TelegramService(
      bridge: _FakeBridge(available: true),
      web: web,
    );

    final page = await service.browse('@films');

    expect(page.backend, TelegramBackend.web);
  });

  test('rejects something that is not a Telegram channel', () async {
    final service = TelegramService(bridge: _FakeBridge(), web: _FakeWeb([]));
    await expectLater(
      service.browse('https://example.com/films'),
      throwsA(isA<TelegramException>()),
    );
  });
}
