import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A keyless hit from the OpenSubtitles.org REST mirror.
class OpenSubtitlesOrgHit {
  const OpenSubtitlesOrgHit({
    required this.fileId,
    required this.label,
    required this.language,
    required this.format,
    required this.downloadUrl,
  });

  final String fileId;
  final String label;

  /// ISO-639-1 when the mirror supplies it (`en`), else its `SubLanguageID`
  /// (`eng`) or the English language name.
  final String language;

  final String format;
  final String downloadUrl;
}

/// Keyless search against the OpenSubtitles.org REST mirror.
///
/// The `.com` API needs a free key; this endpoint does not, so a fresh install
/// can still find captions. Search is by IMDb id when one is known, otherwise
/// by title. Downloads go through Stremio's UTF-8 SRT mirror, which returns
/// plain text rather than the original archive.
class OpenSubtitlesOrgSource {
  OpenSubtitlesOrgSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: const {'User-Agent': _userAgent},
            ),
          );

  final Dio _dio;

  static const String _base = 'https://rest.opensubtitles.org';
  static const String _files =
      'https://subs5.strem.io/en/download/subencoding-stremio-utf8/src-api/file/';
  static const String _userAgent = 'Zangetsu v1.0.0';

  /// The `/search/<criteria>` path, or '' when there is nothing to search.
  ///
  /// Series criteria go first; the mirror redirects any order to the same
  /// canonical URL. An IMDb id wins over a title because it cannot collide with
  /// a remake.
  static String criteria({
    String? query,
    String? imdbId,
    int? season,
    int? episode,
  }) {
    final parts = <String>[];
    if (season != null && season > 0 && episode != null && episode > 0) {
      parts.add('episode-$episode');
      parts.add('season-$season');
    }
    final imdb = (imdbId ?? '').trim();
    if (imdb.startsWith('tt')) {
      parts.add('imdbid-${imdb.substring(2)}');
    } else if (imdb.isNotEmpty) {
      parts.add('imdbid-$imdb');
    } else {
      final q = (query ?? '').trim();
      if (q.length < 2) return '';
      parts.add('query-${Uri.encodeComponent(q)}');
    }
    return parts.join('/');
  }

  Future<List<OpenSubtitlesOrgHit>> search({
    String? query,
    String? imdbId,
    int? season,
    int? episode,
  }) async {
    final path = criteria(
      query: query,
      imdbId: imdbId,
      season: season,
      episode: episode,
    );
    if (path.isEmpty) return const [];
    final response = await _dio.get<dynamic>(
      '$_base/search/$path',
      options: Options(
        responseType: ResponseType.json,
        headers: const {'Accept': 'application/json'},
      ),
    );
    final data = response.data;
    if (data is! List) return const [];
    return parseRows(data);
  }

  @visibleForTesting
  static List<OpenSubtitlesOrgHit> parseRows(List<dynamic> rows) {
    final out = <OpenSubtitlesOrgHit>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      if ('${raw['SubBad'] ?? ''}'.trim() == '1') continue;
      final id = '${raw['IDSubtitleFile'] ?? ''}'.trim();
      if (id.isEmpty || id == '0') continue;
      final fileName = '${raw['SubFileName'] ?? ''}'.trim();
      final release = '${raw['MovieReleaseName'] ?? ''}'.trim();
      final code = '${raw['ISO639'] ?? ''}'.trim();
      final subLang = '${raw['SubLanguageID'] ?? ''}'.trim();
      final langName = '${raw['LanguageName'] ?? ''}'.trim();
      final format = '${raw['SubFormat'] ?? ''}'.trim();
      out.add(
        OpenSubtitlesOrgHit(
          fileId: id,
          label: fileName.isNotEmpty ? fileName : release,
          language: code.isNotEmpty
              ? code
              : (subLang.isNotEmpty ? subLang : langName),
          format: format.isNotEmpty ? format : _extension(fileName),
          downloadUrl: '$_files$id',
        ),
      );
    }
    return out;
  }

  Future<String?> download(OpenSubtitlesOrgHit hit) async {
    final response = await _dio.get<List<int>>(
      hit.downloadUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final ext = hit.format.isEmpty ? 'srt' : hit.format.toLowerCase();
    final file = File('${dir.path}/os_org_${hit.fileId}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static String _extension(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'srt';
    return name.substring(dot + 1).toLowerCase();
  }
}
