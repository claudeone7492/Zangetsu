import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/playback/relay_proxy.dart';

void main() {
  group('RelayProxy', () {
    test('wraps a remote stream and encodes the upstream url', () {
      final wrapped = RelayProxy.wrap('https://cdn.example/live.m3u8?a=1&b=2');
      expect(wrapped, startsWith(RelayProxy.base));
      expect(
        wrapped,
        contains(Uri.encodeComponent('https://cdn.example/live.m3u8?a=1&b=2')),
      );
    });

    test('leaves local and non-http urls alone', () {
      expect(RelayProxy.canWrap('http://127.0.0.1:1234/stream.m3u8'), isFalse);
      expect(RelayProxy.canWrap('http://localhost/stream.m3u8'), isFalse);
      expect(RelayProxy.canWrap('magnet:?xt=urn:btih:abc'), isFalse);
      expect(RelayProxy.canWrap('file:///tmp/a.m3u8'), isFalse);
      expect(RelayProxy.canWrap(''), isFalse);
    });

    test('does not double-wrap an already relayed url', () {
      final wrapped = RelayProxy.wrap('https://cdn.example/live.m3u8');
      expect(RelayProxy.canWrap(wrapped), isFalse);
      expect(RelayProxy.wrapIfPossible(wrapped), isNull);
    });
  });

  group('VideoSource relay fallback', () {
    test('withProxyUrl keeps the visible url and all metadata', () {
      const source = VideoSource(
        url: 'https://cdn.example/live.m3u8',
        quality: '1080p',
        label: 'Live',
        headers: {'Referer': 'https://example.com/'},
      );
      final fallback = source.withProxyUrl(RelayProxy.wrap(source.url));
      expect(fallback.url, source.url);
      expect(fallback.quality, source.quality);
      expect(fallback.label, source.label);
      expect(fallback.headers, source.headers);
      expect(fallback.proxyUrl, RelayProxy.wrap(source.url));
    });
  });
}
