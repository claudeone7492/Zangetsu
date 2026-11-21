import 'package:dio/dio.dart';

import 'tmdb.dart';

/// One TMDB browse row, ported from Hikari's `data/TmdbBrowse.kt`.
///
/// A row is a TMDB endpoint plus the query it is asked with; the row id fully
/// determines that endpoint, so a page request needs no offset bookkeeping.
class TmdbBrowseRow {
  const TmdbBrowseRow({
    required this.id,
    required this.path,
    required this.params,
    required this.titleKey,
    this.series = false,
  });

  final String id;
  final String path;
  final Map<String, String> params;

  /// l10n key for the row title — the catalogue is shown to the user, so the
  /// name is translated rather than hard-coded English.
  final String titleKey;
  final bool series;

  /// Every catalog id this object produces starts with [TmdbBrowse.prefix],
  /// so a caller can tell "browse TMDB for me" from a provider's own id.
  String get catalogId => '${TmdbBrowse.prefix}$id';
}

/// A title from a row, a search, or the details behind one.
class TmdbBrowseItem {
  const TmdbBrowseItem({
    required this.id,
    required this.title,
    required this.series,
    this.poster,
    this.backdrop,
    this.overview,
    this.originalTitle,
    this.year,
    this.rating,
    this.nsfw = false,
  });

  final String id;
  final String title;
  final bool series;
  final String? poster;
  final String? backdrop;
  final String? overview;
  final String? originalTitle;
  final int? year;
  final double? rating;
  final bool nsfw;

  String get uniqueId => '${series ? 'tv' : 'movie'}-$id';
}

/// One episode of a TMDB series.
class TmdbBrowseEpisode {
  const TmdbBrowseEpisode({
    required this.season,
    required this.number,
    required this.name,
    this.overview,
    this.image,
    this.released,
    this.rating,
    this.runtime,
  });

  final int season;
  final int number;
  final String name;
  final String? overview;
  final String? image;
  final String? released;
  final double? rating;
  final int? runtime;
}

class TmdbBrowse {
  TmdbBrowse(this._dio);

  final Dio _dio;

  static const String prefix = 'tmdb-';
  static const String _img = 'https://image.tmdb.org/t/p/w500';
  static const String _imgLarge = 'https://image.tmdb.org/t/p/w1280';
  static const int _maxSeasons = 24;

  static const List<TmdbBrowseRow> generalRows = [
    TmdbBrowseRow(
      id: 'trending',
      path: '/trending/all/week',
      params: {},
      titleKey: 'tmdbTrending',
    ),
    TmdbBrowseRow(
      id: 'movies',
      path: '/movie/popular',
      params: {},
      titleKey: 'tmdbPopularMovies',
    ),
    TmdbBrowseRow(
      id: 'movies-top',
      path: '/movie/top_rated',
      params: {},
      titleKey: 'tmdbTopRatedMovies',
    ),
    TmdbBrowseRow(
      id: 'series',
      path: '/tv/popular',
      params: {},
      titleKey: 'tmdbPopularSeries',
      series: true,
    ),
    TmdbBrowseRow(
      id: 'series-top',
      path: '/tv/top_rated',
      params: {},
      titleKey: 'tmdbTopRatedSeries',
      series: true,
    ),
    TmdbBrowseRow(
      id: 'airing',
      path: '/tv/on_the_air',
      params: {},
      titleKey: 'tmdbOnTv',
      series: true,
    ),
  ];

  static const List<TmdbBrowseRow> animeRows = [
    TmdbBrowseRow(
      id: 'anime',
      path: '/discover/tv',
      params: {
        'with_genres': '16',
        'with_origin_country': 'JP',
        'sort_by': 'popularity.desc',
      },
      titleKey: 'tmdbPopularAnime',
      series: true,
    ),
    TmdbBrowseRow(
      id: 'anime-top',
      path: '/discover/tv',
      params: {
        'with_genres': '16',
        'with_origin_country': 'JP',
        'sort_by': 'vote_average.desc',
        'vote_count.gte': '100',
      },
      titleKey: 'tmdbTopRatedAnime',
      series: true,
    ),
    TmdbBrowseRow(
      id: 'anime-new',
      path: '/discover/tv',
      params: {
        'with_genres': '16',
        'with_origin_country': 'JP',
        'sort_by': 'first_air_date.desc',
      },
      titleKey: 'tmdbNewAnime',
      series: true,
    ),
    TmdbBrowseRow(
      id: 'anime-movies',
      path: '/discover/movie',
      params: {
        'with_genres': '16',
        'with_origin_country': 'JP',
        'sort_by': 'popularity.desc',
      },
      titleKey: 'tmdbAnimeMovies',
    ),
  ];

  static const List<TmdbBrowseRow> hindiRows = [
    TmdbBrowseRow(
      id: 'hindi',
      path: '/discover/movie',
      params: {'with_original_language': 'hi', 'sort_by': 'popularity.desc'},
      titleKey: 'tmdbPopularHindiMovies',
    ),
  ];

