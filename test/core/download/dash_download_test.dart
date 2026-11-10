import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/download/dash_downloader.dart';
import 'package:watch_app/core/download/dash_manifest.dart';

/// Serves an MPD for any `.mpd` URL and a fixed byte body for every segment.
class _DashAdapter implements HttpClientAdapter {
  _DashAdapter(this.mpd, {this.failFor, this.failures = 0});

  final String mpd;
  final String? failFor;
  final int failures;

  final attempts = <String>[];
  int _failed = 0;

  static final _body = Uint8List.fromList(List<int>.filled(16, 0xAB));

  @override
  Future<ResponseBody> fetch(RequestOptions o, _, _) async {
    final url = o.uri.toString();
    attempts.add(url);
    if (url.endsWith('.mpd')) return ResponseBody.fromString(mpd, 200);
    if (failFor != null && url.contains(failFor!) && _failed < failures) {
      _failed++;
      return ResponseBody.fromString('', 500);
    }
    return ResponseBody.fromBytes(_body, 200);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(HttpClientAdapter a) {
  final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 2)));
  dio.httpClientAdapter = a;
  return dio;
}

/// A two-track (video + audio) MPD using SegmentTemplate/$Number$.
const _twoTrackMpd = '''
<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static"
     mediaPresentationDuration="PT8S">
  <BaseURL>https://cdn.test/</BaseURL>
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <SegmentTemplate initialization="v/init.mp4" media="v/\$Number\$.m4s"
                       timescale="1" duration="4" startNumber="1"/>
      <Representation id="v720" bandwidth="800000" width="1280" height="720"/>
      <Representation id="v1080" bandwidth="2000000" width="1920" height="1080"/>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4" contentType="audio">
      <SegmentTemplate initialization="a/init.mp4" media="a/\$Number\$.m4s"
                       timescale="1" duration="4" startNumber="1"/>
      <Representation id="a1" bandwidth="128000"/>
    </AdaptationSet>
  </Period>
</MPD>
''';

/// A SegmentTimeline MPD (time-based segment numbering).
const _timelineMpd = '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <SegmentTemplate initialization="init.mp4" media="seg-\$Time\$.m4s"
                       timescale="1000">
        <SegmentTimeline>
          <S t="0" d="4000" r="2"/>
        </SegmentTimeline>
      </SegmentTemplate>
      <Representation id="v" bandwidth="500000" height="480"/>
    </AdaptationSet>
  </Period>
