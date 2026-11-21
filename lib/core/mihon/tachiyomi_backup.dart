import 'dart:convert';

/// One library row decoded from a Tachiyomi/Mihon backup.
class TachiyomiEntry {
  const TachiyomiEntry({
    required this.title,
    required this.url,
    required this.sourceId,
  });

  final String title;
  final String url;
  final String sourceId;

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    'sourceId': sourceId,
  };
}

/// Reads the library out of a `.tachibk`-unpacked backup JSON.
///
/// Tachiyomi and Mihon both write `{backupManga: [{manga: {...}, ...}]}`;
/// older builds use `{manga: [...]}`. The compressed `.tachibk` container is
/// not handled here — the caller decompresses it first.
class TachiyomiBackup {
  const TachiyomiBackup._();

  static List<TachiyomiEntry> parse(String raw) {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) throw const FormatException('not a backup');
    final rows = decoded['backupManga'] ?? decoded['manga'];
    if (rows is! List) throw const FormatException('no manga list');
    final out = <TachiyomiEntry>[];
    for (final row in rows) {
      if (row is! Map) continue;
      final manga = row['manga'] is Map ? row['manga'] as Map : row;
      final title = (manga['title'] ?? '').toString().trim();
      if (title.isEmpty) continue;
      out.add(
        TachiyomiEntry(
          title: title,
          url: (manga['url'] ?? '').toString(),
          sourceId: (manga['source'] ?? manga['sourceId'] ?? '').toString(),
        ),
      );
    }
    return out;
  }
}
