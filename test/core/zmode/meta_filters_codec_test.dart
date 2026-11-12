// Filters travel as an opaque string through the search bloc's existing
// per-source filter channel, so the codec is load-bearing: a bad round trip
// silently drops what the user picked.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/zmode/metadata_filters.dart';

void main() {
  test('a full selection survives the round trip', () {
    const f = MetaFilters(
      genres: ['Action', 'Comedy'],
      genreMatch: MetaGenreMatch.all,
      yearFrom: 2021,
      yearTo: 2021,
      season: MetaSeason.fall,
      format: MetaFormat.movie,
      status: MetaStatus.finished,
      minScore: 75,
      minVotes: 500,
      runtimeMin: 90,
      runtimeMax: 150,
      originCountry: 'US',
      originalLanguage: 'en',
      excludedGenres: ['Horror'],
      excludeOriginalLanguages: 'yo',
      certifications: ['PG-13'],
      certificationCountry: 'US',
      watchProviders: [8, 337],
      watchRegion: 'US',
      tvNetworks: [213],
      tvStatuses: [0],
      tvTypes: [4],
      sort: MetaSort.score,
    );

    final back = MetaFilters.fromJson(f.toJson())!;

    expect(back.genres, ['Action', 'Comedy']);
    expect(back.genreMatch, MetaGenreMatch.all);
    expect(back.year, 2021);
    expect(back.season, MetaSeason.fall);
    expect(back.format, MetaFormat.movie);
    expect(back.status, MetaStatus.finished);
    expect(back.minScore, 75);
    expect(back.minVotes, 500);
    expect(back.runtimeMin, 90);
    expect(back.runtimeMax, 150);
    expect(back.originCountry, 'US');
    expect(back.originalLanguage, 'en');
    expect(back.excludedGenres, ['Horror']);
    expect(back.excludeOriginalLanguages, 'yo');
    expect(back.certifications, ['PG-13']);
    expect(back.certificationCountry, 'US');
    expect(back.watchProviders, [8, 337]);
    expect(back.watchRegion, 'US');
    expect(back.tvNetworks, [213]);
    expect(back.tvStatuses, [0]);
    expect(back.tvTypes, [4]);
    expect(back.sort, MetaSort.score);
  });

  test('an empty selection reads as empty', () {
    const f = MetaFilters();
    expect(f.isEmpty, isTrue);
    // Round-tripping must not invent a filter out of the default sort.
    expect(MetaFilters.fromJson(f.toJson())!.isEmpty, isTrue);
  });

  test('junk decodes to no filters rather than throwing', () {
    // The string is persisted alongside search state, so a build that changes
    // the shape must degrade to an unfiltered search, not crash on open.
    expect(MetaFilters.fromJson('not json'), isNull);
    expect(MetaFilters.fromJson(''), isNull);
    expect(MetaFilters.fromJson(null), isNull);
    expect(MetaFilters.fromJson('{"s":"nonexistent_season"}')?.season, isNull);
  });
}