  static const List<TmdbBrowseRow> kdramaRows = [
    TmdbBrowseRow(
      id: 'kdrama',
      path: '/discover/tv',
      params: {'with_original_language': 'ko', 'sort_by': 'popularity.desc'},
      titleKey: 'tmdbPopularKoreanDramas',
      series: true,
    ),
  ];

  static const List<TmdbBrowseRow> frenchRows = [
    TmdbBrowseRow(
      id: 'french',
      path: '/discover/movie',
      params: {'with_original_language': 'fr', 'sort_by': 'popularity.desc'},
      titleKey: 'tmdbPopularFrenchMovies',
    ),
  ];

  static const List<TmdbBrowseRow> persianRows = [
    TmdbBrowseRow(
      id: 'persian',
      path: '/discover/movie',
      params: {'with_original_language': 'fa', 'sort_by': 'popularity.desc'},
      titleKey: 'tmdbPopularPersianMovies',
    ),
  ];

  static List<TmdbBrowseRow> get allRows => [
    ...generalRows,
    ...animeRows,
    ...hindiRows,
    ...kdramaRows,
    ...frenchRows,
    ...persianRows,
  ];

  /// The niche a source name belongs to — Hikari's `nicheOf`.
  static String nicheOf(String name) {
    final n = name.toLowerCase();
    const anime = [
      'anime',
      'hianime',
      'anidb',
      'anikoto',
      'kurage',
      'cartoon',
      'aniwatch',
    ];
    const hindi = [
      'desi',
      'hindi',
      'hindmoviez',
      'einthusan',
      'hdhub',
      'hdghar',
      '4khdhub',
      'moviebox',
      'vegamovies',
      'bollywood',
      'phisher',
    ];
    const kdrama = ['kdrama', 'kisskh', 'drama'];
    const french = [
      'movix',
      'nakios',
      'wiflix',
      'vostfr',
      'french',
      'streamingvf',
    ];
    if (anime.any(n.contains)) return 'anime';
    if (hindi.any(n.contains)) return 'hindi';
    if (kdrama.any(n.contains)) return 'kdrama';
    if (french.any(n.contains)) return 'french';
    if (n.contains('persian')) return 'persian';
    return 'general';
  }

  /// The rows [name] should show: its niche's pool, rotated by [seed] so two
  /// sources of the same niche start on different rows.
  static List<TmdbBrowseRow> rowsFor(String name, int seed, {int take = 3}) {
    final pool = switch (nicheOf(name)) {
      'anime' => animeRows,
      'hindi' => hindiRows,
      'kdrama' => kdramaRows,
      'french' => frenchRows,
      'persian' => persianRows,
      _ => generalRows,
    };
    if (pool.isEmpty) return const [];
    final start = ((seed % pool.length) + pool.length) % pool.length;
    final count = take.clamp(0, pool.length);
    return [for (var i = 0; i < count; i++) pool[(start + i) % pool.length]];
  }

  static bool isOurCatalog(String catalogId) => catalogId.startsWith(prefix);

