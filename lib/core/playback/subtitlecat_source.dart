import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' show Element;
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';

/// One release row on SubtitleCat's search page.
class SubtitleCatRelease {
  const SubtitleCatRelease({
    required this.href,
    required this.name,
    required this.downloads,
  });

  final String href;
  final String name;
  final int downloads;
}

/// One language file on a SubtitleCat release page.
class SubtitleCatHit {
  const SubtitleCatHit({
    required this.label,
    required this.language,
    required this.format,
    required this.url,
    required this.referer,
    required this.downloads,
  });

  final String label;
  final String language;
  final String format;
  final String url;
  final String referer;
  final int downloads;
}

/// Keyless search against SubtitleCat's HTML pages.
///
/// The search page lists releases; each release page links one file per
/// language. Two pages are enough for a useful result set, so the top three
/// releases by download count are read and deduped by language — the same
/// behaviour as Hikari's provider.
class SubtitleCatSource {
  SubtitleCatSource({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 10),
              headers: const {'User-Agent': _userAgent},
            ),
          );

  final Dio _dio;

  static const String _base = 'https://subtitlecat.com';
  static const String _userAgent =
      'Mozilla/5.0 (compatible; Zangetsu/1.0)';

  Future<List<SubtitleCatHit>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final searchBody = await _get(
      '$_base/index.php?search=${Uri.encodeQueryComponent(q)}',
    );
    if (searchBody == null) return const [];

    final releases = parseReleases(searchBody).take(3).toList();
    // The three release pages are independent; fetching them in parallel keeps
    // a slow page from adding its full timeout to the search.
    final pages = await Future.wait(
      releases.map((release) => _get(resolveUrl(_base, release.href))),
    );
    final out = <SubtitleCatHit>[];
    for (var i = 0; i < releases.length; i++) {
      final page = pages[i];
      if (page == null) continue;
      out.addAll(parseDownloads(page, release: releases[i]));
    }

    out.sort((a, b) => b.downloads.compareTo(a.downloads));
    final seen = <String>{};
    return [
      for (final hit in out)
        if (seen.add(hit.language)) hit,
    ].take(60).toList();
  }

  Future<String?> _get(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      return response.data;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static List<SubtitleCatRelease> parseReleases(String body) {
    final doc = html_parser.parse(body);
    final out = <SubtitleCatRelease>[];
    for (final row in doc.querySelectorAll('tr')) {
      final anchor = row.querySelector('a[href^="subs/"]');
      if (anchor == null) continue;
      final href = (anchor.attributes['href'] ?? '').trim();
      if (href.isEmpty) continue;
      out.add(
        SubtitleCatRelease(
          href: href,
          name: anchor.text.trim(),
          downloads: _downloads(row),
        ),
      );
    }
    final seen = <String>{};
    final distinct = [
      for (final release in out)
        if (seen.add(release.href)) release,
    ];
    distinct.sort((a, b) => b.downloads.compareTo(a.downloads));
    return distinct;
  }

  /// A row carries three metrics (size, downloads, languages) with the same
  /// value class, so the label has to pick the right one.
  static int _downloads(Element row) {
    for (final metric in row.querySelectorAll('.sub-table__metric')) {
      final label =
          metric.querySelector('.sub-table__metric-label')?.text.toLowerCase() ??
          '';
      if (!label.contains('download')) continue;
      final value = metric.querySelector('.sub-table__metric-value')?.text ?? '';
      final digits = RegExp(r'\d+').firstMatch(value)?.group(0);
      return digits == null ? 0 : int.parse(digits);
    }
    return 0;
  }

  @visibleForTesting
  static List<SubtitleCatHit> parseDownloads(
    String body, {
    required SubtitleCatRelease release,
  }) {
    final doc = html_parser.parse(body);
    final referer = resolveUrl(_base, release.href);
    final out = <SubtitleCatHit>[];
    for (final anchor in doc.querySelectorAll('a[id^="download_"]')) {
      final id = anchor.attributes['id'] ?? '';
      final href = (anchor.attributes['href'] ?? '').trim();
      final code = id.substring('download_'.length).trim();
      if (code.isEmpty || href.isEmpty) continue;
      final lower = href.toLowerCase();
      if (!lower.contains('.srt') && !lower.contains('.ass')) continue;
      out.add(
        SubtitleCatHit(
          label: release.name,
          language: code,
          format: _extension(lower),
          url: resolveUrl(_base, href),
          referer: referer,
          downloads: release.downloads,
        ),
      );
    }
    return out;
  }

  /// Resolves a relative link without double-encoding the `%20` the search
  /// page already writes.
  static String resolveUrl(String base, String href) {
    final raw = href.startsWith('http')
        ? href
        : '$base/${href.replaceFirst(RegExp(r'^/+'), '')}';
    return Uri.parse(raw).toString();
  }

  static String _extension(String lowerUrl) =>
      lowerUrl.contains('.ass') ? 'ass' : 'srt';

  Future<String?> download(SubtitleCatHit hit) async {
    final response = await _dio.get<List<int>>(
      hit.url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Referer': hit.referer},
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) return null;
    final dir = await getTemporaryDirectory();
    final lang = hit.language.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(
      '${dir.path}/subtitlecat_${lang}_${hit.url.hashCode}.${hit.format}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
