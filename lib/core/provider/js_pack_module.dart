import 'dart:convert';

import '../models/provider_info.dart';
import 'js_pack_engine.dart';

/// One installed JS-pack module — the persisted unit of a `nuvio:`/`vega:`/…
/// source. Deliberately plain JSON so it round-trips through Hive and a backup
/// without codegen.
class JsPackModule {
  const JsPackModule({
    required this.engine,
    required this.id,
    required this.name,
    this.version = '1.0.0',
    this.lang = 'en',
    this.type = 'movie',
    this.logo = '',
    this.nsfw = false,
    this.baseUrl = '',
    this.file = '',
    this.repoUrl = '',
    this.code = '',
  });

  final JsPackEngine engine;

  /// Module id as declared by the repo — the `id` half of `prefix:id`.
  final String id;
  final String name;
  final String version;
  final String lang;

  /// `anime` | `movie` | `manga` | `novel`.
  final String type;
  final String logo;
  final bool nsfw;
  final String baseUrl;

  /// Absolute URL of the module's `.js`, or '' when [code] carries it inline.
  final String file;

  /// Repo manifest URL this module came from.
  final String repoUrl;

  /// Inline module source, set once fetched so a boot needs no network.
  final String code;

  /// Fully-qualified source id (`nuvio:tmdb`), the app-wide key.
  String get sourceId => '${engine.prefix}$id';

  ProviderType get providerType => switch (type) {
    'anime' => ProviderType.anime,
    'manga' => ProviderType.manga,
    'novel' => ProviderType.novel,
    _ => ProviderType.movie,
  };

  bool get isReading =>
      providerType == ProviderType.manga || providerType == ProviderType.novel;

  Map<String, dynamic> toJson() => {
    'engine': engine.name,
    'id': id,
    'name': name,
    'version': version,
    'lang': lang,
    'type': type,
    'logo': logo,
    'nsfw': nsfw,
    'baseUrl': baseUrl,
    'file': file,
    'repoUrl': repoUrl,
    if (code.isNotEmpty) 'code': code,
  };

  factory JsPackModule.fromJson(Map<String, dynamic> j) {
    final engineName = (j['engine'] as String?) ?? JsPackEngine.nuvio.name;
    final engine = JsPackEngine.values.firstWhere(
      (e) => e.name == engineName,
      orElse: () => JsPackEngine.nuvio,
    );
    return JsPackModule(
      engine: engine,
      id: (j['id'] as String).trim(),
      name: ((j['name'] as String?) ?? j['id'] as String).trim(),
      version: (j['version'] as String?) ?? '1.0.0',
      lang: (j['lang'] as String?) ?? 'en',
      type: (j['type'] as String?) ?? 'movie',
      logo: (j['logo'] as String?) ?? '',
      nsfw: (j['nsfw'] as bool?) ?? false,
      baseUrl: (j['baseUrl'] as String?) ?? '',
      file: (j['file'] as String?) ?? '',
      repoUrl: (j['repoUrl'] as String?) ?? '',
      code: (j['code'] as String?) ?? '',
    );
  }

  JsPackModule copyWith({
    String? code,
    String? file,
    String? repoUrl,
    String? logo,
    String? baseUrl,
    String? name,
    String? version,
  }) => JsPackModule(
    engine: engine,
    id: id,
    name: name ?? this.name,
    version: version ?? this.version,
    lang: lang,
    type: type,
    logo: logo ?? this.logo,
    nsfw: nsfw,
    baseUrl: baseUrl ?? this.baseUrl,
    file: file ?? this.file,
    repoUrl: repoUrl ?? this.repoUrl,
    code: code ?? this.code,
  );

  /// Parse one module from a repo index entry. Accepts the shapes the four
  /// families actually publish: `{id, name, file|url|js}`, `{name, url}`,
  /// and Hikari's `{id, name, lang, type, source}`. Returns null for an entry
  /// with no id or no way to fetch the code — a repo with one bad row must
  /// still install its good ones.
  static JsPackModule? tryParse(
    dynamic raw, {
    required JsPackEngine engine,
    required String repoUrl,
    required String base,
  }) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final id = (m['id'] ?? m['name'] ?? m['moduleId'] ?? '').toString().trim();
    if (id.isEmpty) return null;
    final file = _resolveFile(m, base);
    final inline = (m['js'] ?? m['code'] ?? m['source'])?.toString() ?? '';
    if (file.isEmpty && inline.isEmpty) return null;
    return JsPackModule(
      engine: engine,
      id: id,
      name: (m['name'] ?? id).toString().trim(),
      version: (m['version'] ?? '1.0.0').toString(),
      lang: (m['lang'] ?? m['language'] ?? 'en').toString(),
      type: (m['type'] ?? 'movie').toString(),
      logo: (m['logo'] ?? m['icon'] ?? '').toString(),
      nsfw: m['nsfw'] == true,
      baseUrl: (m['baseUrl'] ?? m['site'] ?? '').toString(),
      file: file,
      repoUrl: repoUrl,
      code: inline,
    );
  }

  static String _resolveFile(Map<String, dynamic> m, String base) {
    final raw = (m['file'] ?? m['url'] ?? m['path'] ?? m['jsFile'] ?? '')
        .toString()
        .trim();
    if (raw.isEmpty || raw.startsWith('data:')) return '';
    if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
    if (base.isEmpty) return raw;
    return Uri.parse(base).resolve(raw).toString();
  }

  /// Parse a whole repo index body into modules. Handles every shape the
  /// families publish, in one place:
  ///  * `{"sources"|"plugins"|"modules": [...]}`  (Nuvio, Vega, Sora, Hikari)
  ///  * a bare `[...]` array                            (Vega's raw list)
  ///  * `{"entries": [...]}`                            (our directory format)
  static List<JsPackModule> parseRepo(
    String body, {
    required JsPackEngine engine,
    required String repoUrl,
  }) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }
    final List raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map) {
      final list =
          decoded['sources'] ??
          decoded['plugins'] ??
          decoded['modules'] ??
          decoded['entries'] ??
          const [];
      raw = list is List ? list : const [];
    } else {
      return const [];
    }
    final base = _baseOf(repoUrl);
    final out = <JsPackModule>[];
    final seen = <String>{};
    for (final e in raw) {
      final mod = tryParse(e, engine: engine, repoUrl: repoUrl, base: base);
      // First definition of an id wins: a repo that lists a module twice (or
      // a hand-edited index) must not install the same source twice.
      if (mod != null && seen.add(mod.id)) out.add(mod);
    }
    return out;
  }

  /// The directory part of a repo URL, used to resolve relative module files.
  static String _baseOf(String url) {
    if (url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final path = uri.path;
    final cut = path.lastIndexOf('/');
    if (cut <= 0) return url;
    return uri.replace(path: path.substring(0, cut + 1)).toString();
  }
}
