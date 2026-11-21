/// Collapses the same title arriving from different engines.
///
/// Nuvio and Stremio catalogues overlap: the same film can appear in two rows
/// under a TMDB id, an IMDb id and a title+year. Hikari's `HomeDedupe` keeps
/// the first occurrence per identity. Zangetsu deduped only by `sourceId:id`,
/// which cannot see across engines.
class HomeDedupe {
  const HomeDedupe._();

  static final RegExp _bareTmdb = RegExp(r'^\d+$');
  static final RegExp _imdb = RegExp(r'^tt(\d+)$', caseSensitive: false);
  static final RegExp _prefixedTmdb = RegExp(
    r'^tmdb:(\d+)(?::([a-z]+))?$',
    caseSensitive: false,
  );

  /// A stable identity for one title, or null when the id carries nothing
  /// usable. A null key means "never collapse this item".
  static String? keyFor({
    required String id,
    String? type,
    int? year,
    String? title,
  }) {
    final kind = (type == 'series' || type == 'tv' || type == 'anime')
        ? 'tv'
        : 'movie';
    final trimmed = id.trim();
    if (_bareTmdb.hasMatch(trimmed)) return 'tmdb:$trimmed:$kind';
    final imdb = _imdb.firstMatch(trimmed);
    if (imdb != null) return 'imdb:${imdb.group(1)}';
    final prefixed = _prefixedTmdb.firstMatch(trimmed);
    if (prefixed != null) return 'tmdb:${prefixed.group(1)}:$kind';
    final norm = _normalize(title);
    if (norm.isNotEmpty && year != null) return 't:$norm|$year|$kind';
    return null;
  }

  static String _normalize(String? title) => (title ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();

  static List<T> dedupe<T>(
    Iterable<T> items, {
    required String? Function(T) key,
  }) {
    final seen = <String>{};
    final out = <T>[];
    for (final item in items) {
      final k = key(item);
      if (k != null && !seen.add(k)) continue;
      out.add(item);
    }
    return out;
  }
}
