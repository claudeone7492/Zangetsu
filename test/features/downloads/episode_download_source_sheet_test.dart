import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/download/download_size_estimate.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/download/download_record.dart';
import 'package:watch_app/features/downloads/episode_download_source_sheet.dart';

const _episode = Episode(
  id: 'ep-1',
  title: 'Episode 1',
  url: 'ep-1',
  number: 1,
  season: 1,
  runtimeMinutes: 24,
);

VideoSource _source(String url, String quality) =>
    VideoSource(url: url, quality: quality, container: SourceContainer.mp4);

Future<void> _openSheet(
  WidgetTester tester, {
  required Future<List<VideoSource>> Function(Episode) resolve,
  List<VideoSource> initialSources = const [],
  Future<SizeEstimate?> Function(VideoSource source, int? runtimeMinutes)?
  estimateSize,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<SingleEpisodeDownloadChoice>(
              context: context,
              builder: (_) => EpisodeDownloadSourceSheet(
                title: 'Some Show',
                category: 'sub',
                episode: _episode,
                availableCategories: const ['sub'],
                resolveEpisodes: (_) async => {1: const [_episode]},
                resolve: resolve,
                initialSources: initialSources,
                estimateSize:
                    estimateSize ??
                    (_, _) async => (bytes: 100 << 20, solid: true),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

void main() {
  setUp(() => sl.registerSingleton<AppMode>(const AppMode(isTv: false)));
  tearDown(() => sl.reset());

  testWidgets('qualities lay out as grid tiles, not a full-width list', (
    tester,
  ) async {
    await _openSheet(
      tester,
      resolve: (_) async => [
        _source('https://cdn.test/1.mp4', '1080p'),
        _source('https://cdn.test/2.mp4', '720p'),
        _source('https://cdn.test/3.mp4', '480p'),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
  });

  testWidgets('each quality carries its own estimated size', (tester) async {
    await _openSheet(
      tester,
      resolve: (_) async => [
        _source('https://cdn.test/1.mp4', '1080p'),
        _source('https://cdn.test/2.mp4', '720p'),
      ],
      estimateSize: (source, _) async =>
          (bytes: source.quality == '1080p' ? 200 << 20 : 60 << 20, solid: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('~200 MB'), findsOneWidget);
    expect(find.text('~60 MB'), findsOneWidget);
  });

  testWidgets('best quality leads the grid and is badged', (tester) async {
    await _openSheet(
      tester,
      resolve: (_) async => [
        _source('https://cdn.test/1.mp4', '480p'),
        _source('https://cdn.test/2.mp4', '1080p'),
        _source('https://cdn.test/3.mp4', '720p'),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Best'), findsOneWidget);
    final bestTile = find.ancestor(
      of: find.text('1080p'),
      matching: find.byType(Material),
    );
    expect(
      find.descendant(of: bestTile.first, matching: find.text('Best')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text('1080p')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('720p')).dy),
    );
  });

  testWidgets('refresh asks the resolver again', (tester) async {
    var calls = 0;
    await _openSheet(
      tester,
      resolve: (_) async {
        calls++;
        return [_source('https://cdn.test/1.mp4', '1080p')];
      },
    );
    await tester.pumpAndSettle();
    expect(calls, 1);

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('a failed resolve offers Retry and recovers', (tester) async {
    var calls = 0;
    await _openSheet(
      tester,
      resolve: (_) async {
        calls++;
        if (calls == 1) throw StateError('provider exploded');
        return [_source('https://cdn.test/1.mp4', '1080p')];
      },
    );
    await tester.pumpAndSettle();

    expect(find.text("Couldn't load download options"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
  });

  testWidgets('sources already resolved by the player show up immediately', (
    tester,
  ) async {
    final pending = Completer<List<VideoSource>>();
    await _openSheet(
      tester,
      resolve: (_) => pending.future,
      initialSources: [
        _source('https://cdn.test/1.mp4', '1080p'),
        _source('https://cdn.test/2.mp4', '720p'),
      ],
    );
    await tester.pump();

    expect(find.byType(GridView), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);

    pending.complete(const []);
    await tester.pumpAndSettle();
    // A stale empty sweep must not wipe the list the caller supplied.
    expect(find.text('1080p'), findsOneWidget);
  });

  testWidgets('duplicate mirrors collapse to one tile', (tester) async {
    await _openSheet(
      tester,
      resolve: (_) async => [
        _source('https://cdn.test/1.mp4', '1080p'),
        _source('https://cdn.test/1.mp4', '1080p'),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('1 sources'), findsOneWidget);
  });

  testWidgets('subtitle and audio badges ride along with the quality', (
    tester,
  ) async {
    await _openSheet(
      tester,
      resolve: (_) async => [
        VideoSource(
          url: 'https://cdn.test/1.m3u8',
          quality: '1080p',
          container: SourceContainer.hls,
          audioLang: 'Tamil',
          subtitles: const [
            Subtitle(url: 'https://cdn.test/subs.vtt', lang: 'en'),
          ],
        ),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('HLS'), findsOneWidget);
    expect(find.text('CC'), findsOneWidget);
    expect(find.textContaining('Tamil'), findsOneWidget);
  });

  testWidgets('tapping a tile returns the chosen mirror', (tester) async {
    SingleEpisodeDownloadChoice? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showModalBottomSheet<SingleEpisodeDownloadChoice>(
                  context: context,
                  builder: (_) => EpisodeDownloadSourceSheet(
                    title: 'Some Show',
                    category: 'sub',
                    episode: _episode,
                    availableCategories: const ['sub'],
                    resolveEpisodes: (_) async => {1: const [_episode]},
                    resolve: (_) async => [_source('https://cdn.test/1.mp4', '1080p')],
                    estimateSize: (_, _) async => null,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();

    expect(picked?.chosen.quality, '1080p');
    expect(picked?.episode.id, _episode.id);
  });

  test(
    'download identity uses the detail ID when history only has a URL',
    () async {
      expect(
        await resolveEpisodeDownloadShowId(
          sourceId: 'source',
          showUrl: 'https://show.test/123',
          downloads: const [],
          loadShowId: () async => '123',
        ),
        '123',
      );
      expect(
        await resolveEpisodeDownloadShowId(
          sourceId: 'source',
          showUrl: 'https://show.test/123',
          knownId: '123',
          downloads: const [],
          loadShowId: () => throw StateError('must not fetch'),
        ),
        '123',
      );
    },
  );
  test(
    'existing download group is reused without another metadata request',
    () async {
      const record = DownloadRecord(
        id: 'download',
        sourceId: 'source',
        showId: 'saved-group',
        showTitle: 'Title',
        showUrl: 'https://show.test/title',
        episodeId: '1',
        episodeUrl: 'ep-1',
        episodeTitle: 'First',
        category: 'sub',
        quality: '1080p',
        createdAt: 0,
      );
      expect(
        await resolveEpisodeDownloadShowId(
          sourceId: 'source',
          showUrl: record.showUrl,
          downloads: const [record],
          loadShowId: () => throw StateError('must not fetch'),
        ),
        'saved-group',
      );
    },
  );
  test(
    'missing canonical ID fails instead of creating a URL-named group',
    () async {
      expect(
        resolveEpisodeDownloadShowId(
          sourceId: 'source',
          showUrl: 'https://show.test/123',
          downloads: const [],
          loadShowId: () async => '',
        ),
        throwsStateError,
      );
    },
  );

  const original = Episode(
    id: 'sub',
    title: 'Episode 2',
    url: 'sub',
    number: 2,
    season: 1,
  );
  const dub = Episode(
    id: 'dub',
    title: 'Episode 2 dubbed',
    url: 'dub',
    number: 2,
    season: 1,
  );
  test(
    'alternate cut matches season and episode instead of its list position',
    () {
      expect(
        matchDownloadEpisode(original, const [
          Episode(
            id: 'other',
            title: 'Other season',
            url: 'other',
            number: 2,
            season: 2,
          ),
          dub,
        ]),
        same(dub),
      );
    },
  );
  test(
    'ambiguous or missing alternate cut never downloads a different episode',
    () {
      expect(matchDownloadEpisode(original, const [dub, dub]), isNull);
      expect(matchDownloadEpisode(original, const []), isNull);
    },
  );
}
