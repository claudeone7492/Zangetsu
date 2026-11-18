import 'dart:convert';

import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/page_content.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';
import '../provider/base_provider.dart';
import '../provider/reading_provider.dart';
import 'universal_config.dart';
import 'universal_selector.dart';

/// One HTTP fetch, injected so the provider has no opinion about the client.
/// The app passes a `dio`-backed implementation; tests pass a real
/// [HttpServer]-backed one, so the same code path is exercised.
typedef UniversalFetch =
    Future<String> Function(String url, {Map<String, String>? headers});

/// A source driven entirely by a [UniversalConfig] — the app's own
/// implementation of Hikari's "universal scraper": a site is added by
/// describing it in JSON, no code, no APK.
///
/// Routed by the `us:` id prefix (see `SourceRepository`), so it lands in the
/// source picker, search fan-out and cross-source routing exactly like every
/// JS provider — the only difference is what runs underneath.
class UniversalProvider implements BaseProvider, ReadingProvider {
  UniversalProvider({required this.config, required UniversalFetch fetch})
    : _fetch = fetch;

  final UniversalConfig config;
  final UniversalFetch _fetch;

  static const String idPrefix = 'us:';

  @override
  String get sourceId => '$idPrefix${config.id}';

  @override
  String get displayName => config.name;

  ProviderType get providerType => switch (config.type) {
    'anime' => ProviderType.anime,
    'manga' => ProviderType.manga,
    'novel' => ProviderType.novel,
    _ => ProviderType.movie,
  };

  bool get isReading =>
      providerType == ProviderType.manga || providerType == ProviderType.novel;

