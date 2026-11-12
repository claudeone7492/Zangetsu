import 'dart:convert';

import 'zmode_ids.dart';

/// Filters for a metadata-provider search or browse.
///
/// Only AniList (anime/manga) and TMDB (movies/TV) apply these. MAL and Simkl
/// accept the parameters and return unfiltered results — verified against both
/// APIs — so the UI must not offer filters while one of those is the active
/// provider rather than showing results that only look filtered.
class MetaFilters {
  const MetaFilters({
    this.genres = const [],
    this.genreMatch = MetaGenreMatch.any,
    this.tags = const [],
    this.yearFrom,
    this.yearTo,
    this.season,
    this.format,
    this.status,
    this.sort = MetaSort.popularity,
    this.minScore,
    this.adult = false,
    this.minVotes,
    this.runtimeMin,
    this.runtimeMax,
    this.originCountry,
    this.originalLanguage,
    this.excludedGenres = const [],
    this.excludeOriginalLanguages,
    this.certifications = const [],
    this.certificationCountry,
    this.watchProviders = const [],
    this.watchRegion,
    this.tvNetworks = const [],
    this.tvStatuses = const [],
    this.tvTypes = const [],
  });

  /// Genre names as the provider spells them, e.g. `Action`. Translated to
  /// TMDB's numeric ids on the way out; AniList takes the names directly.
  final List<String> genres;

  /// Whether a title must carry ALL of [genres] or just one of them. TMDB
  /// joins with `,` for all and `|` for any; AniList has no equivalent and
  /// always matches any.
  final MetaGenreMatch genreMatch;

  /// AniList tags — finer than a genre ("Time Skip" against "Action"), and
  /// AniList's alone. Nothing else exposes them, so a tag chip is only
  /// offered while AniList is the one answering.
  final List<String> tags;

  /// Inclusive release/air year range. A single year is [yearFrom] == [yearTo].
  /// AniList has only a single `seasonYear`, so it reads [yearFrom].
  final int? yearFrom;
  final int? yearTo;
  final MetaSeason? season;
  final MetaFormat? format;
  final MetaStatus? status;
  final MetaSort sort;

  /// 0-100. AniList compares on `averageScore`; TMDB on `vote_average`, which
  /// is out of 10, so it is divided on the way out.
  final int? minScore;

  /// Include adult (18+) titles. Only reachable when the Privacy switch is on,
  /// and re-checked there before any request — see [PlaybackPrefs.adultMetadata].
  final bool adult;

  /// Minimum TMDB `vote_count`. Replaces the hidden vote floor the rating sort
  /// and [minScore] would otherwise apply.
  final int? minVotes;

  /// Minutes; episode length for TV. TMDB `/discover` only.
  final int? runtimeMin;
  final int? runtimeMax;

  /// ISO 3166-1 code(s), `|`-joined, e.g. `NG` or `US|GB`. TMDB `with_origin_country`.
  final String? originCountry;

  /// ISO 639-1 code(s), `|`-joined, e.g. `en` or `en|yo`. TMDB
  /// `with_original_language`. Search results check it locally.
  final String? originalLanguage;

  /// Genres to drop. TMDB `without_genres`, joined with `,` (TMDB only honours
  /// the "all" separator for exclusions).
  final List<String> excludedGenres;

  /// ISO 639-1 codes to drop, `|`-joined. TMDB has no query parameter for this
  /// (`without_original_language` is silently ignored), so it is applied to
  /// each returned page instead.
  final String? excludeOriginalLanguages;

  /// Movies only; codes of [certificationCountry] (e.g. "PG-13" for "US").
  final List<String> certifications;
  final String? certificationCountry;

  /// TMDB provider ids, available in [watchRegion].
  final List<int> watchProviders;
  final String? watchRegion;

  /// TV only; TMDB network ids.
  final List<int> tvNetworks;
  final List<int> tvStatuses;
  final List<int> tvTypes;

