import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/download/download_source_cache.dart';
import 'package:watch_app/core/download/download_source_resolver.dart';
import 'package:watch_app/core/models/video_source.dart';

VideoSource _source(String url, [String? quality]) =>
    VideoSource(url: url, quality: quality, container: SourceContainer.mp4);

void main() {
  final cache = DownloadSourceCache.instance;
  final ttl = DownloadSourceCache.ttl;
  final sizeTtl = DownloadSourceCache.sizeTtl;

  setUp(cache.clear);
  tearDown(() {
    cache.clear();
    DownloadSourceCache.ttl = ttl;
    DownloadSourceCache.sizeTtl = sizeTtl;
  });

  test('mirrors resolved once are handed back for the same episode', () {
    final sources = [_source('https://cdn.test/1.mp4', '1080p')];
    cache.storeSources('ep-1', sources);

    expect(cache.sources('ep-1')!.single.url, 'https://cdn.test/1.mp4');
    expect(cache.sources('ep-2'), isNull);
  });

  test('a resolved list expires so a dead mirror is not offered forever', () {
    DownloadSourceCache.ttl = Duration.zero;
    cache.storeSources('ep-1', [_source('https://cdn.test/1.mp4')]);

    expect(cache.sources('ep-1'), isNull);
    // Stale data is still readable by a caller that wants to paint first.
    cache.storeSources('ep-1', [_source('https://cdn.test/1.mp4')]);
    expect(cache.sources('ep-1', allowStale: true), isNotNull);
  });

  test('the queue title id is remembered per source and title', () {
    cache.storeShowId('anime', 'https://show.test/1', 'mal-42');

    expect(cache.showId('anime', 'https://show.test/1'), 'mal-42');
    expect(cache.showId('other', 'https://show.test/1'), isNull);
  });

  test('a probed-but-unknowable size is remembered as unknown', () {
    cache.storeSize('https://cdn.test/1.mp4', null);

    expect(cache.hasSize('https://cdn.test/1.mp4'), isTrue);
    expect(cache.size('https://cdn.test/1.mp4'), isNull);
    expect(cache.hasSize('https://cdn.test/2.mp4'), isFalse);
  });

  test('a measured size survives until it goes stale', () {
    const estimate = (bytes: 120 << 20, solid: true);
    cache.storeSize('https://cdn.test/1.mp4', estimate);

    expect(cache.size('https://cdn.test/1.mp4')?.bytes, 120 << 20);

    DownloadSourceCache.sizeTtl = Duration.zero;
    expect(cache.size('https://cdn.test/1.mp4'), isNull);
  });

  test('invalidate forces the next picker open to re-resolve', () {
    cache.storeSources('ep-1', [_source('https://cdn.test/1.mp4')]);
    cache.invalidate('ep-1');

    expect(cache.sources('ep-1'), isNull);
  });

  test(
    'the resolver answers from the cache without touching a provider',
    () async {
      final sources = [_source('https://cdn.test/1.mp4', '1080p')];
      cache.storeSources('ep-1', sources);

      // No GetIt registration at all: any network path would return [] here.
      final resolved = await resolveDownloadSources('ep-1');
      expect(resolved.single.url, 'https://cdn.test/1.mp4');
    },
  );

  test('refresh bypasses the cached list', () async {
    cache.storeSources('ep-1', [_source('https://cdn.test/1.mp4')]);

    expect(await resolveDownloadSources('ep-1', refresh: true), isEmpty);
  });

  test('concurrent callers share one resolve', () async {
    final first = resolveDownloadSources('ep-1');
    final second = resolveDownloadSources('ep-1');

    expect(await first, await second);
    expect(await first, isEmpty);
  });

  test('preloading an unknown episode leaves the cache untouched', () async {
    await preloadDownloadSources('ep-1');

    expect(cache.sources('ep-1'), isNull);
  });

  test('warming sizes stores each probe result once', () async {
    final sources = [
      _source('https://cdn.test/1.mp4'),
      _source('https://cdn.test/2.mp4'),
    ];
    cache.storeSize('https://cdn.test/1.mp4', const (bytes: 5, solid: false));

    await warmDownloadSizes(sources);

    expect(cache.hasSize('https://cdn.test/1.mp4'), isTrue);
    expect(cache.size('https://cdn.test/1.mp4')?.bytes, 5);
    expect(cache.hasSize('https://cdn.test/2.mp4'), isTrue);
  });
}
