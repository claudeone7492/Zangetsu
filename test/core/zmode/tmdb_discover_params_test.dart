// The filter→TMDB mapping is the whole point of the ported filter set: a
// wrong separator or a dropped param silently returns the wrong catalogue
// rather than an error, so each rule is pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/zmode/metadata_filters.dart';

void main() {
  group('genres', () {
    test('any-of joins with a pipe', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(genres: ['Action', 'Comedy']),
        isTv: false,
      );
      expect(p['with_genres'], '28|35');
    });

    test('all-of joins with a comma', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(
          genres: ['Action', 'Comedy'],
          genreMatch: MetaGenreMatch.all,
        ),
        isTv: false,
      );
      expect(p['with_genres'], '28,35');
    });

    test('a genre with no id on this side is dropped, not sent wrong', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(genres: ['Horror', 'Science Fiction']),
        isTv: true,
      );
      // Horror has no TV id; only Science Fiction's 10765 survives.
      expect(p['with_genres'], '10765');
    });

    test('exclusions always join with the all-separator', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(excludedGenres: ['Horror', 'Thriller']),
        isTv: false,
      );
      expect(p['without_genres'], '27,53');
    });
  });

  group('year', () {
    test('a range maps to gte/lte dates', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(yearFrom: 1990, yearTo: 1999),
        isTv: false,
      );
      expect(p['primary_release_date.gte'], '1990-01-01');
      expect(p['primary_release_date.lte'], '1999-12-31');
    });

    test('TV uses first_air_date', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(yearFrom: 2010, yearTo: 2010),
        isTv: true,
      );
      expect(p['first_air_date.gte'], '2010-01-01');
      expect(p['first_air_date.lte'], '2010-12-31');
    });

    test('newest-first with no end date caps at today', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(sort: MetaSort.newest),
        isTv: false,
      );
      expect(p['primary_release_date.lte'], isNotNull);
    });
  });

  group('rating and votes', () {
    test('minScore divides into TMDB\'s 10-point scale', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(minScore: 70),
        isTv: false,
      );
      expect(p['vote_average.gte'], 7.0);
    });

    test('rating sort gets a vote floor so one-vote titles do not top it', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(sort: MetaSort.score),
        isTv: false,
      );
      expect(p['vote_count.gte'], 200);
    });

    test('an explicit minVotes overrides the sort floor', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(sort: MetaSort.score, minVotes: 5000),
        isTv: false,
      );
      expect(p['vote_count.gte'], 5000);
    });

    test('no rating filter means no vote floor', () {
      final p = tmdbDiscoverParams(const MetaFilters(), isTv: false);
      expect(p.containsKey('vote_count.gte'), isFalse);
    });
  });

  group('runtime, country and language', () {
    test('runtime range maps to gte/lte', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(runtimeMin: 90, runtimeMax: 180),
        isTv: false,
      );
      expect(p['with_runtime.gte'], 90);
      expect(p['with_runtime.lte'], 180);
    });

    test('origin country passes through as a pipe-joined list', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(originCountry: 'NG|GH'),
        isTv: false,
      );
      expect(p['with_origin_country'], 'NG|GH');
    });

    test('original language passes through as with_original_language', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(originalLanguage: 'en'),
        isTv: false,
      );
      expect(p['with_original_language'], 'en');
    });
  });

  group('watch providers', () {
    test('providers only ride along with a region', () {
      final noRegion = tmdbDiscoverParams(
        const MetaFilters(watchProviders: [8]),
        isTv: false,
      );
      expect(noRegion.containsKey('with_watch_providers'), isFalse);

      final p = tmdbDiscoverParams(
        const MetaFilters(watchProviders: [8, 337], watchRegion: 'US'),
        isTv: false,
      );
      expect(p['with_watch_providers'], '8|337');
      expect(p['watch_region'], 'US');
    });

    test('a browse-service override pins the provider', () {
      final p = tmdbDiscoverParams(
        const MetaFilters(watchProviders: [8]),
        isTv: true,
        watchProviderOverride: '15',
        watchRegion: 'GB',
      );
      expect(p['with_watch_providers'], '15');
      expect(p['watch_region'], 'GB');
    });
  });

  group('TV-only and movie-only filters', () {
    test('networks, status and type are TV-only', () {
      final tv = tmdbDiscoverParams(
        const MetaFilters(tvNetworks: [213], tvStatuses: [0, 3], tvTypes: [4]),
        isTv: true,
      );
      expect(tv['with_networks'], '213');
      expect(tv['with_status'], '0|3');
      expect(tv['with_type'], '4');

      final movie = tmdbDiscoverParams(
        const MetaFilters(tvNetworks: [213]),
        isTv: false,
      );
      expect(movie.containsKey('with_networks'), isFalse);
    });

    test('certifications are movie-only and AND-joined', () {
      final movie = tmdbDiscoverParams(
        const MetaFilters(
          certifications: ['PG-13', 'R'],
          certificationCountry: 'US',
        ),
        isTv: false,
      );
      // `|` is ignored by TMDB here and returns the whole catalogue.
      expect(movie['certification'], 'PG-13,R');
      expect(movie['certification_country'], 'US');

      final tv = tmdbDiscoverParams(
        const MetaFilters(
          certifications: ['TV-14'],
          certificationCountry: 'US',
        ),
        isTv: true,
      );
      expect(tv.containsKey('certification'), isFalse);
    });
  });

  group('search-year mapping', () {
    test('a single year maps to the search year param', () {
      expect(
        tmdbSearchYear(const MetaFilters(yearFrom: 2023, yearTo: 2023)),
        2023,
      );
    });

    test('a range does not', () {
      expect(
        tmdbSearchYear(const MetaFilters(yearFrom: 2010, yearTo: 2020)),
        isNull,
      );
    });
  });

  group('local result matching', () {
    bool matches(
      MetaFilters f, {
      List<int> genres = const [18],
      String? language = 'en',
    }) => tmdbItemMatchesFilters(
      f,
      isTv: false,
      genreIds: genres,
      year: 2023,
      voteAverage: 7.5,
      voteCount: 500,
      language: language,
    );

    test('genre, rating and vote filters are enforced', () {
      expect(matches(const MetaFilters(genres: ['Drama'])), isTrue);
      expect(matches(const MetaFilters(genres: ['Action'])), isFalse);
      expect(matches(const MetaFilters(minScore: 80)), isFalse);
      expect(matches(const MetaFilters(minVotes: 1000)), isFalse);
      expect(matches(const MetaFilters(excludedGenres: ['Drama'])), isFalse);
    });

    test('all-of genres need every one present', () {
      const both = MetaFilters(
        genres: ['Drama', 'Action'],
        genreMatch: MetaGenreMatch.all,
      );
      expect(matches(both, genres: [18, 28]), isTrue);
      expect(matches(both, genres: [18]), isFalse);
    });

    test('an original-language filter must match', () {
      expect(matches(const MetaFilters(originalLanguage: 'en')), isTrue);
      expect(matches(const MetaFilters(originalLanguage: 'yo')), isFalse);
      expect(matches(const MetaFilters(originalLanguage: 'en|yo')), isTrue);
    });

    test('language exclusion drops a match', () {
      expect(
        matches(const MetaFilters(excludeOriginalLanguages: 'en|yo')),
        isFalse,
      );
      expect(
        matches(const MetaFilters(excludeOriginalLanguages: 'yo')),
        isTrue,
      );
    });

    test('a year outside the range is dropped', () {
      expect(matches(const MetaFilters(yearFrom: 2020, yearTo: 2022)), isFalse);
      expect(matches(const MetaFilters(yearFrom: 2023, yearTo: 2024)), isTrue);
    });
  });
}
