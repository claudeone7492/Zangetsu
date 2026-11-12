import 'metadata_filters.dart';
import 'tmdb_catalogue.dart';

/// The filter choices TMDB only serves from its own reference endpoints:
/// which streaming services carry titles in a region, and which age ratings a
/// country uses.
///
/// Both are per-region and change rarely, so each is fetched once and cached
/// for the session. A failure yields an empty list rather than throwing — an
/// unavailable picker must not take the filter sheet down with it.
class TmdbFilterOptions {
  TmdbFilterOptions(this._get);

  final TmdbGet _get;

  final Map<String, Future<List<TmdbWatchProvider>>> _providers = {};
  final Map<String, Future<List<TmdbCertification>>> _certifications = {};

  /// Services with films available in [region], alphabetically.
  Future<List<TmdbWatchProvider>> watchProviders(String region) =>
      _providers.putIfAbsent(region, () => _loadProviders(region));

  Future<List<TmdbWatchProvider>> _loadProviders(String region) async {
    final both = await Future.wait([
      _get('/watch/providers/movie', {'watch_region': region}),
      _get('/watch/providers/tv', {'watch_region': region}),
    ]);
    final byId = <int, TmdbWatchProvider>{};
    for (final data in both) {
      for (final p in (data?['results'] as List? ?? const [])) {
        if (p is! Map) continue;
        final id = p['provider_id'];
        final name = p['provider_name'];
        if (id is! int || name is! String) continue;
        final logo = p['logo_path'] as String?;
        byId.putIfAbsent(
          id,
          () => TmdbWatchProvider(
            id: id,
            name: name,
            logoUrl: logo == null
                ? null
                : 'https://image.tmdb.org/t/p/w92$logo',
          ),
        );
      }
    }
    final out = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Age ratings [country] uses for films, in the order TMDB lists them.
  Future<List<TmdbCertification>> movieCertifications(String country) =>
      _certifications.putIfAbsent(country, () => _loadCertifications(country));

  Future<List<TmdbCertification>> _loadCertifications(String country) async {
    final data = await _get('/certification/movie/list', const {});
    final perCountry = data?['certifications'];
    if (perCountry is! Map) return const [];
    final list = perCountry[country];
    if (list is! List) return const [];
    final out = <TmdbCertification>[];
    for (final c in list) {
      if (c is! Map) continue;
      final code = c['certification'];
      if (code is! String || code.isEmpty) continue;
      out.add(
        TmdbCertification(code: code, meaning: c['meaning'] as String? ?? ''),
      );
    }
    return out;
  }
}
