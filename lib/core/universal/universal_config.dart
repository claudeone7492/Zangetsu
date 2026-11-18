import 'dart:convert';

/// Parsed model of a **universal scraper config** — a JSON document that
/// describes how to read one site, so a new source can be added with no code.
///
/// Two modes, one schema:
///
///  * **HTML mode** — classic server-rendered sites. Each field is a CSS
///    selector; `element@attr` reads an attribute, a bare selector reads the
///    element's text. `{query}`, `{page}`, `{href}` and `{id}` are substituted
///    into URLs at runtime.
///  * **JSON-API mode** — React/Vue single-page apps whose HTML is an empty
///    `<div id="root">`. An `api` block points at the site's JSON endpoints
///    and names the response keys, so the scraper reads data instead of DOM.
///
/// The same file drives both: a config with an `api` block uses it; one
/// without falls back to the selector rules.
class UniversalConfig {
  const UniversalConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.lang = 'en',
    this.type = 'movie',
    this.logo,
    this.nsfw = false,
    this.homeUrl = '/',
    this.catalogs = const [],
    this.search,
    this.detail,
    this.episodes,
    this.streams,
    this.pages,
    this.chapter,
    this.api,
    this.headers = const {},
    this.raw = const {},
  });

  /// Stable source id (lowercase, no spaces). Becomes the `us:<id>` provider.
  final String id;
  final String name;
  final String baseUrl;
  final String lang;

  /// `movie`, `anime`, `manga` or `novel` — picks the app mode this source
  /// belongs to (see `ProviderType`).
  final String type;
  final String? logo;
  final bool nsfw;
  final String homeUrl;

  /// Home rows. Each carries its own list rule so one config can describe
  /// several shelves with different markup.
  final List<UniversalCatalog> catalogs;

  final UniversalListRule? search;
  final UniversalDetailRule? detail;
  final UniversalEpisodeRule? episodes;
  final UniversalStreamRule? streams;
  final UniversalPageRule? pages;
  final UniversalChapterRule? chapter;

  /// Present only for JSON-API sites. When set, every listing/detail/episode/
  /// stream read goes through the API instead of the HTML rules.
  final UniversalApiRule? api;

  /// Extra headers sent with every request (many APIs reject requests without
  /// the right `Origin`/`Referer`/`User-Agent`).
  final Map<String, String> headers;

  /// The exact decoded JSON this config came from. Persisted verbatim so an
  /// installed source round-trips through Hive with no lossy field-by-field
  /// re-serialisation (and a schema field added later needs no migration).
  final Map<String, dynamic> raw;

  bool get isApi => api != null;

  /// What gets written to Hive — the original JSON, untouched.
  Map<String, dynamic> toJsonForStore() => raw;

  static Map<String, dynamic> _map(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

  static List<Map<String, dynamic>> _list(Object? v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : const [];

  static Map<String, String> _strMap(Object? v) {
    final m = _map(v);
    return m.map((k, value) => MapEntry(k, value.toString()));
  }

  /// Parse a config from decoded JSON. Throws [FormatException] when the
  /// required `id`/`name`/`baseUrl` are missing, so a bad repo entry is
  /// skipped loudly instead of installing a source that can't resolve.
  factory UniversalConfig.fromJson(Map<String, dynamic> j) {
    final id = (j['id'] ?? '').toString().trim();
    final name = (j['name'] ?? '').toString().trim();
    final baseUrl = (j['baseUrl'] ?? '').toString().trim();
    if (id.isEmpty || name.isEmpty || baseUrl.isEmpty) {
      throw const FormatException(
        'universal config requires non-empty id, name and baseUrl',
      );
    }
    final apiRaw = j['api'];
    return UniversalConfig(
      id: id,
      name: name,
      baseUrl: baseUrl,
      lang: (j['lang'] ?? 'en').toString(),
      type: (j['type'] ?? 'movie').toString(),
      logo: j['logo']?.toString(),
      nsfw: j['nsfw'] == true,
      homeUrl: (j['homeUrl'] ?? '/').toString(),
      headers: _strMap(j['headers']),
      catalogs: [
        for (final c in _list(j['catalogs'])) UniversalCatalog.fromJson(c),
      ],
      search: j['search'] is Map
          ? UniversalListRule.fromJson(_map(j['search']))
          : null,
      detail: j['detail'] is Map
          ? UniversalDetailRule.fromJson(_map(j['detail']))
          : null,
      episodes: j['episodes'] is Map
          ? UniversalEpisodeRule.fromJson(_map(j['episodes']))
          : null,
      streams: j['streams'] is Map
          ? UniversalStreamRule.fromJson(_map(j['streams']))
          : null,
      pages: j['pages'] is Map
          ? UniversalPageRule.fromJson(_map(j['pages']))
          : null,
      chapter: j['chapter'] is Map
          ? UniversalChapterRule.fromJson(_map(j['chapter']))
          : null,
      api: apiRaw is Map ? UniversalApiRule.fromJson(_map(apiRaw)) : null,
      raw: Map<String, dynamic>.from(j),
    );
  }

  /// Parse a config from raw JSON text.
  factory UniversalConfig.fromString(String body) =>
      UniversalConfig.fromJson(jsonDecode(body) as Map<String, dynamic>);
}

/// One home row and the rule that lists it.
class UniversalCatalog {
  const UniversalCatalog({
    required this.id,
    required this.name,
    required this.path,
    required this.item,
    this.title = '',
    this.href = '',
    this.poster = '',
    this.type = '',
  });

  final String id;
  final String name;

  /// Path (joined to `baseUrl`) that returns the row. `{page}` is substituted.
  final String path;
  final String item;
  final String title;
  final String href;
  final String poster;

  /// `movie` or `series`; falls back to the config's type.
  final String type;

  factory UniversalCatalog.fromJson(Map<String, dynamic> j) => UniversalCatalog(
    id: (j['id'] ?? 'home').toString(),
    name: (j['name'] ?? 'Home').toString(),
    path: (j['path'] ?? '/').toString(),
    item: (j['item'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    href: (j['href'] ?? '').toString(),
    poster: (j['poster'] ?? '').toString(),
    type: (j['type'] ?? '').toString(),
  );
}

/// A list page (home row or search results) and how to read each card.
class UniversalListRule {
  const UniversalListRule({
    required this.path,
    this.item = '',
    this.title = '',
    this.href = '',
    this.poster = '',
    this.banner = '',
    this.overview = '',
  });

  final String path;
  final String item;
  final String title;
  final String href;
  final String poster;
  final String banner;
  final String overview;

  factory UniversalListRule.fromJson(Map<String, dynamic> j) =>
      UniversalListRule(
        path: (j['path'] ?? j['url'] ?? '/').toString(),
        item: (j['item'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        href: (j['href'] ?? '').toString(),
        poster: (j['poster'] ?? '').toString(),
        banner: (j['banner'] ?? '').toString(),
        overview: (j['overview'] ?? '').toString(),
      );
}

/// Detail-page field selectors.
class UniversalDetailRule {
  const UniversalDetailRule({
    this.title = '',
    this.poster = '',
    this.overview = '',
    this.genres = '',
    this.year = '',
    this.status = '',
    this.cast = '',
    this.type = '',
  });

  final String title;
  final String poster;
  final String overview;
  final String genres;
  final String year;
  final String status;
  final String cast;

  /// `movie` or `series` when the detail page itself declares it.
  final String type;

  factory UniversalDetailRule.fromJson(Map<String, dynamic> j) =>
      UniversalDetailRule(
        title: (j['title'] ?? '').toString(),
        poster: (j['poster'] ?? '').toString(),
        overview: (j['overview'] ?? j['description'] ?? '').toString(),
        genres: (j['genres'] ?? '').toString(),
        year: (j['year'] ?? '').toString(),
        status: (j['status'] ?? '').toString(),
        cast: (j['cast'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
      );
}

/// Episode-list rule. `url` may re-point at a separate endpoint.
class UniversalEpisodeRule {
  const UniversalEpisodeRule({
    this.url = '',
    this.item = '',
    this.number = '',
    this.title = '',
    this.href = '',
    this.thumbnail = '',
    this.date = '',
  });

  final String url;
  final String item;
  final String number;
  final String title;
  final String href;
  final String thumbnail;
  final String date;

  factory UniversalEpisodeRule.fromJson(Map<String, dynamic> j) =>
      UniversalEpisodeRule(
        url: (j['url'] ?? '').toString(),
        item: (j['item'] ?? '').toString(),
        number: (j['number'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        href: (j['href'] ?? '').toString(),
        thumbnail: (j['thumbnail'] ?? '').toString(),
        date: (j['date'] ?? '').toString(),
      );
}

/// Stream-extraction rule. Each field is a selector (or attribute) that
/// yields a playable URL; `iframe` is followed one level.
class UniversalStreamRule {
  const UniversalStreamRule({
    this.video = '',
    this.m3u8 = '',
    this.iframe = '',
    this.subtitles = '',
    this.subtitleUrl = '',
    this.subtitleLang = '',
  });

  final String video;
  final String m3u8;
  final String iframe;
  final String subtitles;
  final String subtitleUrl;
  final String subtitleLang;

  factory UniversalStreamRule.fromJson(Map<String, dynamic> j) =>
      UniversalStreamRule(
        video: (j['video'] ?? '').toString(),
        m3u8: (j['m3u8'] ?? '').toString(),
        iframe: (j['iframe'] ?? '').toString(),
        subtitles: (j['subtitles'] ?? '').toString(),
        subtitleUrl: (j['subtitleUrl'] ?? j['subUrl'] ?? '').toString(),
        subtitleLang: (j['subtitleLang'] ?? j['subLang'] ?? '').toString(),
      );
}

/// Manga page-image rule.
class UniversalPageRule {
  const UniversalPageRule({
    this.item = '',
    this.image = '',
    this.attribute = 'src',
  });

  final String item;
  final String image;
  final String attribute;

  factory UniversalPageRule.fromJson(Map<String, dynamic> j) =>
      UniversalPageRule(
        item: (j['item'] ?? '').toString(),
        image: (j['image'] ?? 'img').toString(),
        attribute: (j['attribute'] ?? 'src').toString(),
      );
}

/// Novel chapter-content rule.
class UniversalChapterRule {
  const UniversalChapterRule({this.content = '', this.title = ''});

  final String content;
  final String title;

  factory UniversalChapterRule.fromJson(Map<String, dynamic> j) =>
      UniversalChapterRule(
        content: (j['content'] ?? j['text'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
      );
}

/// JSON-API rule block for SPA sites. Field names mirror the response keys;
/// `{id}`, `{ep}`, `{lang}`, `{query}` and `{page}` are substituted.
class UniversalApiRule {
  const UniversalApiRule({
    required this.base,
    this.proxy = '',
    this.headers = const {},
    this.catalogs = const [],
    this.homePath = '/home',
    this.searchPath = '/search',
    this.searchResults = 'results',
    this.searchQueryParam = 'query',
    this.searchPageParam = 'page',
    this.detailPath = '/detail/{id}',
    this.detailData = '',
    this.episodesPath = '/episodes/{id}',
    this.episodesPageParam = 'page',
    this.episodesItems = 'episodes',
    this.episodesHasNext = 'hasNextPage',
    this.episodesMaxPages = 30,
    this.episodeNumber = 'number',
    this.episodeName = 'title',
    this.streamsPath = '/streams/{id}',
    this.streamsLangs = 'sub,dub',
    this.streamsSources = 'sources',
    this.streamsUrl = 'url',
    this.streamsQuality = 'quality',
    this.streamsIsM3u8 = 'isM3U8',
    this.streamsSubtitles = 'subtitles',
    this.streamsSubUrl = 'url',
    this.streamsSubLang = 'lang',
    this.streamsHeaders = 'headers',
    this.streamsUrlTemplate = '',
    this.streamsExtensions = '',
    this.streamsMetaPath = '/metadata/{id}',
    this.posterTemplate = '',
    this.idField = 'id',
    this.titleField = 'title',
    this.posterField = 'cover',
  });

  final String base;
  final String proxy;
  final Map<String, String> headers;
  final List<UniversalCatalog> catalogs;
  final String homePath;
  final String searchPath;
  final String searchResults;
  final String searchQueryParam;
  final String searchPageParam;
  final String detailPath;
  final String detailData;
  final String episodesPath;
  final String episodesPageParam;
  final String episodesItems;
  final String episodesHasNext;
  final int episodesMaxPages;
  final String episodeNumber;
  final String episodeName;
  final String streamsPath;
  final String streamsLangs;
  final String streamsSources;
  final String streamsUrl;
  final String streamsQuality;
  final String streamsIsM3u8;
  final String streamsSubtitles;
  final String streamsSubUrl;
  final String streamsSubLang;
  final String streamsHeaders;

  /// A template that builds a playable URL straight from the ids — used when
  /// the API gives a download/browse page rather than a stream. Substitutes
  /// `{id}`; with [streamsExtensions] set, `<ext>` is replaced by the extension
  /// of the first file in the `files` array whose name ends in one of them
  /// (e.g. `mp4`), so an archive item resolves to its real file.
  final String streamsUrlTemplate;
  final String streamsExtensions;

  /// Endpoint that returns an item's file list, used to resolve `<ext>` in
  /// [streamsUrlTemplate] (archive.org: `/metadata/{id}` → `files[]`).
  final String streamsMetaPath;

  /// A template that builds a poster URL from the id, when the API has no
  /// image field (e.g. archive.org's `<base>/services/img/<id>`).
  final String posterTemplate;

  final String idField;
  final String titleField;
  final String posterField;

  factory UniversalApiRule.fromJson(Map<String, dynamic> j) {
    final base = (j['base'] ?? '').toString().trim();
    if (base.isEmpty) {
      throw const FormatException('api block requires a non-empty "base"');
    }
    Map<String, String> strMap(Object? v) => v is Map
        ? Map<String, dynamic>.from(
            v,
          ).map((k, value) => MapEntry(k, value.toString()))
        : const {};
    return UniversalApiRule(
      base: base,
      proxy: (j['proxy'] ?? '').toString(),
      headers: strMap(j['headers']),
      catalogs: [
        for (final c in UniversalConfig._list(j['catalogs']))
          UniversalCatalog.fromJson(c),
      ],
      homePath: (j['homePath'] ?? '/home').toString(),
      searchPath: (j['searchPath'] ?? '/search').toString(),
      searchResults: (j['searchResults'] ?? 'results').toString(),
      searchQueryParam: (j['searchQueryParam'] ?? 'query').toString(),
      searchPageParam: (j['searchPageParam'] ?? 'page').toString(),
      detailPath: (j['detailPath'] ?? '/detail/{id}').toString(),
      detailData: (j['detailData'] ?? '').toString(),
      episodesPath: (j['episodesPath'] ?? '/episodes/{id}').toString(),
      episodesPageParam: (j['episodesPageParam'] ?? 'page').toString(),
      episodesItems: (j['episodesItems'] ?? 'episodes').toString(),
      episodesHasNext: (j['episodesHasNext'] ?? 'hasNextPage').toString(),
      episodesMaxPages: (j['episodesMaxPages'] as num?)?.toInt() ?? 30,
      episodeNumber: (j['episodeNumber'] ?? 'number').toString(),
      episodeName: (j['episodeName'] ?? 'title').toString(),
      streamsPath: (j['streamsPath'] ?? '/streams/{id}').toString(),
      streamsLangs: (j['streamsLangs'] ?? 'sub,dub').toString(),
      streamsSources: (j['streamsSources'] ?? 'sources').toString(),
      streamsUrl: (j['streamsUrl'] ?? 'url').toString(),
      streamsQuality: (j['streamsQuality'] ?? 'quality').toString(),
      streamsIsM3u8: (j['streamsIsM3u8'] ?? 'isM3U8').toString(),
      streamsSubtitles: (j['streamsSubtitles'] ?? 'subtitles').toString(),
      streamsSubUrl: (j['streamsSubUrl'] ?? 'url').toString(),
      streamsSubLang: (j['streamsSubLang'] ?? 'lang').toString(),
      streamsHeaders: (j['streamsHeaders'] ?? 'headers').toString(),
      streamsUrlTemplate: (j['streamsUrlTemplate'] ?? '').toString(),
      streamsExtensions: (j['streamsExtensions'] ?? '').toString(),
      streamsMetaPath: (j['streamsMetaPath'] ?? '/metadata/{id}').toString(),
      posterTemplate: (j['posterTemplate'] ?? '').toString(),
      idField: (j['idField'] ?? 'id').toString(),
      titleField: (j['titleField'] ?? 'title').toString(),
      posterField: (j['posterField'] ?? 'cover').toString(),
    );
  }
}
