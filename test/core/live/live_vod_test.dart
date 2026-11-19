import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/live/catchup_url.dart';
import 'package:watch_app/core/live/live_vod.dart';

void main() {
  group('isTorrentUri / isPlayableStream', () {
    test('recognises magnets and .torrent files', () {
      expect(isTorrentUri('magnet:?xt=urn:btih:abc'), isTrue);
      expect(isTorrentUri('https://cdn/x.torrent'), isTrue);
      expect(isTorrentUri('https://cdn/x.m3u8'), isFalse);
    });

    test('recognises the schemes a player can open', () {
      expect(isPlayableStream('https://cdn/a.m3u8'), isTrue);
      expect(isPlayableStream('http://cdn/a.m3u8'), isTrue);
      expect(isPlayableStream('rtsp://cam/a'), isTrue);
      expect(isPlayableStream('udp://239.0.0.1:1234'), isTrue);
      expect(isPlayableStream('file:///local/a.ts'), isTrue);
      expect(isPlayableStream('magnet:?xt=urn:btih:abc'), isFalse);
      expect(isPlayableStream(''), isFalse);
      expect(isPlayableStream('javascript:alert(1)'), isFalse);
    });
  });

  group('planPlayback', () {
    test('an empty URL is unavailable with a reason', () {
      final plan = planPlayback(url: '   ');
      expect(plan.route, PlaybackRoute.unavailable);
      expect(plan.canPlay, isFalse);
      expect(plan.reason, isNotEmpty);
    });

    test('an http stream plays directly', () {
      final plan = planPlayback(url: 'https://cdn/live.m3u8');
      expect(plan.route, PlaybackRoute.direct);
      expect(plan.url, 'https://cdn/live.m3u8');
      expect(plan.canPlay, isTrue);
    });

    test('a magnet routes to the torrent engine', () {
      final plan = planPlayback(url: 'magnet:?xt=urn:btih:abc');
      expect(plan.route, PlaybackRoute.torrent);
      expect(plan.url, startsWith('magnet:'));
    });

    test('a .torrent URL routes to the torrent engine', () {
      final plan = planPlayback(url: 'https://cdn/movie.torrent');
      expect(plan.route, PlaybackRoute.torrent);
    });

    test('an unsupported scheme is unavailable', () {
      final plan = planPlayback(url: 'ftp://cdn/a.ts');
      expect(plan.route, PlaybackRoute.unavailable);
      expect(plan.reason, contains('Unsupported'));
    });

    test('a future airing stays direct even on a catch-up channel', () {
      final plan = planPlayback(
        url: 'https://cdn/live.m3u8',
        catchup: const CatchupSpec(mode: CatchupMode.appendQuery, days: 7),
        airingStart: DateTime.utc(2026, 1, 2, 20),
        now: DateTime.utc(2026, 1, 2, 19),
      );
      expect(plan.route, PlaybackRoute.direct);
    });

    test('a past airing on a catch-up channel builds a catch-up URL', () {
      final now = DateTime.utc(2026, 1, 2, 20);
      final plan = planPlayback(
        url: 'https://cdn/live.m3u8',
        catchup: const CatchupSpec(mode: CatchupMode.appendQuery, days: 7),
        airingStart: DateTime.utc(2026, 1, 1, 20),
        now: now,
      );
      expect(plan.route, PlaybackRoute.catchup);
      expect(plan.url, contains('utc='));
      expect(plan.canPlay, isTrue);
    });

    test('a past airing outside the retention window is unavailable', () {
      final plan = planPlayback(
        url: 'https://cdn/live.m3u8',
        catchup: const CatchupSpec(mode: CatchupMode.appendQuery, days: 2),
        airingStart: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 20, 20),
      );
      expect(plan.route, PlaybackRoute.unavailable);
      expect(plan.reason, contains('Catch-up'));
    });

    test('a channel without catch-up plays a past airing directly', () {
      final plan = planPlayback(
        url: 'https://cdn/live.m3u8',
        airingStart: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 2, 20),
      );
      expect(plan.route, PlaybackRoute.direct);
    });

    test('planLive and planVod are direct for ordinary URLs', () {
      expect(planLive(url: 'https://cdn/a.m3u8').route, PlaybackRoute.direct);
      expect(planVod(url: 'https://cdn/a.mp4').route, PlaybackRoute.direct);
      expect(
        planVod(url: 'magnet:?xt=urn:btih:x').route,
        PlaybackRoute.torrent,
      );
    });
  });
}
