import 'package:dio/dio.dart';

import '../metadata/tmdb.dart';
import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../ui/streaming_prefs.dart';
import 'video_catalogue.dart';
import 'metadata_filters.dart';
import 'movie_regions.dart';
import 'zmode_ids.dart';

typedef TmdbGet =
    Future<Map<String, dynamic>?> Function(
      String path,
      Map<String, dynamic> params,
    );

/// TMDB as a browsing catalogue for films and series. `sl<Dio>()` already
/// attaches the API key, so paths are relative to [Tmdb.base].
class TmdbCatalogue implements VideoCatalogue {
  TmdbCatalogue(this._get);
  final TmdbGet _get;

  /// Search checks are requested only after the user submits a query. Keeping
  /// provider availability for a title avoids repeating one TMDB request per
  /// result when they refine or repeat that search.
  final Map<String, Map<String, Set<int>>> _watchProviderCache = {};

  /// Production transport. Same shape as `ComingSoonService` — the API key
  /// is attached by the Dio interceptor wired in initDependencies, so this
  /// never adds one itself.
  static TmdbGet dioGet(Dio dio) => (path, params) async {
    try {
      final res = await dio.get<dynamic>(
        '${Tmdb.base}$path',
        queryParameters: params,
      );
      final d = res.data;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return null;
  };

  /// Row titles without a fetch — see [AniListCatalogue.rowTitles].
  static List<String> rowTitles() => [for (final r in _rows) r.$1];

  static const _rows = [
    // What's out right now leads (and feeds the hero banner, which Home
    // repeats as a row); discovery rows follow, Trending first among them.
    ('Now playing', '/movie/now_playing'),
    // The series half of "what's out right now" — /movie/now_playing has no
    // /tv twin, and on_the_air is the closest param-free endpoint: shows with
    // an episode airing this week.
    ('Airing now', '/tv/on_the_air'),
    ('Trending', '/trending/all/week'),
    ('Popular movies', '/movie/popular'),
    ('Popular series', '/tv/popular'),
    ('Top rated', '/movie/top_rated'),
    ('Upcoming', '/movie/upcoming'),
  ];

  /// All rows fired concurrently — TMDB has no aliased multi-query like
  /// AniList, so this is the closest equivalent to one round-trip: the user
  /// waits for the slowest row, not the sum of all of them. `Future.wait`
  /// keeps the results in the same order as [_rows] regardless of which
  /// finishes first.
  @override
  Future<List<HomeSection>> home() async {
    final sections = await Future.wait(_rows.map(_fetchRow));
    return [for (final s in sections) ?s];
  }

  Future<HomeSection?> _fetchRow((String, String) row) async {
    final (title, path) = row;
    // List endpoints under /movie/* and /tv/* don't carry a `media_type`
    // field, so the endpoint itself says what it holds. Mixed endpoints
    // (/trending/all, /search/multi) do carry it, so let _items read it.
    final forcedTv = path.startsWith('/tv/')
        ? true
        : path.startsWith('/movie/')
        ? false
        : null;
    final items = _items(await _get(path, const {}), forcedTv: forcedTv);
    return items.isEmpty
        ? null
        // The endpoint path is the row's identity, and every TMDB list
        // endpoint takes ?page=, so paging is the same call one page along.
        : HomeSection(
            title: title,
            items: items,
            more: BrowseMore(
              sourceId: ZmodeIds.sourceId,
              kind: 'zm_video',
              categoryId: path,
            ),
          );
  }

  @override
  Future<List<MediaItem>> browseRow(String rowId, int page) async {
    if (rowId.startsWith(wpPrefix)) {
      final id = int.tryParse(rowId.substring(wpPrefix.length));
      // No id means nothing to query — return empty rather than asking TMDB
      // for provider "abc" and getting an unrelated unfiltered page back.
      return id == null ? const [] : _discoverProvider(id, page);
    }
    final forcedTv = rowId.startsWith('/tv/')
        ? true
        : rowId.startsWith('/movie/')
        ? false
        : null;
    try {
      return _items(await _get(rowId, {'page': page}), forcedTv: forcedTv);
    } catch (_) {
      return const [];
    }
  }

  /// Row-id prefix for a streaming-service row. A service row is an ordinary
  /// paginable home row; only its id shape is new, so [BrowseMore], the
  /// "See all" grid and the Home-rows editor need no changes.
  static const String wpPrefix = 'wp:';

  static String wpRowId(int providerId) => '$wpPrefix$providerId';

  /// Row-id prefix for a Movies & TV sub-menu discover row: `disc:<region>:<i>`.
  /// The index resolves back to the region's fixed [MovieRow] so the "See all"
  /// grid pages the exact discover query Home showed.
  static const String discPrefix = 'disc:';

  static String discRowId(MovieRegion region, int index) =>
      '$discPrefix${region.name}:$index';

  /// Home rows for a Movies & TV sub-menu cut. [MovieRegion.all] returns null —
  /// the caller keeps the plain [home] rows for it — so a caller can write
  /// `await catalogue.homeForRegion(r) ?? catalogue.home()`.
  Future<List<HomeSection>?> homeForRegion(MovieRegion region) async {
    final rows = region.rows;
    if (rows == null || rows.isEmpty) return null;
    final sections = await Future.wait([
      for (var i = 0; i < rows.length; i++) _fetchDiscoverRow(region, i, rows[i]),
    ]);
    return [for (final s in sections) ?s];
  }

  Future<HomeSection?> _fetchDiscoverRow(
    MovieRegion region,
    int index,
    MovieRow row,
  ) async {
    // Discover endpoints are film-only, so `forcedTv: false` and no page param
    // (page 1 is the home row; paging lives in [browseDiscoverRow]).
    final items = _items(
      await _get(row.path, Map<String, dynamic>.from(row.params)),
      forcedTv: false,
    );
    if (items.isEmpty) return null;
    return HomeSection(
      title: row.title,
      items: items,
      more: BrowseMore(
        sourceId: ZmodeIds.sourceId,
        kind: 'zm_video',
        categoryId: discRowId(region, index),
      ),
    );
  }

  /// Next page of one sub-menu discover row (see [discRowId]).
  Future<List<MediaItem>> browseDiscoverRow(String rowId, int page) async {
    final parts = rowId.split(':');
    if (parts.length != 3 || parts[0] != 'disc') return const [];
    final region = MovieRegion.values
        .where((r) => r.name == parts[1])
        .firstOrNull;
    final index = int.tryParse(parts[2]);
    final rows = region?.rows;
    if (rows == null || index == null || index < 0 || index >= rows.length) {
      return const [];
    }
    final row = rows[index];
    return _items(
      await _get(row.path, {...row.params, 'page': page}),
      forcedTv: false,
    );
  }

  /// Browse one service while preserving TMDB's server-side filters.
  Future<MediaItemPage> browseProvider(
    int providerId,
    int page, {
    MetaFilters filters = const MetaFilters(),
  }) async {
    final region = StreamingPrefs.region;
    final onlyTv = filters.format == MetaFormat.tv;
    final onlyMovie = filters.format == MetaFormat.movie;
    final both = await Future.wait([
      if (!onlyMovie)
        _discoverProviderFiltered(
          providerId,
          page,
          filters,
          region: region,
          isTv: true,
        ),
      if (!onlyTv)
        _discoverProviderFiltered(
          providerId,
          page,
          filters,
          region: region,
          isTv: false,
        ),
    ]);
    if (both.length == 1) return both.single;
    return MediaItemPage(
      items: _interleave(both[0].items, both[1].items),
      hasMore: both.any((page) => page.hasMore),
    );
  }

  Future<MediaItemPage> _discoverProviderFiltered(
    int providerId,
    int page,
    MetaFilters filters, {
    required String region,
    required bool isTv,
  }) async {
    if (filters.genres.any((genre) => tmdbGenreId(genre, isTv: isTv) == null)) {
      return const MediaItemPage(items: [], hasMore: false);
    }
    final ids = filters.genres
        .map((genre) => tmdbGenreId(genre, isTv: isTv))
        .whereType<int>()
        .toSet();
    final params = <String, dynamic>{
      'page': page,
      'include_adult': filters.adult,
      'with_watch_providers': '$providerId',
      'watch_region': region,
      'sort_by': _sortValue(filters.sort, isTv: isTv),
      if (ids.isNotEmpty) 'with_genres': ids.join(','),
      if (filters.year != null)
        (isTv ? 'first_air_date_year' : 'primary_release_year'): filters.year,
      if (filters.sort == MetaSort.score || filters.minScore != null)
        'vote_count.gte': 200,
      if (filters.minScore != null) 'vote_average.gte': filters.minScore! / 10,
    };
    return _safePage(
      () => _get('/discover/${isTv ? 'tv' : 'movie'}', params),
      forcedTv: isTv,
      page: page,
    );
  }

  Future<MediaItemPage> _safePage(
    Future<Map<String, dynamic>?> Function() call, {
    required bool forcedTv,
    required int page,
  }) async {
    try {
      final response = await call();
      final totalPages = response?['total_pages'];
      return MediaItemPage(
        items: _items(response, forcedTv: forcedTv),
        hasMore: totalPages is num && page < totalPages,
      );
    } catch (_) {
      return const MediaItemPage(items: [], hasMore: false);
    }
  }

  /// Search TMDB titles, then keep only ones TMDB lists for [providerId] in
  /// the user's region. TMDB separates text search from provider availability,
  /// so the availability lookup is on-demand and cached per title.
  Future<MediaItemPage> searchProvider(
    int providerId,
    String query, {
    MetaFilters filters = const MetaFilters(),
    int page = 1,
  }) async {
    if (query.trim().isEmpty) {
      return browseProvider(providerId, page, filters: filters);
    }
    final region = StreamingPrefs.region;
    final response = await _get('/search/multi', {
      'query': query.trim(),
      'page': page,
      'include_adult': filters.adult,
    });
    final rawResults = response?['results'];
    if (rawResults is! List) {
      return const MediaItemPage(items: [], hasMore: false);
    }
    final candidates = rawResults
        .whereType<Map>()
        .map(Map<String, dynamic>.from)
        .where((item) => _matchesProviderSearchFilters(item, filters))
        .toList();
    candidates.sort((a, b) => _compareSearchResults(a, b, filters.sort));

    final found = <MediaItem>[];
    // Keep the burst modest: one query yields up to 20 results, but availability
    // is still checked only for this explicit search, never during Home load.
    for (var start = 0; start < candidates.length; start += 4) {
      final end = (start + 4).clamp(0, candidates.length);
      final batch = candidates.sublist(start, end);
      final availability = await Future.wait(
        batch.map((item) => _hasProvider(providerId, item, region)),
      );
      for (var i = 0; i < batch.length; i++) {
        if (availability[i]) {
          found.addAll(
            _items({
              'results': [batch[i]],
            }, forcedTv: null),
          );
        }
      }
    }
    final totalPages = response?['total_pages'];
    return MediaItemPage(
      items: found,
      hasMore: totalPages is num && page < totalPages,
    );
  }

  Future<bool> _hasProvider(
    int providerId,
    Map<String, dynamic> item,
    String region,
  ) async {
    final mediaType = item['media_type'];
    final id = item['id'];
    if ((mediaType != 'movie' && mediaType != 'tv') || id is! int) {
      return false;
    }
    final key = '$mediaType:$id';
    var byRegion = _watchProviderCache[key];
    if (byRegion == null) {
      final response = await _get('/$mediaType/$id/watch/providers', const {});
      final regions = response?['results'];
      if (regions is! Map) return false;
      byRegion = {
        for (final entry in regions.entries)
          if (entry.value is Map)
            entry.key.toString(): {
              for (final section in (entry.value as Map).values)
                if (section is List)
                  for (final provider in section.whereType<Map>())
                    if (provider['provider_id'] is int)
                      provider['provider_id'] as int,
            },
      };
      // ponytail: retain only the last 256 title lookups; enough for repeated
      // searches in one session without an unbounded process-lifetime cache.
      if (_watchProviderCache.length >= 256) {
        _watchProviderCache.remove(_watchProviderCache.keys.first);
      }
      _watchProviderCache[key] = byRegion;
    }
    return byRegion[region]?.contains(providerId) ?? false;
  }

  static bool _matchesProviderSearchFilters(
    Map<String, dynamic> item,
    MetaFilters filters,
  ) {
    final mediaType = item['media_type'];
    final isTv = mediaType == 'tv';
    if (mediaType != 'movie' && !isTv) return false;
    if (filters.format == MetaFormat.tv && !isTv) return false;
    if (filters.format == MetaFormat.movie && isTv) return false;
    if (filters.minScore != null) {
      final score = (item['vote_average'] as num?)?.toDouble() ?? 0;
      final votes = (item['vote_count'] as num?)?.toInt() ?? 0;
      if (score < filters.minScore! / 10 || votes < 200) return false;
    }
    if (filters.year != null) {
      final date = isTv ? item['first_air_date'] : item['release_date'];
      if (date is! String || !date.startsWith('${filters.year}-')) return false;
    }
    if (filters.genres.isNotEmpty) {
      final rawGenres = item['genre_ids'];
      if (rawGenres is! List) return false;
      final genreIds = rawGenres.whereType<int>().toSet();
      final wanted = filters.genres
          .map((genre) => tmdbGenreId(genre, isTv: isTv))
          .toList();
      if (wanted.any((id) => id == null || !genreIds.contains(id))) {
        return false;
      }
    }
    return true;
  }

  static int _compareSearchResults(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    MetaSort sort,
  ) {
    final compare = switch (sort) {
      MetaSort.title =>
        ((a['name'] ?? a['title']) as String? ?? '').toLowerCase().compareTo(
          ((b['name'] ?? b['title']) as String? ?? '').toLowerCase(),
        ),
      MetaSort.newest => _dateValue(b).compareTo(_dateValue(a)),
      MetaSort.score =>
        ((b['vote_average'] as num?)?.toDouble() ?? 0).compareTo(
          (a['vote_average'] as num?)?.toDouble() ?? 0,
        ),
      _ => ((b['popularity'] as num?)?.toDouble() ?? 0).compareTo(
        (a['popularity'] as num?)?.toDouble() ?? 0,
      ),
    };
    return compare;
  }

  static int _dateValue(Map<String, dynamic> item) =>
      DateTime.tryParse(
        (item['first_air_date'] ?? item['release_date']) as String? ?? '',
      )?.millisecondsSinceEpoch ??
      0;

  static String _sortValue(MetaSort sort, {required bool isTv}) =>
      switch (sort) {
        MetaSort.score => 'vote_average.desc',
        MetaSort.newest =>
          isTv ? 'first_air_date.desc' : 'primary_release_date.desc',
        MetaSort.title => isTv ? 'name.asc' : 'title.asc',
        _ => 'popularity.desc',
      };

  /// One page of what [providerId] carries in the user's region.
  ///
  /// Films and series are separate endpoints on TMDB, and a service's shelf is
  /// both, so this asks for the same page of each and interleaves them. Two
  /// calls per page is the cost of a mixed grid; it is why pins are capped.
  Future<List<MediaItem>> _discoverProvider(int providerId, int page) async {
    final params = <String, dynamic>{
      'with_watch_providers': '$providerId',
      'watch_region': StreamingPrefs.region,
      'sort_by': 'popularity.desc',
      'page': page,
    };
    // Each side is caught on its own: one endpoint failing must not lose the
    // other's results, which is what a single try around Future.wait would do.
    final both = await Future.wait([
      _safe(() => _get('/discover/tv', params), forcedTv: true),
      _safe(() => _get('/discover/movie', params), forcedTv: false),
    ]);
    return _interleave(both[0], both[1]);
  }

  Future<List<MediaItem>> _safe(
    Future<Map<String, dynamic>?> Function() call, {
    required bool forcedTv,
  }) async {
    try {
      return _items(await call(), forcedTv: forcedTv);
    } catch (_) {
      return const [];
    }
  }

  /// Alternate a, b, a, b… then append whatever is left of the longer list.
  static List<MediaItem> _interleave(List<MediaItem> a, List<MediaItem> b) {
    final out = <MediaItem>[];
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (i < a.length) out.add(a[i]);
      if (i < b.length) out.add(b[i]);
    }
    return out;
  }

