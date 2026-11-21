import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/playback/stream_probe.dart';

void main() {
  late HttpServer server;
  late String base;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case '/hls.m3u8':
          response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
          response.write('#EXTM3U\n#EXT-X-VERSION:3\n');
        case '/mp4':
          response.headers.contentType = ContentType('video', 'mp4');
          response.add(const [0, 0, 0, 0]);
        case '/page':
          response.headers.contentType = ContentType.html;
          response.write(
            '<html><script>var src="$base/hls.m3u8";</script></html>',
          );
        case '/dead':
          response.statusCode = HttpStatus.notFound;
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  setUp(StreamProbe.clearCache);

  tearDownAll(() async {
    await server.close(force: true);
  });

  test('needsResolve only asks about extension-less http URLs', () {
    expect(StreamProbe.needsResolve('$base/embed/123'), isTrue);
    expect(StreamProbe.needsResolve('$base/live.m3u8'), isFalse);
    expect(StreamProbe.needsResolve('magnet:?xt=urn:btih:abc'), isFalse);
    expect(StreamProbe.needsResolve('not a url'), isFalse);
  });

  test('classifies HLS by its body and content type', () async {
    final result = await StreamProbe.resolve('$base/hls.m3u8');
    expect(result, isNotNull);
    expect(result!.url, '$base/hls.m3u8');
    expect(result.container, SourceContainer.hls);
    expect(StreamProbe.cached('$base/hls.m3u8'), isNotNull);
  });

  test('classifies a plain video body', () async {
    final result = await StreamProbe.resolve('$base/mp4');
    expect(result?.container, SourceContainer.mp4);
  });

  test('follows an HTML wrapper to the media URL', () async {
    final result = await StreamProbe.resolve('$base/page');
    expect(result, isNotNull);
    expect(result!.url, '$base/hls.m3u8');
    expect(result.container, SourceContainer.hls);
  });

  test('marks a 404 bad and returns null', () async {
    expect(await StreamProbe.resolve('$base/dead'), isNull);
    expect(StreamProbe.knownBad('$base/dead'), isTrue);
    expect(await StreamProbe.resolve('$base/dead'), isNull);
  });

  test('refine rewrites wrappers and drops dead sources', () async {
    final sources = [
      VideoSource(url: '$base/page'),
      VideoSource(url: '$base/dead'),
      VideoSource(url: '$base/live.m3u8'),
    ];
    final refined = await StreamProbe.refine(sources);
    expect(refined, hasLength(2));
    expect(refined.first.url, '$base/hls.m3u8');
    expect(refined.first.container, SourceContainer.hls);
    expect(refined.last.url, '$base/live.m3u8');
  });

  test('refine keeps the original list when every probe fails', () async {
    final sources = [
      VideoSource(url: '$base/dead'),
    ];
    final refined = await StreamProbe.refine(sources);
    expect(refined, hasLength(1));
    expect(refined.single.url, '$base/dead');
  });
}