</MPD>
''';

void main() {
  group('parseIsoDuration', () {
    test('parses hours/minutes/seconds', () {
      expect(parseIsoDuration('PT1H2M3.5S'), closeTo(3723.5, 0.001));
      expect(parseIsoDuration('PT24S'), 24);
      expect(parseIsoDuration('PT0S'), 0);
    });

    test('rejects junk', () {
      expect(parseIsoDuration('nope'), isNull);
      expect(parseIsoDuration(null), isNull);
    });
  });

  group('parseDashManifest', () {
    test('picks the video closest to the requested quality + best audio', () {
      final m = parseDashManifest(
        _twoTrackMpd,
        'https://cdn.test/x.mpd',
        quality: '720p',
      );
      expect(m, isNotNull);
      expect(m!.video, isNotNull);
      expect(m.video!.height, 720);
      expect(m.audio, isNotNull);
      expect(m.audio!.isAudio, isTrue);
    });

    test('best selects the tallest video', () {
      final m = parseDashManifest(
        _twoTrackMpd,
        'https://cdn.test/x.mpd',
        quality: 'best',
      );
      expect(m!.video!.height, 1080);
    });

    test(r'expands $Number$ segments against the period duration', () {
      final m = parseDashManifest(
        _twoTrackMpd,
        'https://cdn.test/x.mpd',
        quality: 'best',
      );
      // 8s period / 4s segments = 2 segments, numbered from startNumber=1.
      expect(m!.video!.segmentUrls, [
        'https://cdn.test/v/1.m4s',
        'https://cdn.test/v/2.m4s',
      ]);
      expect(m.video!.initUrl, 'https://cdn.test/v/init.mp4');
    });

    test('expands a SegmentTimeline (time-based) into segments', () {
      final m = parseDashManifest(
        _timelineMpd,
        'https://cdn.test/x.mpd',
      );
      expect(m!.video!.segmentUrls, [
        'https://cdn.test/seg-0.m4s',
        'https://cdn.test/seg-4000.m4s',
        'https://cdn.test/seg-8000.m4s',
      ]);
    });

    test('rejects CENC-encrypted manifests', () {
      const enc = '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011">
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <ContentProtection schemeIdUri="urn:mpeg:dash:mp4protection:2011"
                         cenc:default_KID="12345678-1234-1234-1234-123456789012"/>
      <Representation id="v" bandwidth="500000" height="480">
        <BaseURL>v.mp4</BaseURL>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>
''';
      expect(parseDashManifest(enc, 'https://cdn.test/x.mpd'), isNull);
    });

    test('returns null for a non-MPD document', () {
      expect(parseDashManifest('<html></html>', 'https://cdn.test/x.mpd'), isNull);
    });
  });

  group('DashDownloader', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('dash-dl');
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test('downloads video + audio tracks and reports completion', () async {
      final adapter = _DashAdapter(_twoTrackMpd);
      final out = '${dir.path}/ep.mp4';
      var lastProgress = 0.0;
      final res = await DashDownloader(_dioWith(adapter)).download(
        url: 'https://cdn.test/x.mpd',
        headers: const {},
        outputPath: out,
        preferredQuality: 'best',
        onProgress: (p) => lastProgress = p,
        canceled: () => false,
      );

      expect(res.isOk, isTrue, reason: res.error);
      expect(res.videoPath, isNotNull);
      expect(res.audioPath, isNotNull);
      expect(File(res.videoPath!).existsSync(), isTrue);
      expect(File(res.audioPath!).existsSync(), isTrue);
      expect(lastProgress, 1.0);
      // init + 2 segments per track.
      expect(
        adapter.attempts.where((u) => u.contains('/v/')).length,
        3,
      );
      expect(
        adapter.attempts.where((u) => u.contains('/a/')).length,
        3,
      );
    });

    test('retries a flaky segment and still succeeds', () async {
      final adapter = _DashAdapter(_twoTrackMpd, failFor: 'v/1.m4s', failures: 2);
      final res = await DashDownloader(_dioWith(adapter)).download(
        url: 'https://cdn.test/x.mpd',
        headers: const {},
        outputPath: '${dir.path}/ep.mp4',
        preferredQuality: 'best',
        onProgress: (_) {},
        canceled: () => false,
      );
      expect(res.isOk, isTrue, reason: res.error);
      final tries = adapter.attempts.where((u) => u.contains('v/1.m4s')).length;
      expect(tries, 3);
    });

    test('fails and cleans up when a segment never recovers', () async {
      final adapter = _DashAdapter(_twoTrackMpd, failFor: 'v/2.m4s', failures: 999);
      final res = await DashDownloader(_dioWith(adapter)).download(
        url: 'https://cdn.test/x.mpd',
        headers: const {},
        outputPath: '${dir.path}/ep.mp4',
        preferredQuality: 'best',
        onProgress: (_) {},
        canceled: () => false,
      );
      expect(res.isOk, isFalse);
      // No partial track files left behind.
      final leftovers = dir
          .listSync()
          .where((f) => f.path.endsWith('.mp4'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('fails cleanly on an unreachable manifest', () async {
      final adapter = _DashAdapter('<MPD/>');
      final res = await DashDownloader(_dioWith(adapter)).download(
        url: 'https://cdn.test/x.mpd',
        headers: const {},
        outputPath: '${dir.path}/ep.mp4',
        preferredQuality: 'best',
        onProgress: (_) {},
        canceled: () => false,
      );
      expect(res.isOk, isFalse);
    });
  });
}
