import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitlecat_source.dart';

const _searchHtml = '''
<table>
  <tr>
    <td><a href="subs/1/Avatar%202024%201080p.html">Avatar.2024.1080p</a></td>
    <td class="sub-table__metric">
      <span class="sub-table__metric-label">Size</span>
      <span class="sub-table__metric-value">119 KB</span>
    </td>
    <td class="sub-table__metric">
      <span class="sub-table__metric-label">Downloads</span>
      <span class="sub-table__metric-value">150<span class="sub-table__metric-unit"> downloads</span></span>
    </td>
  </tr>
  <tr>
    <td><a href="subs/2/Avatar%202024%20720p.html">Avatar.2024.720p</a></td>
    <td class="sub-table__metric">
      <span class="sub-table__metric-label">Downloads</span>
      <span class="sub-table__metric-value">20<span class="sub-table__metric-unit"> downloads</span></span>
    </td>
  </tr>
  <tr>
    <td><a href="subs/1/Avatar%202024%201080p.html">duplicate</a></td>
    <td class="sub-table__metric">
      <span class="sub-table__metric-label">Downloads</span>
      <span class="sub-table__metric-value">5</span>
    </td>
  </tr>
</table>
''';

const _releaseHtml = '''
<div>
  <a id="download_en" href="/subs/9/Avatar (2024)-en.srt">English</a>
  <a id="download_fr" href="/subs/9/Avatar (2024)-fr.srt">French</a>
  <a id="download_es" href="/subs/9/Avatar (2024)-es.ass">Spanish</a>
  <a id="download_de" href="/subs/9/Avatar (2024)-de.zip">German</a>
</div>
''';

void main() {
  group('parseReleases', () {
    test('dedupes by href and sorts by downloads', () {
      final releases = SubtitleCatSource.parseReleases(_searchHtml);
      expect(releases, hasLength(2));
      expect(releases.first.href, 'subs/1/Avatar%202024%201080p.html');
      expect(releases.first.name, 'Avatar.2024.1080p');
      expect(releases.first.downloads, 150);
      expect(releases.last.downloads, 20);
    });
  });

  group('parseDownloads', () {
    test('keeps srt/ass, skips archives, and resolves links', () {
      const release = SubtitleCatRelease(
        href: 'subs/1/Avatar%202024%201080p.html',
        name: 'Avatar.2024.1080p',
        downloads: 150,
      );
      final hits = SubtitleCatSource.parseDownloads(
        _releaseHtml,
        release: release,
      );

      expect(hits.map((h) => h.language), ['en', 'fr', 'es']);
      expect(hits.first.format, 'srt');
      expect(hits.last.format, 'ass');
      expect(
        hits.first.url,
        'https://subtitlecat.com/subs/9/Avatar%20(2024)-en.srt',
      );
      expect(
        hits.first.referer,
        'https://subtitlecat.com/subs/1/Avatar%202024%201080p.html',
      );
      expect(hits.first.label, 'Avatar.2024.1080p');
    });
  });

  test('resolveUrl encodes spaces but keeps existing percent escapes', () {
    expect(
      SubtitleCatSource.resolveUrl(
        'https://subtitlecat.com',
        '/subs/9/Avatar (2024)-en.srt',
      ),
      'https://subtitlecat.com/subs/9/Avatar%20(2024)-en.srt',
    );
    expect(
      SubtitleCatSource.resolveUrl(
        'https://subtitlecat.com',
        'subs/1/Avatar%202024.html',
      ),
      'https://subtitlecat.com/subs/1/Avatar%202024.html',
    );
  });
}
