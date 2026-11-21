import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/rating_aggregator.dart';

void main() {
  test('normalises different scales', () {
    expect(const Rating(source: RatingSource.imdb, score: 8).normalized, 0.8);
    expect(const Rating(source: RatingSource.rottenTomatoes, score: 80, max: 100).normalized, 0.8);
  });

  test('averages to a ten point score', () {
    final value = RatingAggregator.average([
      const Rating(source: RatingSource.imdb, score: 8),
      const Rating(source: RatingSource.tmdb, score: 8),
    ]);
    expect(value, closeTo(8, 0.01));
  });

  test('returns null with no ratings', () {
    expect(RatingAggregator.average(const []), isNull);
  });

  test('picks the primary source per kind', () {
    expect(RatingAggregator.primaryFor('anime'), RatingSource.mal);
    expect(RatingAggregator.primaryFor('movie'), RatingSource.imdb);
  });
}