  /// The single year AniList can express, kept as a convenience for callers
  /// that only ever set one.
  int? get year => yearFrom;

  /// Whether a year range is set at all.
  bool get hasYear => yearFrom != null || yearTo != null;

  /// Whether anything here would actually narrow a request. A search with
  /// nothing set must take the plain path, so an untouched sheet does not turn
  /// a search into a filtered browse.
  bool get isEmpty =>
      genres.isEmpty &&
      tags.isEmpty &&
      !hasYear &&
      season == null &&
      format == null &&
      status == null &&
      minScore == null &&
      !adult &&
      minVotes == null &&
      runtimeMin == null &&
      runtimeMax == null &&
      originCountry == null &&
      originalLanguage == null &&
      excludedGenres.isEmpty &&
      excludeOriginalLanguages == null &&
      certifications.isEmpty &&
      watchProviders.isEmpty &&
      tvNetworks.isEmpty &&
      tvStatuses.isEmpty &&
      tvTypes.isEmpty &&
      sort == MetaSort.popularity;

  bool get isNotEmpty => !isEmpty;

  /// Whether anything here narrows the CATALOGUE, ignoring [adult].
  ///
  /// Adult is a visibility flag, not a query. TMDB serves filters from
  /// /discover, which takes no query at all, so counting "NSFW on" as a filter
  /// sent a plain text search down the discover path — where the query is
  /// dropped and the title match is done locally against popular titles, which
  /// finds almost nothing.
  bool get narrowsCatalogue =>
      genres.isNotEmpty ||
      tags.isNotEmpty ||
      hasYear ||
      season != null ||
      format != null ||
      status != null ||
      minScore != null ||
      minVotes != null ||
      runtimeMin != null ||
      runtimeMax != null ||
      originCountry != null ||
      originalLanguage != null ||
      excludedGenres.isNotEmpty ||
      excludeOriginalLanguages != null ||
      certifications.isNotEmpty ||
      watchProviders.isNotEmpty ||
      tvNetworks.isNotEmpty ||
      tvStatuses.isNotEmpty ||
      tvTypes.isNotEmpty ||
      sort != MetaSort.popularity;

  MetaFilters copyWith({
    List<String>? genres,
    MetaGenreMatch? genreMatch,
    List<String>? tags,
    int? yearFrom,
    int? yearTo,
    MetaSeason? season,
    MetaFormat? format,
    MetaStatus? status,
    MetaSort? sort,
    int? minScore,
    bool? adult,
    int? minVotes,
    int? runtimeMin,
    int? runtimeMax,
    String? originCountry,
    String? originalLanguage,
    List<String>? excludedGenres,
    String? excludeOriginalLanguages,
    List<String>? certifications,
    String? certificationCountry,
    List<int>? watchProviders,
    String? watchRegion,
    List<int>? tvNetworks,
    List<int>? tvStatuses,
    List<int>? tvTypes,
    bool clearYear = false,
    bool clearSeason = false,
    bool clearFormat = false,
    bool clearStatus = false,
    bool clearScore = false,
    bool clearMinVotes = false,
    bool clearRuntime = false,
    bool clearCountry = false,
    bool clearLanguage = false,
    bool clearExcludedLanguages = false,
    bool clearCertifications = false,
    bool clearProviders = false,
    bool clearNetworks = false,
    bool clearTvStatuses = false,
    bool clearTvTypes = false,
  }) => MetaFilters(
    genres: genres ?? this.genres,
    genreMatch: genreMatch ?? this.genreMatch,
    tags: tags ?? this.tags,
    yearFrom: clearYear ? null : (yearFrom ?? this.yearFrom),
    yearTo: clearYear ? null : (yearTo ?? this.yearTo),
    season: clearSeason ? null : (season ?? this.season),
    format: clearFormat ? null : (format ?? this.format),
    status: clearStatus ? null : (status ?? this.status),
    sort: sort ?? this.sort,
    minScore: clearScore ? null : (minScore ?? this.minScore),
    adult: adult ?? this.adult,
    minVotes: clearMinVotes ? null : (minVotes ?? this.minVotes),
    runtimeMin: clearRuntime ? null : (runtimeMin ?? this.runtimeMin),
    runtimeMax: clearRuntime ? null : (runtimeMax ?? this.runtimeMax),
    originCountry: clearCountry ? null : (originCountry ?? this.originCountry),
    originalLanguage: clearLanguage
        ? null
        : (originalLanguage ?? this.originalLanguage),
    excludedGenres: excludedGenres ?? this.excludedGenres,
    excludeOriginalLanguages: clearExcludedLanguages
        ? null
        : (excludeOriginalLanguages ?? this.excludeOriginalLanguages),
    certifications: clearCertifications
        ? const []
        : (certifications ?? this.certifications),
    certificationCountry: clearCertifications
        ? null
        : (certificationCountry ?? this.certificationCountry),
    watchProviders: clearProviders
        ? const []
        : (watchProviders ?? this.watchProviders),
    watchRegion: clearProviders ? null : (watchRegion ?? this.watchRegion),
    tvNetworks: clearNetworks ? const [] : (tvNetworks ?? this.tvNetworks),
    tvStatuses: clearTvStatuses ? const [] : (tvStatuses ?? this.tvStatuses),
    tvTypes: clearTvTypes ? const [] : (tvTypes ?? this.tvTypes),
  );

