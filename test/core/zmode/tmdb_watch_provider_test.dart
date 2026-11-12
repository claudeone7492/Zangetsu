import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/ui/streaming_prefs.dart';
import 'package:watch_app/core/zmode/metadata_filters.dart';
import 'package:watch_app/core/zmode/tmdb_catalogue.dart';

Map<String, dynamic> _page(List<(int, String)> rows) => {
  'results': [
    for (final (id, title) in rows)
      {'id': id, 'name': title, 'title': title, 'poster_path': '/p.png'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late List<(String, Map<String, dynamic>)> calls;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tmdb_wp');
    Hive.init(dir.path);
    await StreamingPrefs.init();
    StreamingPrefs.deviceRegion = () => 'IN';
    calls = [];
  });

  tearDown(() async {
    StreamingPrefs.resetDeviceRegionForTest();
    await Hive.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  TmdbCatalogue build(Map<String, Map<String, dynamic>> byPath) =>
      TmdbCatalogue((path, params) async {
        calls.add((path, params));
        return byPath[path];
      });

  test(
    'a wp: row queries both discover endpoints with the provider and region',
    () async {
      final c = build({
        '/discover/tv': _page([(1, 'Show')]),
        '/discover/movie': _page([(2, 'Film')]),
      });

      await c.browseRow(TmdbCatalogue.wpRowId(8), 2);

      expect(calls.map((c) => c.$1).toSet(), {
        '/discover/tv',
        '/discover/movie',
      });
      for (final (_, params) in calls) {
        expect(params['with_watch_providers'], '8');
        expect(params['watch_region'], 'IN');
        expect(params['page'], 2);
      }
    },
  );

  test('the region is read per call, not frozen at construction', () async {
    final c = build({
      '/discover/tv': _page([(1, 'Show')]),
      '/discover/movie': _page([(2, 'Film')]),
    });
    await c.browseRow(TmdbCatalogue.wpRowId(8), 1);
    await StreamingPrefs.setRegion('GB');
    calls.clear();
    await c.browseRow(TmdbCatalogue.wpRowId(8), 1);
    for (final (_, params) in calls) {
      expect(params['watch_region'], 'GB');
    }
  });

  test('series and films are interleaved, not one then the other', () async {
    final c = build({
      '/discover/tv': _page([(1, 'S1'), (3, 'S2'), (5, 'S3')]),
      '/discover/movie': _page([(2, 'M1'), (4, 'M2')]),
    });

    final items = await c.browseRow(TmdbCatalogue.wpRowId(8), 1);

    expect(items.map((i) => i.title).toList(), ['S1', 'M1', 'S2', 'M2', 'S3']);
  });

  test('one endpoint failing still returns the other', () async {
    final c = build({
      '/discover/tv': _page([(1, 'S1')]),
    });
    final items = await c.browseRow(TmdbCatalogue.wpRowId(8), 1);
    expect(items.map((i) => i.title).toList(), ['S1']);
  });

  test(
    'a series from a wp: row is typed as a series, a film as a film',
    () async {
      final c = build({
        '/discover/tv': _page([(1, 'S1')]),
        '/discover/movie': _page([(2, 'M1')]),
      });
      final items = await c.browseRow(TmdbCatalogue.wpRowId(8), 1);
      expect(items.firstWhere((i) => i.title == 'S1').tmdbIsTv, isTrue);
      expect(items.firstWhere((i) => i.title == 'M1').tmdbIsTv, isFalse);
    },
  );

  test('a malformed wp: id is an empty list, not a crash', () async {
    final c = build({});
    expect(await c.browseRow('wp:', 1), isEmpty);
    expect(await c.browseRow('wp:abc', 1), isEmpty);
    expect(calls, isEmpty, reason: 'nothing to ask for, so do not ask');
  });

  test(
    'service search keeps only titles offered by that service in region',
    () async {
      final c = build({
        '/search/multi': {
          'results': [
            {
              'id': 11,
              'media_type': 'movie',
              'title': 'Movie match',
              'release_date': '2024-01-01',
            },
            {
              'id': 22,
              'media_type': 'tv',
              'name': 'Series match',
              'first_air_date': '2023-01-01',
            },
            {'id': 33, 'media_type': 'movie', 'title': 'Other service'},
          ],
        },
        '/movie/11/watch/providers': {
          'results': {
            'IN': {
              'flatrate': [
                {'provider_id': 8},
              ],
            },
          },
        },
        '/tv/22/watch/providers': {
          'results': {
            'IN': {
              'flatrate': [
                {'provider_id': 8},
              ],
            },
          },
        },
        '/movie/33/watch/providers': {
          'results': {
            'IN': {
              'flatrate': [
                {'provider_id': 9},
              ],
            },
          },
        },
      });

      final items = (await c.searchProvider(8, 'match')).items;

      expect(items.map((item) => item.title), ['Movie match', 'Series match']);
      expect(items.map((item) => item.tmdbIsTv), [false, true]);
      expect(
        calls.where((call) => call.$1 == '/search/multi').single.$2,
        containsPair('query', 'match'),
      );
      expect(
        calls.where((call) => call.$1.endsWith('/watch/providers')),
        hasLength(3),
      );
    },
  );

  test('service search reuses cached provider availability', () async {
    final c = build({
      '/search/multi': {
        'results': [
          {'id': 11, 'media_type': 'movie', 'title': 'Movie match'},
        ],
      },
      '/movie/11/watch/providers': {
        'results': {
          'IN': {
            'flatrate': [
              {'provider_id': 8},
            ],
          },
        },
      },
    });

    await c.searchProvider(8, 'match');
    await c.searchProvider(8, 'match');

    expect(
      calls.where((call) => call.$1 == '/movie/11/watch/providers'),
      hasLength(1),
    );
  });

  test(
    'filtered service browse keeps provider and region constraints',
    () async {
      final c = build({
        '/discover/tv': _page([(1, 'Series')]),
      });

      await c.browseProvider(
        8,
        2,
        filters: const MetaFilters(
          format: MetaFormat.tv,
          genres: ['Action'],
          yearFrom: 2024,
          yearTo: 2024,
          minScore: 80,
          sort: MetaSort.score,
        ),
      );

      expect(calls, hasLength(1));
      expect(calls.single.$1, '/discover/tv');
      expect(calls.single.$2, containsPair('with_watch_providers', '8'));
      expect(calls.single.$2, containsPair('watch_region', 'IN'));
      expect(calls.single.$2, containsPair('first_air_date.gte', '2024-01-01'));
      expect(calls.single.$2, containsPair('first_air_date.lte', '2024-12-31'));
      expect(calls.single.$2, containsPair('vote_average.gte', 8.0));
      expect(calls.single.$2, containsPair('page', 2));
    },
  );

  test('movie-only genres do not broaden mixed service TV results', () async {
    final c = build({
      '/discover/tv': _page([(1, 'Unfiltered series')]),
      '/discover/movie': _page([(2, 'Horror film')]),
    });

    final items = (await c.browseProvider(
      8,
      1,
      filters: const MetaFilters(genres: ['Horror']),
    )).items;

    expect(calls.map((call) => call.$1), ['/discover/movie']);
    expect(items.map((item) => item.title), ['Horror film']);
  });

  test(
    'provider search preserves more-pages after an empty filtered page',
    () async {
      final c = TmdbCatalogue((path, params) async {
        calls.add((path, params));
        if (path == '/search/multi') {
          return {
            'total_pages': 2,
            'results': params['page'] == 1
                ? const []
                : [
                    {'id': 31, 'media_type': 'movie', 'title': 'Later match'},
                  ],
          };
        }
        if (path == '/movie/31/watch/providers') {
          return {
            'results': {
              'IN': {
                'flatrate': [
                  {'provider_id': 8},
                ],
              },
            },
          };
        }
        return null;
      });

      final first = await c.searchProvider(8, 'match', page: 1);
      final second = await c.searchProvider(8, 'match', page: 2);

      expect(first.items, isEmpty);
      expect(first.hasMore, isTrue);
      expect(second.items.single.title, 'Later match');
      expect(second.hasMore, isFalse);
    },
  );

  test('the existing path endpoints are untouched', () async {
    final c = build({
      '/movie/popular': _page([(9, 'Pop')]),
    });
    final items = await c.browseRow('/movie/popular', 3);
    expect(items.single.title, 'Pop');
    expect(calls.single.$1, '/movie/popular');
    expect(calls.single.$2['page'], 3);
  });
}
