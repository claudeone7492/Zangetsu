import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/opensubtitles_org_source.dart';

void main() {
  group('criteria', () {
    test('uses the IMDb id without the tt prefix', () {
      expect(
        OpenSubtitlesOrgSource.criteria(imdbId: 'tt0133093'),
        'imdbid-0133093',
      );
    });

    test('puts series criteria before the id', () {
      expect(
        OpenSubtitlesOrgSource.criteria(
          imdbId: 'tt0944947',
          season: 1,
          episode: 2,
        ),
        'episode-2/season-1/imdbid-0944947',
      );
    });

    test('falls back to the encoded title when there is no id', () {
      expect(
        OpenSubtitlesOrgSource.criteria(query: 'The Matrix'),
        'query-The%20Matrix',
      );
    });

    test('needs at least two characters of title', () {
      expect(OpenSubtitlesOrgSource.criteria(query: ' a '), '');
      expect(OpenSubtitlesOrgSource.criteria(), '');
    });
  });

  group('parseRows', () {
    test('skips bad and id-less rows', () {
      final hits = OpenSubtitlesOrgSource.parseRows([
        {'SubBad': '1', 'IDSubtitleFile': '10'},
        {'IDSubtitleFile': '0'},
        {'IDSubtitleFile': ''},
        'not a map',
      ]);
      expect(hits, isEmpty);
    });

    test('maps the file name, language and download url', () {
      final hits = OpenSubtitlesOrgSource.parseRows([
        {
          'IDSubtitleFile': '1955468734',
          'SubFileName': 'Movie.2024.en.srt',
          'MovieReleaseName': 'Movie.2024.1080p',
          'ISO639': 'en',
          'SubLanguageID': 'eng',
          'LanguageName': 'English',
          'SubFormat': 'srt',
        },
        {
          'IDSubtitleFile': '42',
          'SubFileName': 'Other.2024.fr.srt',
          'MovieReleaseName': 'Other.2024.720p',
          'ISO639': '',
          'SubLanguageID': 'fre',
          'LanguageName': 'French',
          'SubFormat': '',
        },
      ]);

      expect(hits, hasLength(2));
      expect(hits.first.label, 'Movie.2024.en.srt');
      expect(hits.first.language, 'en');
      expect(hits.first.format, 'srt');
      expect(
        hits.first.downloadUrl,
        'https://subs5.strem.io/en/download/subencoding-stremio-utf8/src-api/file/1955468734',
      );

      // No ISO639: fall back to SubLanguageID, and derive the format from the
      // file name when SubFormat is blank.
      expect(hits.last.language, 'fre');
      expect(hits.last.format, 'srt');
    });

    test('normalises a non-text format to srt', () {
      final hits = OpenSubtitlesOrgSource.parseRows([
        {
          'IDSubtitleFile': '9',
          'SubFileName': 'Movie.spa.sub',
          'SubFormat': 'sub',
          'ISO639': 'es',
        },
      ]);
      expect(hits.single.format, 'srt');
    });

    test('falls back to the release name when the file name is blank', () {
      final hits = OpenSubtitlesOrgSource.parseRows([
        {
          'IDSubtitleFile': '7',
          'SubFileName': '',
          'MovieReleaseName': 'Release.2024',
          'ISO639': 'de',
        },
      ]);
      expect(hits.single.label, 'Release.2024');
    });
  });
}