  /// Encoded for [HomeSection]-style plumbing: the search bloc already carries
  /// an opaque per-source filter string, so riding that instead of adding a
  /// parallel channel keeps one path for "filters were applied".
  String toJson() => jsonEncode({
    if (genres.isNotEmpty) 'g': genres,
    if (tags.isNotEmpty) 't': tags,
    if (yearFrom != null) 'y': yearFrom,
    if (yearTo != null) 'yt': yearTo,
    if (season != null) 's': season!.name,
    if (format != null) 'f': format!.name,
    if (status != null) 'st': status!.name,
    if (minScore != null) 'ms': minScore,
    if (adult) 'a': true,
    if (minVotes != null) 'mv': minVotes,
    if (runtimeMin != null) 'r1': runtimeMin,
    if (runtimeMax != null) 'r2': runtimeMax,
    if (originCountry != null) 'oc': originCountry,
    if (originalLanguage != null) 'ol': originalLanguage,
    if (genreMatch != MetaGenreMatch.any) 'gm': genreMatch.name,
    if (excludedGenres.isNotEmpty) 'xg': excludedGenres,
    if (excludeOriginalLanguages != null) 'xl': excludeOriginalLanguages,
    if (certifications.isNotEmpty) 'ce': certifications,
    if (certificationCountry != null) 'cc': certificationCountry,
    if (watchProviders.isNotEmpty) 'wp': watchProviders,
    if (watchRegion != null) 'wr': watchRegion,
    if (tvNetworks.isNotEmpty) 'tn': tvNetworks,
    if (tvStatuses.isNotEmpty) 'ts': tvStatuses,
    if (tvTypes.isNotEmpty) 'tt': tvTypes,
    'so': sort.name,
  });