  Map<String, String> get _headers => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/json,*/*',
    ...config.headers,
  };

  Future<String> _get(String url, {Map<String, String>? headers}) =>
      _fetch(url, headers: {..._headers, ...?headers});

  Future<dynamic> _getJson(String url, {Map<String, String>? headers}) async {
    final body = await _get(url, headers: headers);
    return jsonDecode(body);
  }

  @override
  Future<ProviderInfo> getInfo() async => ProviderInfo(
    name: config.name,
    lang: config.lang,
    baseUrl: config.baseUrl,
    logo: config.logo,
    type: providerType,
    version: '1.0.0',
  );

  // ── Home ──────────────────────────────────────────────────────────────────

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) async {
    if (config.isApi) return _apiHome();
    final sections = <HomeSection>[];
    for (final catalog in config.catalogs) {
      final items = await _htmlList(
        resolveTemplate(catalog.path, base: config.baseUrl, page: 1),
        item: catalog.item,
        title: catalog.title,
        href: catalog.href,
        poster: catalog.poster,
        type: catalog.type,
      );
      if (items.isNotEmpty) {
        sections.add(HomeSection(title: catalog.name, items: items));
      }
    }
    return sections.isEmpty ? null : sections;
  }

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) async {
    if (config.isApi) {
      final sections = await _apiHome();
      return sections.isEmpty ? const [] : sections.first.items;
    }
    final catalog = config.catalogs.isNotEmpty ? config.catalogs.first : null;
    if (catalog == null) return const [];
    return _htmlList(
      resolveTemplate(catalog.path, base: config.baseUrl, page: page),
      item: catalog.item,
      title: catalog.title,
      href: catalog.href,
      poster: catalog.poster,
      type: catalog.type,
    );
  }

  // ── Search ────────────────────────────────────────────────────────────────

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) async {
    if (config.isApi) {
      final api = config.api!;
      final url = _apiUrl(
        api.searchPath,
        query: query,
        page: page,
        queryParam: api.searchQueryParam,
        pageParam: api.searchPageParam,
      );
      final data = await _getJson(url);
      final results = _dig(data, api.searchResults);
      return _apiItems(results is List ? results : const []);
    }
    final rule = config.search;
    if (rule == null) return const [];
    return _htmlList(
      resolveTemplate(
        rule.path,
        base: config.baseUrl,
        query: query,
        page: page,
      ),
      item: rule.item,
      title: rule.title,
      href: rule.href,
      poster: rule.poster,
      banner: rule.banner,
      type: config.type,
    );
  }

  // ── Detail ────────────────────────────────────────────────────────────────

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) async {
    if (config.isApi) return _apiDetail(url);
    final doc = UniversalSelector.parse(await _get(url));
    final d = config.detail ?? const UniversalDetailRule();
    final type = _typeFromString(d.type.isEmpty ? config.type : d.type);
    return MediaDetail(
      id: url,
      title: UniversalSelector.read(doc, d.title) ?? _titleFromUrl(url),
      cover: _absolute(UniversalSelector.read(doc, d.poster), url),
      banner: null,
      url: url,
      description: UniversalSelector.read(doc, d.overview),
      genres: _splitList(UniversalSelector.read(doc, d.genres)),
      cast: _splitList(UniversalSelector.read(doc, d.cast)),
      year: UniversalSelector.read(doc, d.year),
      type: type,
      sourceId: sourceId,
    );
  }

  // ── Episodes ──────────────────────────────────────────────────────────────

  @override
  Future<List<Episode>> getEpisodes(
    String url, {
    String category = 'sub',
  }) async {
    if (config.isApi) return _apiEpisodes(url);
    final rule = config.episodes;
    if (rule == null) return const [];
    final target = rule.url.isEmpty
        ? url
        : resolveTemplate(rule.url, base: config.baseUrl, href: url);
    final doc = UniversalSelector.parse(await _get(target));
    final items = rule.item.isEmpty
        ? <Episode>[]
        : UniversalSelector.elements(doc, rule.item).asMap().entries.map((e) {
            final el = e.value;
            final href = _absolute(
              UniversalSelector.readIn(el, rule.href),
              target,
            );
            final num = UniversalSelector.readIn(el, rule.number);
            return Episode(
              id: href ?? '$url#${e.key + 1}',
              title:
                  UniversalSelector.readIn(el, rule.title) ??
                  'Episode ${num ?? e.key + 1}',
              number: double.tryParse(num ?? '') ?? (e.key + 1).toDouble(),
              url: href ?? url,
              thumbnail: _absolute(
                UniversalSelector.readIn(el, rule.thumbnail),
                target,
              ),
              date: UniversalSelector.readIn(el, rule.date),
            );
          }).toList();
    // A movie source has no episode list — surface the page itself as one
    // playable "episode" so the player opens the single stream.
    if (items.isEmpty) {
      return [
        Episode(id: url, title: 'Play', number: 1, url: url),
      ];
    }
    return items;
  }

  // ── Streams ───────────────────────────────────────────────────────────────

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) async {
    if (config.isApi) return _apiStreams(episodeUrl);
    final rule = config.streams;
    if (rule == null) return const [];
    final doc = UniversalSelector.parse(await _get(episodeUrl));
    final sources = <VideoSource>[];
    final subs = _readSubtitles(doc, rule, episodeUrl);

    void add(String? raw, SourceContainer container) {
      final abs = _absolute(raw, episodeUrl);
      if (abs == null || !abs.startsWith('http')) return;
      sources.add(
        VideoSource(
          url: abs,
          container: container,
          kind: AudioKind.unknown,
          headers: _headers,
          subtitles: subs,
        ),
      );
    }

    for (final raw in _all(doc, rule.m3u8)) {
      add(raw, SourceContainer.hls);
    }
    for (final raw in _all(doc, rule.video)) {
      add(raw, _containerFor(raw));
    }
    // Follow one iframe level: fetch the embed and look for a video/m3u8.
    for (final raw in _all(doc, rule.iframe)) {
      final embed = _absolute(raw, episodeUrl);
      if (embed == null || !embed.startsWith('http')) continue;
      try {
        final inner = UniversalSelector.parse(await _get(embed));
        final found = <String?>[
          ..._all(inner, rule.m3u8),
          ..._all(inner, rule.video),
          ..._all(inner, 'video@src'),
          ..._all(inner, 'source@src'),
        ];
        for (final f in found) {
          final abs = _absolute(f, embed);
          if (abs != null && abs.startsWith('http')) {
            sources.add(
              VideoSource(
                url: abs,
                container: _containerFor(abs),
                kind: AudioKind.unknown,
                headers: _headers,
                subtitles: subs,
              ),
            );
          }
        }
      } catch (_) {
        // A dead embed shouldn't sink the sources that did resolve.
      }
    }
    return sources;
  }

  List<Subtitle> _readSubtitles(
    dynamic doc,
    UniversalStreamRule rule,
    String base,
  ) {
    if (rule.subtitles.isEmpty) return const [];
    final out = <Subtitle>[];
    for (final el in UniversalSelector.elements(doc, rule.subtitles)) {
      final url = _absolute(
        UniversalSelector.readIn(el, rule.subtitleUrl),
        base,
      );
      if (url == null) continue;
      final lang = UniversalSelector.readIn(el, rule.subtitleLang) ?? 'und';
      out.add(
        Subtitle(
          url: url,
          lang: lang,
          format: url.contains('.srt') ? 'srt' : 'vtt',
        ),
      );
    }
    return out;
  }

  // ── Reading leaf (manga / novel) ──────────────────────────────────────────

  @override
  Future<List<PageImage>> getPages(String chapterUrl) async {
    final rule = config.pages;
    if (rule == null) return const [];
    final doc = UniversalSelector.parse(await _get(chapterUrl));
    final out = <PageImage>[];
    for (final el in UniversalSelector.elements(doc, rule.item)) {
      final raw = UniversalSelector.readIn(el, 'img@${rule.attribute}') ??
          UniversalSelector.readIn(el, '${rule.image}@${rule.attribute}');
      final abs = _absolute(raw, chapterUrl);
      if (abs != null) out.add(PageImage(url: abs, headers: _headers));
    }
    return out;
  }

  @override
  Future<ChapterText> getText(String chapterUrl) async {
    final rule = config.chapter;
    if (rule == null) return const ChapterText(html: '');
    final doc = UniversalSelector.parse(await _get(chapterUrl));
    final el = UniversalSelector.firstElement(doc, rule.content);
    return ChapterText(
      html: el?.innerHtml ?? '',
      title: rule.title.isEmpty
          ? null
          : UniversalSelector.read(doc, rule.title),
    );
  }

  // ── HTML helpers ──────────────────────────────────────────────────────────

  Future<List<MediaItem>> _htmlList(
    String url, {
    required String item,
    required String title,
    required String href,
    required String poster,
    String banner = '',
    String type = '',
  }) async {
    if (item.isEmpty) return const [];
    final doc = UniversalSelector.parse(await _get(url));
    final items = <MediaItem>[];
    for (final el in UniversalSelector.elements(doc, item)) {
      final t = title.isEmpty ? null : UniversalSelector.readIn(el, title);
      final h = href.isEmpty ? null : UniversalSelector.readIn(el, href);
      final abs = _absolute(h, url);
      if (t == null || abs == null) continue;
      items.add(
        MediaItem(
          id: abs,
          title: t,
          cover: _absolute(
            poster.isEmpty ? null : UniversalSelector.readIn(el, poster),
            url,
          ),
          banner: banner.isEmpty
              ? null
              : _absolute(UniversalSelector.readIn(el, banner), url),
          url: abs,
          type: _typeFromString(type.isEmpty ? config.type : type),
          sourceId: sourceId,
        ),
      );
    }
    return items;
  }

  List<String?> _all(dynamic doc, String rule) {
    if (rule.isEmpty) return const [];
    return UniversalSelector.elements(doc, rule)
        .map((el) => UniversalSelector.readIn(el, rule))
        .toList();
  }

  // ── API helpers ───────────────────────────────────────────────────────────

  String _apiUrl(
    String path, {
    String? query,
    int? page,
    String? id,
    String? ep,
    String? lang,
    String? queryParam,
    String? pageParam,
  }) {
    final api = config.api!;
    var p = path
        .replaceAll('{query}', Uri.encodeQueryComponent(query ?? ''))
        .replaceAll('{id}', id ?? '')
        .replaceAll('{ep}', ep ?? '')
        .replaceAll('{lang}', lang ?? '')
        .replaceAll('{page}', '${page ?? 1}');
    final b = api.base.endsWith('/')
        ? api.base.substring(0, api.base.length - 1)
        : api.base;
    var url = p.startsWith('http') ? p : '$b${p.startsWith('/') ? '' : '/'}$p';
    final params = <String, String>{};
    if (query != null && queryParam != null && queryParam.isNotEmpty) {
      params[queryParam] = query;
    }
    if (page != null && pageParam != null && pageParam.isNotEmpty) {
      params[pageParam] = '$page';
    }
    if (params.isNotEmpty) {
      final sep = url.contains('?') ? '&' : '?';
      url += sep +
          params.entries
              .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
              .join('&');
    }
    return url;
  }

  Future<List<HomeSection>> _apiHome() async {
    final api = config.api!;
    final data = await _getJson(_apiUrl(api.homePath));
    final sections = <HomeSection>[];
    for (final catalog in api.catalogs) {
      final raw = _dig(data, catalog.id);
      final items = _apiItems(raw is List ? raw : const []);
      if (items.isNotEmpty) {
        sections.add(HomeSection(title: catalog.name, items: items));
      }
    }
    return sections;
  }

  Future<MediaDetail> _apiDetail(String url) async {
    final api = config.api!;
    final id = _extractId(url);
    final data = await _getJson(_apiUrl(api.detailPath, id: id));
    final obj = api.detailData.isEmpty
        ? data
        : _dig(data, api.detailData);
    final m = obj is Map ? Map<String, dynamic>.from(obj) : <String, dynamic>{};
    final titleRaw = _dig(m, api.titleField);
    return MediaDetail(
      id: url,
      title: _titleString(titleRaw) ?? _titleFromUrl(url),
      cover: _apiPoster(m, id, url),
      banner: _absolute(_string(_dig(m, 'bannerImage')), url),
      url: url,
      description: _string(_dig(m, 'description') ?? _dig(m, 'overview')),
      genres: _stringList(_dig(m, 'genres')),
      year: _string(_dig(m, 'seasonYear') ?? _dig(m, 'year')),
      type: _apiType(m),
      sourceId: sourceId,
    );
  }

  /// Poster from the API's image field, else the config's [posterTemplate]
  /// (`<base>/services/img/{id}` for archive.org), else null.
  String? _apiPoster(Map<String, dynamic> m, String id, String base) {
    final api = config.api!;
    final direct = _absolute(_string(_dig(m, api.posterField)), base);
    if (direct != null) return direct;
    if (api.posterTemplate.isEmpty) return null;
    return api.posterTemplate.replaceAll('{id}', id);
  }

  Future<List<Episode>> _apiEpisodes(String url) async {
    final api = config.api!;
    final id = _extractId(url);
    // A movie/whole-item source has no episode list: the item IS the one
    // playable unit, so the detail object maps to a single episode.
    if (api.episodesItems == '__single__') {
      return [Episode(id: '$id|1', title: 'Play', number: 1, url: '$id|1')];
    }
    final out = <Episode>[];
    for (var page = 1; page <= api.episodesMaxPages; page++) {
      final data = await _getJson(
        _apiUrl(api.episodesPath, id: id, page: page),
      );
      final list = _dig(data, api.episodesItems);
      if (list is! List) break;
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final rawNum = _dig(m, api.episodeNumber);
        final parsedNum = rawNum is num
            ? rawNum.toDouble()
            : double.tryParse('$rawNum');
        final epNum = parsedNum ?? (out.length + 1).toDouble();
        out.add(
          Episode(
            id: '$id|${epNum.toInt()}',
            title: _string(_dig(m, api.episodeName)) ?? 'Episode ${epNum.toInt()}',
            number: epNum,
            // Carry the ids the streams step needs: `<animeId>|<ep>`.
            url: '$id|${epNum.toInt()}',
          ),
        );
      }
      final hasNext = _dig(data, api.episodesHasNext);
      if (hasNext != true) break;
    }
    if (out.isEmpty) {
      return [Episode(id: '$id|1', title: 'Play', number: 1, url: '$id|1')];
    }
    return out;
  }

  Future<List<VideoSource>> _apiStreams(String episodeUrl) async {
    final api = config.api!;
    final parts = episodeUrl.split('|');
    final id = parts.isNotEmpty ? parts[0] : episodeUrl;
    final ep = parts.length > 1 ? parts[1] : '1';
    final sources = <VideoSource>[];
    final seen = <String>{};
    for (final lang in api.streamsLangs.split(',')) {
      final l = lang.trim();
      if (l.isEmpty) continue;
      dynamic data;
      try {
        data = await _getJson(
          _apiUrl(api.streamsPath, id: id, ep: ep, lang: l),
        );
      } catch (_) {
        continue;
      }
      final raw = _dig(data, api.streamsSources);
      if (raw is! List) continue;
      for (final s in raw) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        final url = _string(_dig(m, api.streamsUrl));
        if (url == null || !url.startsWith('http') || !seen.add(url)) continue;
        final isM3u8 = _dig(m, api.streamsIsM3u8) == true ||
            url.contains('.m3u8');
        sources.add(
          VideoSource(
            url: url,
            quality: _string(_dig(m, api.streamsQuality)),
            label: l.isEmpty ? null : l.toUpperCase(),
            container: isM3u8 ? SourceContainer.hls : SourceContainer.mp4,
            kind: l == 'dub'
                ? AudioKind.dub
                : (l == 'sub' ? AudioKind.sub : AudioKind.unknown),
            audioLang: l,
            headers: _headers,
            subtitles: _apiSubtitles(m, api),
          ),
        );
      }
    }
    // A config that builds its URL from the ids (archive.org: a download page
    // rather than a JSON stream) is resolved here, once, after the API sources.
    if (api.streamsUrlTemplate.isNotEmpty) {
      final built = await _buildTemplateStream(api, id);
      if (built != null && seen.add(built.url)) sources.add(built);
    }
    return sources;
  }

  /// Resolve [UniversalApiRule.streamsUrlTemplate] to a playable source. When
  /// [UniversalApiRule.streamsExtensions] is set, fetch the item's metadata
  /// first and swap `<ext>` for the extension of the first matching file.
  Future<VideoSource?> _buildTemplateStream(
    UniversalApiRule api,
    String id,
  ) async {
    var template = api.streamsUrlTemplate.replaceAll('{id}', id);
    if (template.contains('<ext>')) {
      final exts = api.streamsExtensions
          .split(',')
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
      String? picked;
      try {
        final meta = await _getJson(_apiUrl(api.streamsMetaPath, id: id));
        final files = meta is Map ? meta['files'] : null;
        if (files is List) {
          for (final f in files) {
            if (f is! Map) continue;
            final name = (f['name'] ?? '').toString();
            final lower = name.toLowerCase();
            for (final ext in exts) {
              // Skip the "*.ia.mp4" derivative archive.org serves alongside
              // the original — it 404s on some items.
              if (lower.endsWith('.$ext') && !lower.endsWith('.ia.$ext')) {
                picked = name;
                break;
              }
            }
            if (picked != null) break;
          }
        }
      } catch (_) {
        return null;
      }
      if (picked == null) return null;
      // The filename is a path segment — encode it (spaces, non-ASCII) so the
      // request matches what the host serves.
      template = template.replaceAll('<ext>', Uri.encodeComponent(picked));
    }
    final url = template.startsWith('http')
        ? template
        : '${api.base}${template.startsWith('/') ? '' : '/'}$template';
    return VideoSource(
      url: url,
      container: _containerFor(url),
      kind: AudioKind.unknown,
      headers: _headers,
    );
  }

  List<Subtitle> _apiSubtitles(Map<String, dynamic> source, UniversalApiRule api) {
    final raw = _dig(source, api.streamsSubtitles);
    if (raw is! List) return const [];
    final out = <Subtitle>[];
    for (final s in raw) {
      if (s is! Map) continue;
      final m = Map<String, dynamic>.from(s);
      final url = _string(_dig(m, api.streamsSubUrl));
      if (url == null) continue;
      out.add(
        Subtitle(
          url: url,
          lang: _string(_dig(m, api.streamsSubLang)) ?? 'und',
          format: url.contains('.srt') ? 'srt' : 'vtt',
        ),
      );
    }
    return out;
  }

  List<MediaItem> _apiItems(List raw) {
    final api = config.api!;
    final out = <MediaItem>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = _string(_dig(m, api.idField));
      final title = _titleString(_dig(m, api.titleField));
      if (id == null || title == null) continue;
      final detailUrl = _apiUrl(api.detailPath, id: id);
      out.add(
        MediaItem(
          id: detailUrl,
          title: title,
          cover: _apiPoster(m, id, detailUrl),
          banner: _absolute(_string(_dig(m, 'bannerImage')), detailUrl),
          url: detailUrl,
          type: _apiType(m),
          sourceId: sourceId,
        ),
      );
    }
    return out;
  }

  ProviderType _apiType(Map<String, dynamic> m) {
    final fmt = (_string(_dig(m, 'format')) ?? _string(_dig(m, 'type')) ?? '')
        .toUpperCase();
    if (fmt.contains('MOVIE')) return ProviderType.movie;
    if (config.type == 'anime') return ProviderType.anime;
    return _typeFromString(config.type);
  }

  // ── Shared ────────────────────────────────────────────────────────────────

  /// Deep-read a dotted key path (`"data.results"`) from a decoded JSON value.
  static dynamic _dig(dynamic node, String key) {
    if (key.isEmpty || node == null) return node;
    dynamic cur = node;
    for (final part in key.split('.')) {
      if (cur is Map && cur.containsKey(part)) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  static String? _string(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  /// A title that may be a plain string or `{english, romaji, native}`.
  static String? _titleString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.trim().isEmpty ? null : v.trim();
    if (v is Map) {
      for (final k in ['english', 'romaji', 'userPreferred', 'native', 'title']) {
        final s = _string(v[k]);
        if (s != null) return s;
      }
    }
    return _string(v);
  }

  static List<String> _stringList(dynamic v) => v is List
      ? v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList()
      : const [];

  static List<String> _splitList(String? v) => v == null
      ? const []
      : v
          .split(RegExp(r'[,\u2022|/]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  ProviderType _typeFromString(String s) => switch (s) {
    'anime' => ProviderType.anime,
    'manga' => ProviderType.manga,
    'novel' => ProviderType.novel,
    'movie' || 'series' || 'tv' => ProviderType.movie,
    _ => ProviderType.movie,
  };

  static SourceContainer _containerFor(String? url) {
    if (url == null) return SourceContainer.unknown;
    if (url.contains('.m3u8')) return SourceContainer.hls;
    if (url.contains('.mp4')) return SourceContainer.mp4;
    return SourceContainer.unknown;
  }

  static String? _absolute(String? raw, String base) {
    if (raw == null) return null;
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http://') || v.startsWith('https://')) return v;
    if (v.startsWith('//')) return 'https:$v';
    final uri = Uri.tryParse(base);
    if (uri == null) return v;
    return uri.resolve(v).toString();
  }

  static String _titleFromUrl(String url) {
    final seg = Uri.tryParse(url)?.pathSegments ?? const [];
    if (seg.isEmpty) return 'Untitled';
    return Uri.decodeComponent(seg.last)
        .replaceAll(RegExp(r'[-_]+'), ' ')
        .trim();
  }

  String _extractId(String url) {
    final api = config.api;
    if (api == null) return url;
    if (api.detailPath.endsWith('{id}')) {
      final seg = Uri.tryParse(url)?.pathSegments ?? const [];
      if (seg.isNotEmpty) return seg.last;
    }
    // Fall back to the segment after the last '/' in the template.
    final idx = api.detailPath.lastIndexOf('/');
    if (idx >= 0) {
      final seg = Uri.tryParse(url)?.pathSegments ?? const [];
      if (seg.isNotEmpty) return seg.last;
    }
    return url;
  }
}
