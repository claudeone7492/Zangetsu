import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/download/download_size_estimate.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/l10n/app_localizations_en.dart';

VideoSource src(String url, {String? quality}) =>
    VideoSource(url: url, quality: quality, container: SourceContainer.mp4);

void main() {
  group('dashTotalBitrate', () {
    const mpd = '''
<MPD>
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="a" bandwidth="800000" height="720"/>
      <Representation id="b" bandwidth="2000000" height="1080"/>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4">
      <Representation id="c" bandwidth="128000"/>
    </AdaptationSet>
  </Period>
</MPD>
''';

    test('adds the requested video bitrate to the best audio', () {
      expect(dashTotalBitrate(mpd, '720p'), 800000 + 128000);
      expect(dashTotalBitrate(mpd, 'best'), 2000000 + 128000);
    });

    test('is null when no bandwidth is stated', () {
      expect(dashTotalBitrate('<MPD><Period/></MPD>', 'best'), isNull);
    });
  });

  group('parseHlsVariants', () {
    test('reads bandwidth and height, fastest first', () {
      const manifest = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
low.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
high.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1280x720
mid.m3u8
''';
      final variants = parseHlsVariants(manifest);

      expect(variants.map((v) => v.bandwidth), [5000000, 2000000, 800000]);
      expect(variants.map((v) => v.height), [1080, 720, 360]);
    });

    test('media playlists yield nothing', () {
      const manifest = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXTINF:6.0,
seg0.ts
''';
      expect(parseHlsVariants(manifest), isEmpty);
    });

    test('average bandwidth does not shadow the variant bandwidth', () {
      expect(
        parseHlsVariants(
          '#EXTM3U\n#EXT-X-STREAM-INF:AVERAGE-BANDWIDTH=1000000,BANDWIDTH=2000000\na.m3u8',
        ).single.bandwidth,
        2000000,
      );
    });

    test('variants without bandwidth are skipped, height optional', () {
      const manifest = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1000000
audio.m3u8
#EXT-X-STREAM-INF:RESOLUTION=640x360
novariant.m3u8
''';
      final variants = parseHlsVariants(manifest);

      expect(variants, hasLength(1));
      expect(variants.single.height, isNull);
    });
  });

  group('hlsVariantBytes', () {
    const variants = [
      (bandwidth: 5000000, height: 1080),
      (bandwidth: 2000000, height: 720),
    ];

    test('matches the wanted height', () {
      expect(
        hlsVariantBytes(variants, wantedHeight: 720, runtimeSec: 1200),
        2000000 ~/ 8 * 1200,
      );
    });

    test('falls back to the fastest without a match', () {
      expect(
        hlsVariantBytes(variants, wantedHeight: 480, runtimeSec: 1200),
        5000000 ~/ 8 * 1200,
      );
    });

    test('needs variants and a runtime', () {
      expect(hlsVariantBytes(const [], runtimeSec: 1200), isNull);
      expect(hlsVariantBytes(variants, runtimeSec: 0), isNull);
    });
  });

  test('qualityHeight parses labels, null otherwise', () {
    expect(qualityHeight('1080p'), 1080);
    expect(qualityHeight('720p60'), 720);
    expect(qualityHeight('best'), isNull);
    expect(qualityHeight(null), isNull);
  });

  test('formatApproxBytes always wears its tilde', () {
    expect(formatApproxBytes(2 * (1 << 30)), '~2.0 GB');
    expect(formatApproxBytes(90 * (1 << 20)), '~90 MB');
    expect(formatApproxBytes(512), '~512 B');
    expect(
      AppLocalizationsEn().downloadSizeEstimate('~90 MB', '~180 MB'),
      '~90 MB / episode · ~180 MB total',
    );
  });

  test('parseHlsMediaDurationSec sums segments, rejects non-playlists', () {
    const media = '#EXTM3U\n#EXTINF:6.0,\na.ts\n#EXTINF:4.5,\nb.ts\n';
    expect(parseHlsMediaDurationSec(media), 11);
    expect(parseHlsMediaDurationSec('not a playlist'), isNull);
    expect(
      parseHlsMediaDurationSec('#EXTM3U\n#EXT-X-TARGETDURATION:6\n'),
      isNull,
    );
  });

  test('assumedBitrateForHeight is coarse and null-safe', () {
    expect(assumedBitrateForHeight(1080), 8000000);
    expect(assumedBitrateForHeight(480), 2000000);
    expect(assumedBitrateForHeight(null), isNull);
  });

  group('estimateEpisodeBytes against a local server', () {
    late HttpServer server;
    late Uri base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
      server.listen((req) async {
        if (req.uri.path == '/video.mp4') {
          req.response.headers.contentLength = 42 * (1 << 20);
          await req.response.close();
        } else if (req.uri.path == '/nolength.mp4') {
          req.response.headers.chunkedTransferEncoding = true;
          await req.response.close();
        } else if (req.uri.path == '/master.m3u8') {
          req.response.headers.contentType = ContentType.text;
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n'
            'hi.m3u8\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/x.mpd') {
          req.response.headers.contentType = ContentType.text;
          req.response.write(
            '<MPD><Period>'
            '<AdaptationSet mimeType="video/mp4">'
            '<Representation id="v" bandwidth="4000000" height="1080"/>'
            '</AdaptationSet>'
            '<AdaptationSet mimeType="audio/mp4">'
            '<Representation id="a" bandwidth="128000"/>'
            '</AdaptationSet>'
            '</Period></MPD>',
          );
          await req.response.close();
        } else if (req.uri.path == '/error.mp4') {
          req.response.statusCode = HttpStatus.forbidden;
          req.response.headers.contentLength = 128;
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });
    });

    tearDown(() => server.close(force: true));

    test('direct file reads content-length, solid', () async {
      final est = await estimateEpisodeBytes(
        src('${base.replace(path: '/video.mp4')}'),
      );

      expect(est?.bytes, 42 * (1 << 20));
      expect(est?.solid, isTrue);
    });

    test('missing length is unknown, not zero', () async {
      expect(
        await estimateEpisodeBytes(
          src('${base.replace(path: '/nolength.mp4')}'),
        ),
        isNull,
      );
    });

    test('an error response length is not a video size', () async {
      expect(
        await estimateEpisodeBytes(src('${base.replace(path: '/error.mp4')}')),
        isNull,
      );
    });

    test('hls master math is solid; without runtime it is unknown', () async {
      final url = '${base.replace(path: '/master.m3u8')}';
      final est = await estimateEpisodeBytes(
        src(url, quality: '1080p'),
        runtimeMinutes: 20,
      );

      expect(est?.bytes, 4000000 ~/ 8 * 20 * 60);
      expect(est?.solid, isTrue);
      expect(await estimateEpisodeBytes(src(url, quality: '1080p')), isNull);
    });

    test('media playlist falls back to assumed bitrate, not solid', () async {
      // Separate server serving a media playlist (no variants stated).
      final media = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      try {
        media.listen((req) async {
          req.response.headers.contentType = ContentType.text;
          req.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
            '#EXTINF:6.0,\na.ts\n#EXTINF:6.0,\nb.ts\n',
          );
          await req.response.close();
        });
        final url = 'http://127.0.0.1:${media.port}/media.m3u8';
        final est = await estimateEpisodeBytes(src(url, quality: '1080p'));

        // 12s at assumed 8 Mbps → 12 MB, flagged low-confidence.
        expect(est?.bytes, 8000000 ~/ 8 * 12);
        expect(est?.solid, isFalse);
      } finally {
        await media.close(force: true);
      }
    });

    test('garbage in, null out', () async {
      expect(await estimateEpisodeBytes(src('')), isNull);
      expect(await estimateEpisodeBytes(src('not a url')), isNull);
      expect(
        await estimateEpisodeBytes(src('${base.replace(path: '/missing')}')),
        isNull,
      );
    });

    test('dash estimates from the manifest bitrates, not solid', () async {
      final est = await estimateEpisodeBytes(
        src('${base.replace(path: '/x.mpd')}'),
        runtimeMinutes: 24,
      );
      // (4_000_000 + 128_000) bits/s ÷ 8 × 1440s.
      expect(est?.bytes, (4000000 + 128000) ~/ 8 * 1440);
      expect(est?.solid, isFalse);
    });
  });
}