  static MetaFilters? fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      T? pick<T extends Enum>(List<T> values, String? name) =>
          name == null ? null : values.where((v) => v.name == name).firstOrNull;
      List<int> ints(Object? v) => [
        ...?(v as List?)?.map((e) => e is int ? e : int.tryParse('$e')),
      ].whereType<int>().toList();
      return MetaFilters(
        genres: [...?(m['g'] as List?)?.cast<String>()],
        tags: [...?(m['t'] as List?)?.cast<String>()],
        yearFrom: m['y'] as int?,
        yearTo: m['yt'] as int?,
        season: pick(MetaSeason.values, m['s'] as String?),
        format: pick(MetaFormat.values, m['f'] as String?),
        status: pick(MetaStatus.values, m['st'] as String?),
        minScore: m['ms'] as int?,
        adult: m['a'] == true,
        minVotes: m['mv'] as int?,
        runtimeMin: m['r1'] as int?,
        runtimeMax: m['r2'] as int?,
        originCountry: m['oc'] as String?,
        originalLanguage: m['ol'] as String?,
        genreMatch:
            pick(MetaGenreMatch.values, m['gm'] as String?) ??
            MetaGenreMatch.any,
        excludedGenres: [...?(m['xg'] as List?)?.cast<String>()],
        excludeOriginalLanguages: m['xl'] as String?,
        certifications: [...?(m['ce'] as List?)?.cast<String>()],
        certificationCountry: m['cc'] as String?,
        watchProviders: ints(m['wp']),
        watchRegion: m['wr'] as String?,
        tvNetworks: ints(m['tn']),
        tvStatuses: ints(m['ts']),
        tvTypes: ints(m['tt']),
        sort: pick(MetaSort.values, m['so'] as String?) ?? MetaSort.popularity,
      );
    } catch (_) {
      // A malformed string means an unfiltered search, never a crash.
      return null;
    }
  }
}

enum MetaSeason { winter, spring, summer, fall }

enum MetaFormat { tv, movie, ova, special, manga, novel, oneShot }

enum MetaStatus { releasing, finished, notYetReleased, cancelled }

enum MetaSort { popularity, score, trending, newest, oldest, title }

/// Whether a title must carry every selected genre or just one of them.
enum MetaGenreMatch { any, all }

/// The genres offered for [kind]. AniList's list is fixed and small, and the
/// TMDB ids below cover the same ground for movies and TV, so one picker
/// serves every provider that can filter.
/// AniList's adult genre. Kept out of [metaGenresFor] unless asked for: it is
/// a real genre on every anime/manga/novel query, but offering it while the
/// Privacy switch is off would show a tile that can only ever come back empty
/// (the catalogue sends `isAdult:false`, so nothing in it can match).
const String kAdultGenre = 'Hentai';

/// The genres offered for [kind], plus [kAdultGenre] when [adult] is on.
///
/// [adult] is the caller's read of `PlaybackPrefs.adultMetadata`; the
/// repository re-checks the same switch before any request, so passing true
/// here can widen what is OFFERED but never what is returned.
List<String> metaGenresFor(ZKind kind, {bool adult = false}) {
  final base = _metaGenresFor(kind);
  if (!adult || kind == ZKind.movie || kind == ZKind.tv) return base;
  // Inserted where it sorts, not appended. These lists are alphabetical, and
  // one entry stuck on the end reads as a bolted-on afterthought — you go
  // looking under H and it is at the bottom of the grid.
  final out = [...base];
  final at = out.indexWhere((g) => g.compareTo(kAdultGenre) > 0);
  out.insert(at < 0 ? out.length : at, kAdultGenre);
  return out;
}

List<String> _metaGenresFor(ZKind kind) => switch (kind) {
  ZKind.anime || ZKind.manga || ZKind.novel => const [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  ],
  ZKind.movie || ZKind.tv => const [
    'Action',
    'Adventure',
    'Animation',
    'Comedy',
    'Crime',
    'Documentary',
    'Drama',
    'Family',
    'Fantasy',
    'History',
    'Horror',
    'Music',
    'Mystery',
    'Romance',
    'Science Fiction',
    'Thriller',
    'War',
    'Western',
  ],
};

/// TMDB genre ids, which `/discover` takes instead of names. Movie and TV
/// share most ids; the ones that differ are handled by [tmdbGenreId].
const Map<String, int> _tmdbMovieGenres = {
  'Action': 28,
  'Adventure': 12,
  'Animation': 16,
  'Comedy': 35,
  'Crime': 80,
  'Documentary': 99,
  'Drama': 18,
  'Family': 10751,
  'Fantasy': 14,
  'History': 36,
  'Horror': 27,
  'Music': 10402,
  'Mystery': 9648,
  'Romance': 10749,
  'Science Fiction': 878,
  'Thriller': 53,
  'War': 10752,
  'Western': 37,
};

