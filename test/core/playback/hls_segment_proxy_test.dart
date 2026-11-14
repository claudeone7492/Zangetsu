import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/hls_segment_rewrite.dart';

// StreamFree's live-sports playlist points each segment at a P2P object whose
// `#sf=` fragment names the real, header-locked media URL. FFmpeg can't follow
// the fragment, so the body is rewritten to proxy URLs before it reaches mpv.
void main() {
  final base = Uri.parse(
    'https://strmfree.st/live-externalcdn/skyf11080p/index.m3u8?_t=abc&_e=1',
  );

  test('unwraps an absolute #sf= target', () {
    final body = [
      '#EXTM3U',
      '#EXTINF:1.920,',
      'https://p16.ttcdn-us.com/obj/x#sf=https%3A%2F%2Fcdn1.strmfree.st%2Flive%2Fskyf11080p%2F27551.js',
    ].join('\n');
    final out = proxyRewriteHlsBody(body, base, (u) => 'PROXY:$u');
    expect(out, contains('PROXY:https://cdn1.strmfree.st/live/skyf11080p/27551.js'));
    expect(out, isNot(contains('ttcdn-us.com')));
    expect(out, contains('#EXTM3U'));
  });

  test('resolves a path-only #sf= target against the stream host', () {
    final body = [
      '#EXTM3U',
      '#EXTINF:1.920,',
      'https://p16.ttcdn-us.com/obj/x#sf=%2Flive%2Fskyf11080p%2F27552.js',
    ].join('\n');
    final out = proxyRewriteHlsBody(body, base, (u) => 'PROXY:$u');
    expect(out, contains('PROXY:https://cdn1.strmfree.st/live/skyf11080p/27552.js'));
  });

  test('leaves a plain playlist untouched', () {
    final body = [
      '#EXTM3U',
      '#EXTINF:6.0,',
      'seg0.ts',
      '#EXTINF:6.0,',
      'seg1.ts',
    ].join('\n');
    expect(proxyRewriteHlsBody(body, base, (u) => 'PROXY:$u'), isNull);
  });

  test('keeps tag lines and drops nothing', () {
    final body = [
      '#EXTM3U',
      '#EXT-X-TARGETDURATION:8',
      '#EXTINF:1.920,',
      'https://p16.ttcdn-us.com/obj/x#sf=%2Flive%2Fk%2F1.js',
    ].join('\n');
    final out = proxyRewriteHlsBody(body, base, (u) => '/s/0')!;
    expect(out.split('\n'), [
      '#EXTM3U',
      '#EXT-X-TARGETDURATION:8',
      '#EXTINF:1.920,',
      '/s/0',
    ]);
  });

  test('leaves a nested playlist line alone', () {
    expect(proxySegmentTarget('variant.m3u8', base), isNull);
    expect(proxySegmentTarget('#EXTINF:1.0,', base), isNull);
    expect(proxySegmentTarget('', base), isNull);
  });
}
