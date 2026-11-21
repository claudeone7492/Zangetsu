import 'package:dio/dio.dart';

/// One episode on Bangumi's absolute numbering.
class BangumiEpisode {
  const BangumiEpisode({required this.number, this.name, this.airDate});

  final int number;
  final String? name;
  final String? airDate;
}

/// Anime episode titles from Bangumi.
///
/// TMDB leaves many anime episodes with a generic "Episode 12", and AniZip
/// only covers the part of a long show its editors reached. Bangumi numbers
/// every episode of the subject, so it fills the gaps with the real title and
/// air date. Best-effort: a miss returns null and never throws.
class Bangumi {
  Bangumi(this._dio, {String base = 'https://api.bgm.tv'}) : _base = base;

  final Dio _dio;
  final String _base;

  static const String userAgent =
      'Zangetsu/1.0 (Android; +https://github.com/claudeone7492/Zangetsu)';

  static final Map<String, List<BangumiEpisode>> _cache = {};

  /// Movies and specials carry their own 1..n numbering on Bangumi and would
  /// collide with the series episodes if merged.
  static final RegExp _notMain = RegExp(
    '剧场版|劇場版|特别篇|特別篇|特典|番外|Q版|小剧场|小劇場|合集|总集|预告|花絮|声优|聲優|舞台|广播剧|写真',
  );

  static final RegExp _generic = RegExp(
    r'^(episode|ep|e)?[\s._-]*\d+$|^第\s*\d+\s*[集話话]$',
    caseSensitive: false,
  );

  static bool isGenericName(String? name) {
    final value = name?.trim() ?? '';
    return value.isEmpty || _generic.hasMatch(value);
  }

  Future<List<BangumiEpisode>?> episodes({
    required String title,
    String? originalTitle,
    int? year,
  }) async {
    final native = (originalTitle ?? '').trim();
    final base = native.isNotEmpty ? native : title.trim();
    if (base.isEmpty) return null;
    final key = '$base|${year ?? 0}';
    final hit = _cache[key];
    if (hit != null) return hit;

    try {
      final search = await _dio.post<Map<String, dynamic>>(
        '$_base/v0/search/subjects',
        data: {
          'keyword': base,
          'filter': {
            'type': [2],
          },
        },
        options: Options(
          headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if ((search.statusCode ?? 0) >= 400) return null;
      final rows = search.data?['data'];
      if (rows is! List) return null;

      final candidates = <Map<String, dynamic>>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final name = '${row['name'] ?? ''}'.trim();
        final nameCn = '${row['name_cn'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        if (_notMain.hasMatch(name) || _notMain.hasMatch(nameCn)) continue;
        final date = '${row['date'] ?? ''}';
        final rowYear = int.tryParse(date.length >= 4 ? date.substring(0, 4) : '');
        if (year != null && rowYear != null && (rowYear - year).abs() > 1) {
          continue;
        }
        candidates.add(Map<String, dynamic>.from(row));
      }
      if (candidates.isEmpty) return null;
      candidates.sort(
        (a, b) => '${a['date'] ?? '9999'}'.compareTo('${b['date'] ?? '9999'}'),
      );

      final out = <int, BangumiEpisode>{};
      for (final candidate in candidates.take(3)) {
        final id = candidate['id'];
        if (id is! int || id <= 0) continue;
        final episodes = await _subjectEpisodes(id);
        if (episodes.isEmpty) continue;
        for (final episode in episodes) {
          out.putIfAbsent(episode.number, () => episode);
        }
        if (out.isNotEmpty) break;
      }
      if (out.isEmpty) return null;
      final list = out.values.toList()
        ..sort((a, b) => a.number.compareTo(b.number));
      _cache[key] = list;
      return list;
    } catch (_) {
      return null;
    }
  }

  Future<List<BangumiEpisode>> _subjectEpisodes(int subjectId) async {
    final out = <BangumiEpisode>[];
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '$_base/v0/episodes',
        queryParameters: {
          'subject_id': subjectId,
          'limit': 100,
          'offset': 0,
        },
        options: Options(
          headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if ((response.statusCode ?? 0) >= 400) return out;
      final rows = response.data?['data'];
      if (rows is! List) return out;
      for (final row in rows) {
        if (row is! Map) continue;
        final sort = row['sort'];
        final number = sort is int && sort > 0 ? sort : row['ep'];
        if (number is! int || number <= 0) continue;
        final cn = '${row['name_cn'] ?? ''}'.trim();
        final en = '${row['name'] ?? ''}'.trim();
        final name = cn.isNotEmpty ? cn : (en.isNotEmpty ? en : null);
        final air = '${row['airdate'] ?? ''}'.trim();
        out.add(
          BangumiEpisode(
            number: number,
            name: name,
            airDate: air.length == 10 ? air : null,
          ),
        );
      }
    } catch (_) {
      return out;
    }
    return out;
  }

  static void clearCache() => _cache.clear();
}