  @override
  Future<List<MediaItem>> search(String q) async =>
      _items(await _get('/search/multi', {'query': q}), forcedTv: null);

  @override
  bool get supportsFilters => true;

  /// Filtering lives on `/discover`, which takes no query, while `/search`
  /// takes a query and no filters — TMDB genuinely has no endpoint that does
  /// both. So a filtered search runs /discover and narrows by title locally;
  /// a filtered browse (no query) is just /discover.
  @override
  Future<List<MediaItem>> searchFiltered(
    String q, {
    MetaFilters? filters,
    int page = 1,
  }) async {
    final f = filters ?? const MetaFilters();
    // Adult alone stays on /search: both endpoints take include_adult, but
    // only /search takes the query.
    //
    // It also REQUIRES one. Asked with an empty string it answers with
    // nothing, so a filters-only browse — sort by Popular and nothing else,
    // which `narrowsCatalogue` counts as no filter at all — used to land here
    // and come back empty. No query means browse, and browsing is /discover's
    // job whatever the filters say.
    if (q.trim().isNotEmpty && !f.narrowsCatalogue) {
      return _items(
        await _get('/search/multi', {
          'query': q,
          'page': page,
          'include_adult': f.adult,
        }),
        forcedTv: null,
      );
    }
    // One side at a time: /discover is per-media-type, and a TV request with a
    // movie-only genre id returns nothing rather than an error.
    final isTv = f.format == MetaFormat.tv;
    final ids = f.genres
        .map((g) => tmdbGenreId(g, isTv: isTv))
        .whereType<int>()
        .toSet();
    final params = <String, dynamic>{
      'page': page,
      'include_adult': f.adult,
      'sort_by': switch (f.sort) {
        MetaSort.score => 'vote_average.desc',
        MetaSort.newest =>
          isTv ? 'first_air_date.desc' : 'primary_release_date.desc',
        MetaSort.title => 'title.asc',
        _ => 'popularity.desc',
      },
      if (ids.isNotEmpty) 'with_genres': ids.join(','),
      if (f.year != null)
        (isTv ? 'first_air_date_year' : 'primary_release_year'): f.year,
      // Sorting by score with no vote floor surfaces titles with one 10/10
      // vote, which reads as broken rather than as a top-rated list.
      if (f.sort == MetaSort.score || f.minScore != null) 'vote_count.gte': 200,
      if (f.minScore != null) 'vote_average.gte': f.minScore! / 10,
    };
    final items = _items(
      await _get('/discover/${isTv ? 'tv' : 'movie'}', params),
      forcedTv: isTv,
    );
    final needle = q.trim().toLowerCase();
    if (needle.isEmpty) return items;
    return items
        .where((i) => i.title.toLowerCase().contains(needle))
        .toList(growable: false);
  }