/// TV uses its own ids for the genres that exist at all on the TV side.
const Map<String, int> _tmdbTvGenres = {
  'Action': 10759,
  'Adventure': 10759,
  'Animation': 16,
  'Comedy': 35,
  'Crime': 80,
  'Documentary': 99,
  'Drama': 18,
  'Family': 10751,
  'Fantasy': 10765,
  'History': 36,
  'Mystery': 9648,
  'Science Fiction': 10765,
  'War': 10768,
  'Western': 37,
};

/// The genre names behind TMDB's `genre_ids`, which is all a list response
/// carries — full `genres` objects only come back on a detail fetch.
///
/// Without this every movie/TV item reached the app with no genres at all, so
/// anything keyed on them (the genre tiles' artwork) had nothing to match and
/// silently fell back. Ids that map to more than one name (TV folds Adventure
/// into Action, and Science Fiction into Fantasy) yield each of them; ids with
/// no entry are dropped rather than guessed.
List<String> tmdbGenreNames(List<dynamic> ids, {required bool isTv}) {
  final table = isTv ? _tmdbTvGenres : _tmdbMovieGenres;
  final out = <String>[];
  for (final raw in ids) {
    final id = raw is int ? raw : int.tryParse('$raw');
    if (id == null) continue;
    for (final e in table.entries) {
      if (e.value == id && !out.contains(e.key)) out.add(e.key);
    }
  }
  return out;
}

/// The TMDB id for [genre], or null when that genre has no equivalent on this
/// side (Horror and Thriller are movie-only, for instance) — a null must drop
/// the genre rather than send a wrong id.
int? tmdbGenreId(String genre, {required bool isTv}) =>
    (isTv ? _tmdbTvGenres : _tmdbMovieGenres)[genre];

/// `with_status` values of `/discover/tv`.
enum TmdbTvStatus {
  returning(0),
  planned(1),
  inProduction(2),
  ended(3),
  cancelled(4),
  pilot(5);

  const TmdbTvStatus(this.id);
  final int id;
}

/// `with_type` values of `/discover/tv`.
enum TmdbTvType {
  documentary(0),
  news(1),
  miniseries(2),
  reality(3),
  scripted(4),
  talkShow(5),
  video(6);

  const TmdbTvType(this.id);
  final int id;
}

/// A streaming service, as TMDB lists it for a watch region.
class TmdbWatchProvider {
  const TmdbWatchProvider({required this.id, required this.name, this.logoUrl});

  final int id;
  final String name;
  final String? logoUrl;
}

/// A certification code for a country, e.g. `PG-13` for `US`.
class TmdbCertification {
  const TmdbCertification({required this.code, required this.meaning});

  final String code;
  final String meaning;
}

/// Popular TV networks. TMDB has no list endpoint, so these are the ids TMDB
/// spells for the big ones (same table netflix-pro ships).
enum TmdbTvNetwork {
  netflix(213, 'Netflix'),
  primeVideo(1024, 'Prime Video'),
  disneyPlus(2739, 'Disney+'),
  hbo(49, 'HBO'),
  hboMax(3186, 'HBO Max'),
  appleTv(2552, 'Apple TV'),
  hulu(453, 'Hulu'),
  paramountPlus(4330, 'Paramount+'),
  peacock(3353, 'Peacock'),
  crunchyroll(1112, 'Crunchyroll'),
  bbcOne(4, 'BBC One'),
  amc(174, 'AMC'),
  fx(88, 'FX'),
  abc(2, 'ABC'),
  nbc(6, 'NBC'),
  cbs(16, 'CBS'),
  fox(19, 'FOX'),
  tvn(866, 'tvN'),
  jtbc(885, 'JTBC'),
  kbs2(342, 'KBS2'),
  mbc(97, 'MBC'),
  sbs(156, 'SBS');

