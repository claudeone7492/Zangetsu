import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'zmode_prefs.dart';

/// The Movies & TV sub-menu: a regional/category cut of the film catalogue.
///
/// The stream kind (`movie`) already says "films and series"; this narrows it
/// further to the datasets people actually browse by — Hollywood, Bollywood,
/// Nollywood and Cartoons. Each is a fixed set of TMDB `/discover` rows
/// (`with_origin_country` + original language, plus the Animation genre for
/// Cartoons), so selecting one swaps the whole movie Home for that cut rather
/// than filtering a single row. `all` keeps TMDB's own curated rows.
///
/// `with_origin_country` — not `region` — is what actually filters by the
/// film's country of origin. `region` only shifts release-date handling, so
/// `region=NG` returned the whole English-language catalogue (20k titles) and
/// the Nollywood shelf was just Hollywood. The origin filter returns the real
/// ~1.1k Nigerian films.
enum MovieRegion { all, hollywood, bollywood, nollywood, cartoons }

/// One discover row: a title, the endpoint, and the params that make it that
/// region's shelf. The endpoint takes `?page=`, so [path]/[params] are also
/// what the "See all" grid pages.
typedef MovieRow = ({String title, String path, Map<String, String> params});

extension MovieRegionX on MovieRegion {
  /// Persisted key and the sub-menu chip label.
  String get label => switch (this) {
    MovieRegion.all => 'All',
    MovieRegion.hollywood => 'Hollywood',
    MovieRegion.bollywood => 'Bollywood',
    MovieRegion.nollywood => 'Nollywood',
    MovieRegion.cartoons => 'Cartoons',
  };

  /// The plain movie catalogue (no discover filter) — Home renders TMDB's own
  /// rows for it.
  bool get isAll => this == MovieRegion.all;

  /// The `/discover/movie` rows for this region, or null for [MovieRegion.all].
  List<MovieRow>? get rows => switch (this) {
    MovieRegion.all => null,
    MovieRegion.hollywood => const [
      (
        title: 'Popular in Hollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'US',
          'with_original_language': 'en',
          'sort_by': 'popularity.desc',
        },
      ),
      (
        title: 'Top rated Hollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'US',
          'with_original_language': 'en',
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '300',
        },
      ),
      (
        title: 'New in Hollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'US',
          'with_original_language': 'en',
          'sort_by': 'primary_release_date.desc',
        },
      ),
      (
        title: 'Hollywood Action',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'US',
          'with_original_language': 'en',
          'with_genres': '28',
          'sort_by': 'popularity.desc',
        },
      ),
    ],
    MovieRegion.bollywood => const [
      (
        title: 'Popular in Bollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'IN',
          'with_original_language': 'hi',
          'sort_by': 'popularity.desc',
        },
      ),
      (
        title: 'Top rated Bollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'IN',
          'with_original_language': 'hi',
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '100',
        },
      ),
      (
        title: 'New in Bollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'IN',
          'with_original_language': 'hi',
          'sort_by': 'primary_release_date.desc',
        },
      ),
      (
        title: 'Bollywood Drama',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'IN',
          'with_original_language': 'hi',
          'with_genres': '18',
          'sort_by': 'popularity.desc',
        },
      ),
    ],
    MovieRegion.nollywood => const [
      (
        title: 'Popular in Nollywood',
        path: '/discover/movie',
        params: {'with_origin_country': 'NG', 'sort_by': 'popularity.desc'},
      ),
      (
        title: 'New in Nollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'NG',
          'sort_by': 'primary_release_date.desc',
        },
      ),
      (
        title: 'Top rated Nollywood',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'NG',
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '20',
        },
      ),
      (
        title: 'Nollywood Drama',
        path: '/discover/movie',
        params: {
          'with_origin_country': 'NG',
          'with_genres': '18',
          'sort_by': 'popularity.desc',
        },
      ),
    ],
    MovieRegion.cartoons => const [
      (
        title: 'Popular cartoons',
        path: '/discover/movie',
        params: {'with_genres': '16', 'sort_by': 'popularity.desc'},
      ),
      (
        title: 'Top rated cartoons',
        path: '/discover/movie',
        params: {
          'with_genres': '16',
          'sort_by': 'vote_average.desc',
          'vote_count.gte': '100',
        },
      ),
      (
        title: 'Animated comedy',
        path: '/discover/movie',
        params: {'with_genres': '16,35', 'sort_by': 'popularity.desc'},
      ),
      (
        title: 'Animated family',
        path: '/discover/movie',
        params: {'with_genres': '16,10751', 'sort_by': 'popularity.desc'},
      ),
    ],
  };
}

/// The selected [MovieRegion]. Synchronous reads (Home builds on them) and a
/// revision notifier so Home reloads without resetting its scroll — same
/// contract as `StreamingPrefs`.
class MovieRegionPrefs {
  const MovieRegionPrefs._();

  // Reuses Z Mode's box, which is opened at bootstrap on every install.
  static const String boxName = ZModePrefs.boxName;
  static const String _key = 'movieRegion';

  /// Bumped on every write so listeners can rebuild/reload.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box? get _boxOrNull =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// The chosen cut, defaulting to [MovieRegion.all]. An unknown stored value
  /// falls back rather than reaching the catalogue with a dead key.
  static MovieRegion get region {
    final v = _boxOrNull?.get(_key);
    if (v is! String) return MovieRegion.all;
    return MovieRegion.values.where((r) => r.name == v).firstOrNull ??
        MovieRegion.all;
  }

  static Future<void> setRegion(MovieRegion r) async {
    if (r == region) return;
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
    await Hive.box(boxName).put(_key, r.name);
    revision.value++;
  }
}