  @override
  Future<MediaDetail> detail(ZCanonical c) async {
    final isTv = c.kind == ZKind.tv;
    final id = c.id.split(':').last;
    final m = await _get(isTv ? '/tv/$id' : '/movie/$id', const {});
    if (m == null) throw StateError('TMDB returned nothing for $c');
    final date = (isTv ? m['first_air_date'] : m['release_date']) as String?;
    return MediaDetail(
      id: c.id,
      title: (isTv ? m['name'] : m['title']) as String? ?? '',
      cover: _poster(m['poster_path'] as String?),
      banner: _backdrop(m['backdrop_path'] as String?),
      url: ZmodeIds.showUrl(c),
      description: m['overview'] as String?,
      status: switch (m['status'] as String?) {
        'Returning Series' => MediaStatus.ongoing,
        'Ended' || 'Released' => MediaStatus.completed,
        'Canceled' => MediaStatus.cancelled,
        _ => MediaStatus.unknown,
      },
      genres: [
        for (final g in (m['genres'] as List? ?? const []))
          if (g is Map && g['name'] is String) g['name'] as String,
      ],
      episodes: isTv
          ? _tvEpisodes(m, c)
          : [
              Episode(
                id: '1',
                title: (m['title'] as String?) ?? 'Movie',
                number: 1,
                url: ZmodeIds.episodeUrl(c, 1),
              ),
            ],
      year: date != null && date.length >= 4 ? date.substring(0, 4) : null,
      type: ProviderType.movie,
      sourceId: ZmodeIds.sourceId,
      tmdbId: int.tryParse(id),
      // Out of 10 in the payload, out of 100 in the model.
      score: _score(m['vote_average']),
      // vote_count, not `popularity`: TMDB's popularity is an internal
      // trending float (55.6) that means nothing printed on a page.
      popularity: (m['vote_count'] as num?)?.toInt(),
      // A series reports per-episode run times as a list; a film reports one
      // number. Both end up as minutes.
      durationMins: _runtime(isTv ? m['episode_run_time'] : m['runtime']),
      country: _country(m['production_countries']),
      startDate: _isoDate(date),
      endDate: _isoDate(m['last_air_date'] as String?),
      nativeTitle: (isTv ? m['original_name'] : m['original_title']) as String?,
      isAdult: m['adult'] == true,
      tmdbIsTv: isTv,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  static int? _score(Object? v) {
    final d = (v as num?)?.toDouble();
    return d == null || d <= 0 ? null : (d * 10).round();
  }

  static int? _runtime(Object? v) {
    if (v is num && v > 0) return v.toInt();
    // episode_run_time is a list, often with more than one entry when a show
    // changed length. The first is the usual one.
    if (v is List && v.isNotEmpty && v.first is num && (v.first as num) > 0) {
      return (v.first as num).toInt();
    }
    return null;
  }

  static String? _country(Object? v) {
    if (v is! List || v.isEmpty) return null;
    final first = v.first;
    return (first is Map) ? first['iso_3166_1'] as String? : null;
  }

  /// A malformed date is worth dropping a row over, never a detail page.
  static DateTime? _isoDate(String? raw) =>
      (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);

  static String? _poster(String? path) =>
      path == null ? null : '${Tmdb.img}/w500$path';

  /// Wide 16:9 art for the hero — TMDB's `backdrop_path`.
  static String? _backdrop(String? path) =>
      path == null ? null : '${Tmdb.img}/w780$path';

  /// [forcedTv]: list endpoints don't carry `media_type`, so the caller says
  /// (see [home]); null means read `media_type` off each result and skip
  /// anything that's neither `movie` nor `tv` (e.g. `person` from search).
  static List<MediaItem> _items(
    Map<String, dynamic>? data, {
    required bool? forcedTv,
  }) {
    final results = data?['results'];
    if (results is! List) return const [];
    final out = <MediaItem>[];
    for (final r in results) {
      if (r is! Map) continue;
      final m = Map<String, dynamic>.from(r);
      final mediaType = m['media_type'];
      if (forcedTv == null && mediaType != 'tv' && mediaType != 'movie') {
        continue;
      }
      final isTv = forcedTv ?? (mediaType == 'tv');
      final id = m['id'];
      if (id is! int) continue;
      final c = ZCanonical(isTv ? ZKind.tv : ZKind.movie, 'tmdb:$id');
      out.add(
        MediaItem(
          id: c.id,
          title: ((isTv ? m['name'] : m['title']) as String?) ?? '',
          cover: _poster(m['poster_path'] as String?),
          banner: _backdrop(m['backdrop_path'] as String?),
          url: ZmodeIds.showUrl(c),
          type: ProviderType.movie,
          sourceId: ZmodeIds.sourceId,
          tmdbId: id,
          tmdbIsTv: isTv,
          // List responses carry genre_ids, not genre objects. Mapping them
          // here is what lets anything downstream key on genres at all.
          genres: tmdbGenreNames(
            (m['genre_ids'] as List?) ?? const [],
            isTv: isTv,
          ),
          score: _score(m['vote_average']),
          isAdult: m['adult'] == true,
        ),
      );
    }
    return out;
  }

  /// Seasons 1..n in order, episodes numbered continuously across them, so
  /// "episode 11" of a 10-episode-season show is S2E1. Specials (season 0)
  /// are skipped.
  static List<Episode> _tvEpisodes(Map<String, dynamic> m, ZCanonical c) {
    final seasons =
        (m['seasons'] as List? ?? const [])
            .whereType<Map>()
            .where((s) => (s['season_number'] as int? ?? 0) > 0)
            .toList()
          ..sort(
            (a, b) => (a['season_number'] as int).compareTo(
              b['season_number'] as int,
            ),
          );
    final out = <Episode>[];
    var n = 0;
    for (final s in seasons) {
      final count = s['episode_count'] as int? ?? 0;
      final season = s['season_number'] as int;
      for (var i = 1; i <= count; i++) {
        n++;
        out.add(
          Episode(
            id: '$n',
            title: 'S$season · E$i',
            number: n.toDouble(),
            url: ZmodeIds.episodeUrl(c, n),
            season: season,
          ),
        );
      }
    }
    return out;
  }
}