  static TmdbBrowseRow? rowFor(String catalogId) {
    for (final row in allRows) {
      if (row.catalogId == catalogId) return row;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _get(
    String path,
    Map<String, String> params,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '${Tmdb.base}$path',
        queryParameters: params.isEmpty ? null : params,
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  /// One page of [catalogId]'s row.
  Future<List<TmdbBrowseItem>> items(String catalogId, {int page = 1}) async {
    final row = rowFor(catalogId);
    if (row == null) return const [];
    final data = await _get(row.path, {
      ...row.params,
      'page': page.clamp(1, 500).toString(),
    });
    final results = data?['results'];
    if (results is! List) return const [];
    final out = <TmdbBrowseItem>[];
    for (final entry in results) {
      if (entry is! Map) continue;
      final item = _toItem(
        Map<String, dynamic>.from(entry),
        series: row.series ? true : null,
      );
      if (item != null) out.add(item);
    }
    final seen = <String>{};
    return out.where((i) => seen.add(i.uniqueId)).take(40).toList();
  }

  /// A title search over TMDB, for a source with no search of its own.
  Future<List<TmdbBrowseItem>> search(String query, {int page = 1}) async {
    if (query.trim().isEmpty) return const [];
    final data = await _get('/search/multi', {
      'query': query,
      'page': page.clamp(1, 500).toString(),
      'include_adult': 'false',
    });
    final results = data?['results'];
    if (results is! List) return const [];
    final out = <TmdbBrowseItem>[];
    for (final entry in results) {
      if (entry is! Map) continue;
      final item = _toItem(Map<String, dynamic>.from(entry));
      if (item != null) out.add(item);
    }
    final seen = <String>{};
    return out.where((i) => seen.add(i.uniqueId)).toList();
  }

  TmdbBrowseItem? _toItem(Map<String, dynamic> o, {bool? series}) {
    final id = (o['id'] ?? '').toString().trim();
    if (id.isEmpty || id == 'null') return null;
    final rawType = (o['media_type'] as String? ?? '').ifEmpty(
      series == true
          ? 'tv'
          : series == false
          ? 'movie'
          : '',
    );
    if (rawType.isEmpty) return null;
    final isSeries = rawType == 'tv';
    final title =
        (((isSeries ? o['name'] : o['title']) as String?) ??
                (o['title'] as String?) ??
                (o['name'] as String?) ??
                '')
            .trim();
    if (title.isEmpty) return null;
    final date =
        ((isSeries ? o['first_air_date'] : o['release_date']) as String?) ?? '';
    final vote = (o['vote_average'] as num?)?.toDouble() ?? 0;
    final original =
        ((isSeries ? o['original_name'] : o['original_title']) as String?) ?? '';
    return TmdbBrowseItem(
      id: id,
      title: title,
      series: isSeries,
      poster: _image(o['poster_path'] as String?, _img),
      backdrop: _image(o['backdrop_path'] as String?, _imgLarge),
      overview: (o['overview'] as String?)?.trim().ifEmptyNull(),
      originalTitle: original.isNotEmpty && original != title ? original : null,
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null,
      rating: vote > 0 ? vote : null,
      nsfw: o['adult'] == true,
    );
  }

  /// The full details behind an item.
  Future<TmdbBrowseItem> meta(TmdbBrowseItem item) async {
    final kind = item.series ? 'tv' : 'movie';
    final d = await _get('/$kind/${item.id}', const {});
    if (d == null) return item;
    final date =
        ((item.series ? d['first_air_date'] : d['release_date']) as String?) ??
        '';
    final vote = (d['vote_average'] as num?)?.toDouble() ?? 0;
    return TmdbBrowseItem(
      id: item.id,
      title: ((item.series ? d['name'] : d['title']) as String? ?? '').ifEmpty(
        item.title,
      ),
      series: item.series,
      poster: _image(d['poster_path'] as String?, _img) ?? item.poster,
      backdrop:
          _image(d['backdrop_path'] as String?, _imgLarge) ?? item.backdrop,
      overview: (d['overview'] as String?)
          ?.ifEmpty(item.overview ?? '')
          .ifEmptyNull(),
      originalTitle: item.originalTitle,
      year: date.length >= 4 ? int.tryParse(date.substring(0, 4)) : item.year,
      rating: vote > 0 ? vote : item.rating,
      nsfw: item.nsfw,
    );
  }

  /// Every released episode of a series, seasons fetched in parallel.
  Future<List<TmdbBrowseEpisode>> episodes(TmdbBrowseItem item) async {
    if (!item.series) return const [];
    final show = await _get('/tv/${item.id}', const {});
    final seasons = show?['seasons'];
    if (seasons is! List) return const [];
    final numbers = <int>[];
    for (final entry in seasons) {
      if (entry is! Map) continue;
      final n = (entry['season_number'] as num?)?.toInt() ?? -1;
      final count = (entry['episode_count'] as num?)?.toInt() ?? 0;
      if (n < 0 || count <= 0) continue;
      numbers.add(n);
      if (numbers.length >= _maxSeasons) break;
    }
    if (numbers.isEmpty) return const [];
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final loaded = await Future.wait([
      for (final n in numbers)
        _get('/tv/${item.id}/season/$n', const {}).then((v) => (n, v)),
    ]);
    final out = <TmdbBrowseEpisode>[];
    for (final (n, season) in loaded) {
      final eps = season?['episodes'];
      if (eps is! List) continue;
      for (final entry in eps) {
        if (entry is! Map) continue;
        final number = (entry['episode_number'] as num?)?.toInt() ?? -1;
        if (number < 0) continue;
        final air = entry['air_date'] as String? ?? '';
        if (air.length >= 10 && air.compareTo(today) > 0) continue;
        final vote = (entry['vote_average'] as num?)?.toDouble() ?? 0;
        out.add(
          TmdbBrowseEpisode(
            season: n,
            number: number,
            name: (entry['name'] as String? ?? '').ifEmpty('Episode $number'),
            overview: (entry['overview'] as String?)?.ifEmptyNull(),
            image: _image(entry['still_path'] as String?, _img),
            released: air.isEmpty ? null : air,
            rating: vote > 0 ? vote : null,
            runtime: (entry['runtime'] as num?)?.toInt(),
          ),
        );
      }
    }
    out.sort((a, b) {
      final bySeason = a.season.compareTo(b.season);
      return bySeason != 0 ? bySeason : a.number.compareTo(b.number);
    });
    return out;
  }

  /// The IMDb id behind a TMDB title, for trackers.
  Future<String?> imdbId(String tmdbId, {required bool series}) async {
    final d = await _get(
      '/${series ? 'tv' : 'movie'}/$tmdbId/external_ids',
      const {},
    );
    final imdb = d?['imdb_id'] as String?;
    return imdb != null && imdb.startsWith('tt') && imdb.length > 3
        ? imdb
        : null;
  }

  static String? _image(String? path, String base) =>
      path == null || path.isEmpty || path == 'null' ? null : '$base$path';
}

extension _StringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
  String? ifEmptyNull() => isEmpty ? null : this;
}
