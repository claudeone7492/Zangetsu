import 'dart:convert';

/// One plugin listed in a Hikari repository index.
///
/// The real index (`codegeasse1/hikari-extensions`, branch `builds`,
/// `repo.json`) has this shape — verified against the live file, 203 entries:
///
/// ```json
/// { "name": "Hikari Extensions", "description": "...",
///   "plugins": [ { "name": "51CG", "description": "...",
///                  "url": "https://…/continuous/51cg.hiki",
///                  "version": 7,
///                  "fileHash": "sha256-<hex>",
///                  "tvTypes": ["movie"] } ] }
/// ```
///
/// Note what is NOT here: no `mainClass`, no `id`. The class to instantiate is
/// only known once the `.hiki` is downloaded and its own `manifest.json` is
/// read, so an entry is a *download descriptor* and nothing more.
class HikariRepoEntry {
  const HikariRepoEntry({
    required this.name,
    required this.url,
    required this.version,
    this.description = '',
    this.fileHash,
    this.tvTypes = const [],
  });

  final String name;

  /// Absolute URL of the `.hiki` file.
  final String url;

  /// Repository-declared version. The manifest inside the archive also carries
  /// a version; this one is what the index advertises, so updates are detected
  /// without downloading.
  final int version;

  final String description;

  /// `sha256-<hex>`, or null when the index doesn't publish one.
  final String? fileHash;

  final List<String> tvTypes;

  /// The hex digest without the `sha256-` prefix, or null.
  String? get sha256Hex {
    final hash = fileHash;
    if (hash == null) return null;
    final trimmed = hash.trim();
    if (trimmed.isEmpty) return null;
    const prefix = 'sha256-';
    return trimmed.toLowerCase().startsWith(prefix)
        ? trimmed.substring(prefix.length).toLowerCase()
        : trimmed.toLowerCase();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'version': version,
    'description': description,
    if (fileHash != null) 'fileHash': fileHash,
    'tvTypes': tvTypes,
  };

  factory HikariRepoEntry.fromJson(Map<String, dynamic> j) => HikariRepoEntry(
    name: (j['name'] ?? '').toString().trim(),
    url: (j['url'] ?? '').toString().trim(),
    version: j['version'] is int
        ? j['version'] as int
        : int.tryParse('${j['version']}') ?? 1,
    description: (j['description'] ?? '').toString(),
    fileHash: (j['fileHash'] as String?)?.trim().isEmpty == true
        ? null
        : j['fileHash'] as String?,
    tvTypes: [
      if (j['tvTypes'] is List)
        for (final t in j['tvTypes'] as List)
          if (t != null && '$t'.trim().isNotEmpty) '$t'.trim(),
    ],
  );
}

/// A parsed Hikari repository index.
class HikariRepo {
  const HikariRepo({
    required this.name,
    required this.entries,
    this.description = '',
  });

  final String name;
  final String description;
  final List<HikariRepoEntry> entries;

  /// Parses a repository index.
  ///
  /// [baseUrl] resolves relative plugin URLs, which some third-party indexes
  /// use. Entries with no usable name or URL are dropped rather than surfaced
  /// as broken tiles — an index is third-party data and one bad row must not
  /// hide the other 202.
  static HikariRepo parse(String body, {String baseUrl = ''}) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Not a Hikari repository index (expected an object)');
    }
    final rawPlugins = decoded['plugins'];
    if (rawPlugins is! List) {
      throw const FormatException('Hikari repository index has no "plugins" array');
    }

    final entries = <HikariRepoEntry>[];
    for (final raw in rawPlugins) {
      if (raw is! Map) continue;
      final entry = HikariRepoEntry.fromJson(Map<String, dynamic>.from(raw));
      if (entry.name.isEmpty || entry.url.isEmpty) continue;
      entries.add(
        entry.url.startsWith('http')
            ? entry
            : HikariRepoEntry(
                name: entry.name,
                url: _resolve(entry.url, baseUrl),
                version: entry.version,
                description: entry.description,
                fileHash: entry.fileHash,
                tvTypes: entry.tvTypes,
              ),
      );
    }

    return HikariRepo(
      name: (decoded['name'] ?? '').toString().trim().isEmpty
          ? 'Hikari repository'
          : decoded['name'].toString().trim(),
      description: (decoded['description'] ?? '').toString(),
      entries: entries,
    );
  }

  static String _resolve(String relative, String baseUrl) {
    if (baseUrl.isEmpty) return relative;
    // Resolve against the index URL as given: `Uri.resolve` drops a trailing
    // file segment (`…/repo.json`) but keeps a trailing directory (`…/repo/`),
    // which is right for both shapes an index URL arrives in.
    return Uri.parse(baseUrl).resolve(relative).toString();
  }
}
