enum RatingSource { imdb, rottenTomatoes, metacritic, letterboxd, tmdb, anilist, mal, mangabaka }

class Rating {
  const Rating({required this.source, required this.score, this.max = 10});
  final RatingSource source;

  /// Score on the source's own scale; [max] says what the top is.
  final double score;
  final double max;

  double get normalized => max <= 0 ? 0 : (score / max).clamp(0, 1);
}

/// Blends scores from several sites into one 0–10 value.
///
/// Hikari's `Ratings.kt` keeps each site's own score and lets the UI pick.
/// This keeps the per-site values and adds a weighted mean so a detail page
/// can show one number without inventing one.
class RatingAggregator {
  const RatingAggregator._();

  static const Map<RatingSource, double> weights = {
    RatingSource.imdb: 1.4,
    RatingSource.rottenTomatoes: 1.2,
    RatingSource.metacritic: 1.1,
    RatingSource.letterboxd: 1.0,
    RatingSource.tmdb: 0.8,
    RatingSource.anilist: 1.0,
    RatingSource.mal: 1.0,
    RatingSource.mangabaka: 0.8,
  };

  static double? average(List<Rating> ratings) {
    if (ratings.isEmpty) return null;
    var weight = 0.0;
    var sum = 0.0;
    for (final rating in ratings) {
      final w = weights[rating.source] ?? 1.0;
      sum += rating.normalized * w;
      weight += w;
    }
    return weight == 0 ? null : (sum / weight) * 10;
  }

  /// The site the UI should quote for a given media kind.
  static RatingSource? primaryFor(String kind) => switch (kind) {
    'anime' => RatingSource.mal,
    'manga' => RatingSource.mangabaka,
    _ => RatingSource.imdb,
  };
}