  const TmdbTvNetwork(this.id, this.displayName);
  final int id;
  final String displayName;
}

/// Pipe-joins values the way TMDB's `with_*` params mean "any of".
String _anyOf(Iterable<Object> values) => values.join('|');

/// TMDB drops titles carrying any of `without_genres`, whichever separator is
/// used, so exclusions always join with the "all" separator.
String _allOf(Iterable<Object> values) => values.join(',');

/// Vote floors that keep a rating-sorted or rating-filtered list from being
/// topped by titles with a single 10/10 vote.
const int _ratingSortMovieVotes = 200;
const int _ratingSortTvVotes = 100;
const int _minRatingMovieVotes = 50;
const int _minRatingTvVotes = 20;

/// Builds the TMDB `/discover/{movie|tv}` query for these filters.
///
/// The single source of truth for the filter→TMDB mapping, so the search tab,
/// the service browse and any shelf all emit the same query for the same
/// filters. [page] is omitted when null (the caller may add it later).
///
/// [watchProviderOverride] pins a single service (the "browse this service"
/// path) and takes precedence over the [watchProviders] filter; [watchRegion]
/// overrides [MetaFilters.watchRegion] the same way.
///
/// [categoryGenreIds] are a shelf's own required genres (pipe-joined), kept
/// apart from [genres] so a shelf cannot be switched off from the genre row.
Map<String, dynamic> tmdbDiscoverParams(
  MetaFilters f, {
  required bool isTv,
  int? page,
  String? watchProviderOverride,
  String? watchRegion,
  String? categoryGenreIds,
}) {
  final params = <String, dynamic>{
    'include_adult': f.adult,
    'sort_by': _tmdbSortValue(f.sort, isTv: isTv),
  };
  if (page != null) params['page'] = page;

  final genreIds = <int>{
    ...f.genres.map((g) => tmdbGenreId(g, isTv: isTv)).whereType<int>(),
    ...?categoryGenreIds?.split('|').map(int.tryParse).whereType<int>(),
  };
  if (genreIds.isNotEmpty) {
    // A shelf's genres are always any-of, so a mixed list falls back to OR.
    final sep = categoryGenreIds != null
        ? '|'
        : (f.genreMatch == MetaGenreMatch.all ? ',' : '|');
    params['with_genres'] = genreIds.join(sep);
  }

  final dateFrom = isTv ? 'first_air_date.gte' : 'primary_release_date.gte';
  final dateTo = isTv ? 'first_air_date.lte' : 'primary_release_date.lte';
  if (f.yearFrom != null) {
    params[dateFrom] = '${f.yearFrom}-01-01';
  }
  if (f.yearTo != null) {
    params[dateTo] = '${f.yearTo}-12-31';
  } else if (f.sort == MetaSort.newest) {
    // Newest-first would otherwise start with announced titles years away.
    final now = DateTime.now();
    params[dateTo] =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  if (f.minScore != null) params['vote_average.gte'] = f.minScore! / 10;
  // Without a vote floor, titles with a single 10/10 vote rank first.
  final voteFloor =
      f.minVotes ??
      switch (f.sort) {
        MetaSort.score => isTv ? _ratingSortTvVotes : _ratingSortMovieVotes,
        _ =>
          f.minScore != null
              ? (isTv ? _minRatingTvVotes : _minRatingMovieVotes)
              : null,
      };
  if (voteFloor != null) params['vote_count.gte'] = voteFloor;

  if (f.runtimeMin != null) params['with_runtime.gte'] = f.runtimeMin;
  if (f.runtimeMax != null) params['with_runtime.lte'] = f.runtimeMax;
  if (f.originCountry != null) params['with_origin_country'] = f.originCountry;
  if (f.originalLanguage != null) {
    params['with_original_language'] = f.originalLanguage;
  }

  final excludedIds = f.excludedGenres
      .map((g) => tmdbGenreId(g, isTv: isTv))
      .whereType<int>()
      .toSet();
  if (excludedIds.isNotEmpty) {
    params['without_genres'] = _allOf(excludedIds);
  }

  final provider = watchProviderOverride;
  final providers = provider != null
      ? <String>[provider]
      : f.watchProviders.map((e) => '$e');
  final region = watchRegion ?? f.watchRegion;
  if (providers.isNotEmpty && region != null) {
    params['with_watch_providers'] = _anyOf(providers);
    params['watch_region'] = region;
  }

  if (isTv) {
    if (f.tvNetworks.isNotEmpty) params['with_networks'] = _anyOf(f.tvNetworks);
    if (f.tvStatuses.isNotEmpty) params['with_status'] = _anyOf(f.tvStatuses);
    if (f.tvTypes.isNotEmpty) params['with_type'] = _anyOf(f.tvTypes);
  } else if (f.certifications.isNotEmpty && f.certificationCountry != null) {
    // Certifications are AND-joined, like without_genres: `|` is ignored and
    // returns the whole catalogue.
    params['certification'] = _allOf(f.certifications);
    params['certification_country'] = f.certificationCountry;
  }
  return params;
}

String _tmdbSortValue(MetaSort sort, {required bool isTv}) => switch (sort) {
  MetaSort.score => 'vote_average.desc',
  MetaSort.newest => isTv ? 'first_air_date.desc' : 'primary_release_date.desc',
  MetaSort.oldest => isTv ? 'first_air_date.asc' : 'primary_release_date.asc',
  MetaSort.title => isTv ? 'name.asc' : 'title.asc',
  _ => 'popularity.desc',
};

/// The year `/search/movie` and `/search/tv` can filter by themselves: only a
/// range of one year maps to their single `year` parameter.
int? tmdbSearchYear(MetaFilters f) =>
    f.yearFrom != null && f.yearFrom == f.yearTo ? f.yearFrom : null;

/// Whether a TMDB search result survives the filters `/search` cannot apply.
///
/// `/search/{movie,tv}` takes only the query, one year and `include_adult`, so
/// the rest — genres, rating, vote floor, language exclusions — are checked
/// here against the returned fields. Runtime and origin country are not in a
/// list response, so they cannot be enforced on a text search; they only ever
/// narrow a discover browse.
bool tmdbItemMatchesFilters(
  MetaFilters f, {
  required bool isTv,
  required List<int> genreIds,
  required int? year,
  required double voteAverage,
  required int voteCount,
  required String? language,
}) {
  final wanted = f.genres
      .map((g) => tmdbGenreId(g, isTv: isTv))
      .whereType<int>()
      .toSet();
  if (wanted.isNotEmpty) {
    final ok = f.genreMatch == MetaGenreMatch.all
        ? genreIds.toSet().containsAll(wanted)
        : genreIds.any(wanted.contains);
    if (!ok) return false;
  }
  final excluded = f.excludedGenres
      .map((g) => tmdbGenreId(g, isTv: isTv))
      .whereType<int>()
      .toSet();
  if (genreIds.any(excluded.contains)) return false;
  if (f.yearFrom != null && (year == null || year < f.yearFrom!)) return false;
  if (f.yearTo != null && (year == null || year > f.yearTo!)) return false;
  if (f.minScore != null && voteAverage < f.minScore! / 10) return false;
  if (f.minVotes != null && voteCount < f.minVotes!) return false;
  final wantedLangs = f.originalLanguage?.split('|') ?? const [];
  if (wantedLangs.isNotEmpty &&
      (language == null || !wantedLangs.contains(language))) {
    return false;
  }
  final droppedLangs = f.excludeOriginalLanguages?.split('|') ?? const [];
  if (droppedLangs.isNotEmpty &&
      language != null &&
      droppedLangs.contains(language)) {
    return false;
  }
  return true;
}
