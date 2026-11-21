import 'dart:convert';

/// One title from a Nuvio export.
class NuvioItem {
  const NuvioItem({
    required this.title,
    this.id = '',
    this.type = 'movie',
    this.poster,
    this.year,
  });

  final String title;
  final String id;
  final String type;
  final String? poster;
  final int? year;

  Map<String, dynamic> toJson() => {
    'title': title,
    'id': id,
    'type': type,
    if (poster != null) 'poster': poster,
    if (year != null) 'year': year,
  };
}

class NuvioCollection {
  const NuvioCollection({required this.name, required this.items});
  final String name;
  final List<NuvioItem> items;
}

/// Parses the JSON Nuvio exports from its library screen.
///
/// Accepts a bare item array, `{items: [...]}`, `{name, items}` and
/// `{collections: [...]}`. Anything else is rejected with a reason.
class NuvioImport {
  const NuvioImport._();

  static List<NuvioCollection> parse(String raw) {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        NuvioCollection(name: 'Nuvio', items: _items(decoded)),
      ];
    }
    if (decoded is! Map) throw const FormatException('not a Nuvio export');
    final collections = decoded['collections'];
    if (collections is List) {
      return [
        for (final entry in collections)
          if (entry is Map)
            NuvioCollection(
              name: (entry['name'] as String?)?.trim().isNotEmpty == true
                  ? entry['name'] as String
                  : 'Nuvio',
              items: _items(entry['items']),
            ),
      ];
    }
    return [
      NuvioCollection(
        name: (decoded['name'] as String?) ?? 'Nuvio',
        items: _items(decoded['items']),
      ),
    ];
  }

  static List<NuvioItem> _items(dynamic raw) {
    if (raw is! List) return const [];
    final out = <NuvioItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final title = (entry['title'] ?? entry['name'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      out.add(
        NuvioItem(
          title: title,
          id: (entry['id'] ?? entry['tmdbId'] ?? '').toString(),
          type: (entry['type'] ?? 'movie').toString(),
          poster: (entry['poster'] ?? entry['cover']) as String?,
          year: entry['year'] is num ? (entry['year'] as num).toInt() : null,
        ),
      );
    }
    return out;
  }
}
