import 'dart:convert';

import 'package:dio/dio.dart';

/// Artwork and a few facts from TheTVDB's keyless website search.
///
/// TMDB is the primary source; TVDB fills a missing poster or wide banner for
/// titles TMDB has no art for, and carries the TMDB/IMDb ids that let the
/// caller cross-validate a match. A miss returns null and never throws.
class TvdbInfo {
  const TvdbInfo({
    required this.title,
    this.poster,
    this.banner,
    this.overview,
    this.year,
    this.tmdbId,
    this.imdbId,
  });

  final String title;
  final String? poster;
  final String? banner;
  final String? overview;
  final int? year;
  final String? tmdbId;
  final String? imdbId;
}

class TvdbArt {
  TvdbArt(this._dio, {String searchUrl = 'https://api4.thetvdb.com/web/search/queries'})
    : _searchUrl = searchUrl;

  final Dio _dio;
  final String _searchUrl;

  static final Map<String, TvdbInfo?> _cache = {};

  Future<TvdbInfo?> lookup({
    required String title,
    String? originalTitle,
    int? year,
    bool isMovie = false,
  }) async {
    final query = title.trim();
    if (query.length < 2) return null;
    final key = '${query.toLowerCase()}|${year ?? 0}|$isMovie';
    if (_cache.containsKey(key)) return _cache[key];

    for (final candidate in {query, (originalTitle ?? '').trim()}
        .where((value) => value.length >= 2)
        .take(2)) {
      final info = await _search(candidate, year: year, isMovie: isMovie);
      if (info != null) {
        _cache[key] = info;
        return info;
      }
    }
    _cache[key] = null;
    return null;
  }

  Future<TvdbInfo?> _search(
    String query, {
    int? year,
    required bool isMovie,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _searchUrl,
        data: jsonEncode({
          'requests': [
            {
              'indexName': 'TVDB',
              'params': {'query': query},
            },
          ],
        }),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if ((response.statusCode ?? 0) >= 400) return null;
      final results = response.data?['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      final hits = first is Map ? first['hits'] : null;
      if (hits is! List) return null;

      TvdbInfo? best;
      var bestScore = 0;
      for (final hit in hits) {
        if (hit is! Map) continue;
        final type = '${hit['type'] ?? ''}'.toLowerCase();
        if (isMovie && type.isNotEmpty && type != 'movie') continue;
        if (!isMovie && type.isNotEmpty && type != 'series') continue;

        final names = <String>[
          '${hit['name'] ?? ''}',
          ...?(hit['aliases'] is List
              ? (hit['aliases'] as List).map((a) => '$a')
              : null),
        ].where((n) => n.trim().isNotEmpty).toList();
        if (names.isEmpty) continue;

        var score = 0;
        for (final name in names) {
          score = _max(score, _titleScore(query, name));
        }
        if (score == 0) continue;

        final hitYear = _year('${hit['year'] ?? hit['first_air_date'] ?? ''}');
        if (year != null && hitYear != null) {
          if ((hitYear - year).abs() > 2 && score < 40) continue;
          if (hitYear == year) {
            score += 25;
          } else if ((hitYear - year).abs() <= 1) {
            score += 8;
          }
        }
        if (score > bestScore) {
          bestScore = score;
          best = _info(hit, fallbackTitle: query);
        }
      }
      if (best == null || bestScore <= 0) return null;
      return best;
    } catch (_) {
      return null;
    }
  }

  static TvdbInfo _info(Map hit, {required String fallbackTitle}) {
    final overviews = hit['overviews'];
    var overview = overviews is Map ? '${overviews['eng'] ?? ''}'.trim() : '';
    if (overview.isEmpty && hit['overview_translated'] is List) {
      for (final row in hit['overview_translated'] as List) {
        final text = '$row';
        if (text.startsWith('eng:')) {
          overview = text.substring(4).trim();
          break;
        }
      }
    }
    String? firstString(List<String> keys) {
      for (final key in keys) {
        final value = '${hit[key] ?? ''}'.trim();
        if (value.isNotEmpty && value != 'null') return value;
      }
      return null;
    }

    String? tmdbId;
    String? imdbId;
    final remote = hit['remote_ids'];
    if (remote is List) {
      for (final row in remote) {
        if (row is! Map) continue;
        final source = '${row['sourceName'] ?? ''}'.toLowerCase();
        final id = '${row['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        if (source.contains('moviedb') && tmdbId == null && id.length <= 8) {
          tmdbId = id;
        }
        if (source == 'imdb' && imdbId == null && id.startsWith('tt')) {
          imdbId = id;
        }
      }
    }

    return TvdbInfo(
      title: firstString(['name']) ?? fallbackTitle,
      poster: firstString(['poster', 'image_url', 'image']),
      banner: firstString(['banner']),
      overview: overview.isEmpty ? null : overview,
      year: _year('${hit['year'] ?? hit['first_air_date'] ?? ''}'),
      tmdbId: tmdbId,
      imdbId: imdbId,
    );
  }

  static int _titleScore(String query, String candidate) {
    final a = _norm(query);
    final b = _norm(candidate);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 100;
    if (b.startsWith(a) || a.startsWith(b)) return 70;
    if (b.contains(a) || a.contains(b)) return 45;
    return 0;
  }

  static String _norm(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff]+'), ' ')
      .trim();

  static int? _year(String value) {
    final match = RegExp(r'(\d{4})').firstMatch(value);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static int _max(int a, int b) => a > b ? a : b;

  static void clearCache() => _cache.clear();
}
