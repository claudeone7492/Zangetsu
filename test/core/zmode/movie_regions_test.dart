import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/zmode/movie_regions.dart';
import 'package:watch_app/core/zmode/zmode_prefs.dart';
import 'package:watch_app/core/zmode/tmdb_catalogue.dart';

/// Every region cut asks /discover/movie with a distinguishing parameter; the
/// plain `all` cut has no discover rows at all (it keeps TMDB's own home).
void main() {
  group('MovieRegion rows', () {
    test('all has no discover rows — it keeps the plain TMDB home', () {
      expect(MovieRegion.all.isAll, isTrue);
      expect(MovieRegion.all.rows, isNull);
      for (final r in MovieRegion.values.where((r) => r != MovieRegion.all)) {
        expect(r.isAll, isFalse);
        expect(r.rows, isNotNull);
        expect(r.rows!, isNotEmpty);
        for (final row in r.rows!) {
          expect(row.path, '/discover/movie');
        }
      }
    });

    test('Hollywood is US/English, Bollywood is IN/Hindi', () {
      final hw = MovieRegion.hollywood.rows!.first;
      expect(hw.params['with_original_language'], 'en');
      expect(hw.params['region'], 'US');

      final bw = MovieRegion.bollywood.rows!.first;
      expect(bw.params['with_original_language'], 'hi');
      expect(bw.params['region'], 'IN');
    });

    test('Nollywood is Nigeria, Cartoons is the Animation genre', () {
      final nw = MovieRegion.nollywood.rows!.first;
      expect(nw.params['with_original_language'], 'en');
      expect(nw.params['region'], 'NG');

      for (final row in MovieRegion.cartoons.rows!) {
        expect(row.params['with_genres'], startsWith('16'));
      }
    });

    test('labels are the sub-menu chip text', () {
      expect(
        MovieRegion.values.map((r) => r.label).toList(),
        ['All', 'Hollywood', 'Bollywood', 'Nollywood', 'Cartoons'],
      );
    });
  });

  group('MovieRegionPrefs', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('movie_regions');
      Hive.init(dir.path);
      await ZModePrefs.init();
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('defaults to all', () {
      expect(MovieRegionPrefs.region, MovieRegion.all);
    });

    test('persists the pick and bumps the revision', () async {
      final before = MovieRegionPrefs.revision.value;
      await MovieRegionPrefs.setRegion(MovieRegion.nollywood);
      expect(MovieRegionPrefs.region, MovieRegion.nollywood);
      expect(MovieRegionPrefs.revision.value, before + 1);
    });

    test('a stored unknown value falls back to all', () async {
      await Hive.box(MovieRegionPrefs.boxName).put('movieRegion', 'klingon');
      expect(MovieRegionPrefs.region, MovieRegion.all);
    });
  });

  group('TmdbCatalogue.homeForRegion', () {
    test('all returns null so the caller keeps TMDB rows', () async {
      final cat = TmdbCatalogue((p, q) async => {'results': []});
      expect(await cat.homeForRegion(MovieRegion.all), isNull);
    });

    test('fires one discover request per row, carrying the region params',
        () async {
      final calls = <(String, Map<String, dynamic>)>[];
      final cat = TmdbCatalogue((p, q) async {
        calls.add((p, q));
        return {
          'results': [
            {
              'id': 1,
              'title': 'A Film',
              'poster_path': '/p.jpg',
              'genre_ids': const [16],
            },
          ],
        };
      });

      final rows = await cat.homeForRegion(MovieRegion.cartoons);
      expect(rows!.length, MovieRegion.cartoons.rows!.length);
      expect(calls.length, rows.length);
      for (final (path, params) in calls) {
        expect(path, '/discover/movie');
        expect(params['with_genres'], startsWith('16'));
      }
      expect(rows.first.title, 'Popular cartoons');
      // Region discover responses are films; the item must be typed as one and
      // carry the Animation genre name from its genre id.
      final item = rows.first.items.single;
      expect(item.type, ProviderType.movie);
      expect(item.tmdbIsTv, isFalse);
      expect(item.genres, contains('Animation'));
      // The row must be paginable so "See all" pages the same query.
      expect(rows.first.more!.kind, 'zm_video');
      expect(rows.first.more!.categoryId, TmdbCatalogue.discRowId(MovieRegion.cartoons, 0));
    });

    test('drops an empty discover row rather than showing a blank shelf',
        () async {
      final cat = TmdbCatalogue((p, q) async => {'results': []});
      final rows = await cat.homeForRegion(MovieRegion.hollywood);
      expect(rows, isEmpty);
    });

    test('browseDiscoverRow resolves the row id back to its query and pages it',
        () async {
      Map<String, dynamic>? lastParams;
      String? lastPath;
      final cat = TmdbCatalogue((p, q) async {
        lastPath = p;
        lastParams = q;
        return {'results': []};
      });

      final rowId = TmdbCatalogue.discRowId(MovieRegion.bollywood, 0);
      await cat.browseDiscoverRow(rowId, 3);
      expect(lastPath, '/discover/movie');
      expect(lastParams!['page'], 3);
      expect(lastParams!['with_original_language'], 'hi');
      expect(lastParams!['region'], 'IN');
    });

    test('browseDiscoverRow rejects a malformed or out-of-range id', () async {
      final cat = TmdbCatalogue((p, q) async => {'results': []});
      expect(await cat.browseDiscoverRow('disc:nope:0', 1), isEmpty);
      expect(await cat.browseDiscoverRow('disc:cartoons:99', 1), isEmpty);
      expect(await cat.browseDiscoverRow('wp:8', 1), isEmpty);
    });
  });
}
