/// Stats engine (gap E1): turns the history stores we already keep into the
/// watch/read figures Hikari's StatsScreen shows, with no new backend and no
/// new dependency.
///
/// Everything here is pure Dart over plain value objects — it never touches
/// Hive, Supabase or the widget tree — so the aggregation is unit-testable and
/// the screen is a thin renderer. `StatsScreen` adapts [HistoryEntry] /
/// [ReadEntry] into [WatchStat] / [ReadStat] and calls [StatsSummary.from].
library;

/// One watched episode/title, reduced to the fields the stats need.
class WatchStat {
  const WatchStat({
    required this.showId,
    required this.title,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.category = '',
    this.episodeNumber,
    this.finished = false,
  });

  final String showId;
  final String title;
  final Duration position;
  final Duration duration;

  /// Epoch millis of the last update — the day a watch counts towards.
  final int updatedAt;

  /// Source category ("anime", "movie", …) — only used for the top-category rail.
  final String category;
  final double? episodeNumber;

  /// The store's own finished rule (>= 92% watched). Kept explicit rather than
  /// recomputed so the two can't drift apart.
  final bool finished;

  /// Time actually watched, capped at the episode length: a position past the
  /// duration (a seek, a mis-sized stream) must not inflate the totals.
  Duration get watched {
    if (duration <= Duration.zero) return position;
    return position > duration ? duration : position;
  }
}

/// One read title, reduced to what the stats need.
class ReadStat {
  const ReadStat({
    required this.title,
    required this.type,
    required this.pos,
    required this.total,
    required this.updatedAt,
    required this.finished,
  });

  final String title;

  /// "manga" or "novel".
  final String type;

  /// Progress counters, in the store's own units (pages for manga, permille for
  /// novels). Used only to count finished/started titles, never as time.
  final int pos;
  final int total;
  final int updatedAt;
  final bool finished;
}

/// Per-day bucket, keyed by local calendar day (midnight).
class DayBucket {
  DayBucket(this.day);

  final DateTime day;
  int watches = 0;
  int reads = 0;

  DateTime get key => DateTime(day.year, day.month, day.day);
}

/// The whole computed report the screen renders.
class StatsSummary {
  const StatsSummary({
    required this.watchTime,
    required this.readTime,
    required this.titlesWatched,
    required this.episodesWatched,
    required this.titlesRead,
    required this.chaptersRead,
    required this.streakDays,
    required this.activeDays,
    required this.last7,
    required this.last30,
    required this.topShows,
    required this.topCategories,
  });

  /// Estimated time spent watching / reading. Reading time is derived (see
  /// [StatsSummary.from]) because the stores record progress, not wall-clock.
  final Duration watchTime;
  final Duration readTime;

  final int titlesWatched;
  final int episodesWatched;
  final int titlesRead;
  final int chaptersRead;

  /// Consecutive days up to today (or yesterday) with at least one watch/read.
  final int streakDays;
  final int activeDays;

  /// Daily buckets for the last 7 / 30 calendar days, oldest first.
  final List<DayBucket> last7;
  final List<DayBucket> last30;

  /// Top shows by watched time, longest first.
  final List<TopShow> topShows;

  /// Top source categories by watched time.
  final List<({String category, Duration time})> topCategories;

  /// Minutes we credit a single reading session towards [readTime]. The stores
  /// keep a page/percent position, not a stopwatch, so this is an explicit
  /// estimate rather than a fake "exact" number.
  static const int readMinutesPerChapter = 4;

  static StatsSummary from(
    Iterable<WatchStat> watch,
    Iterable<ReadStat> read, {
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());
    final watchList = watch.toList(growable: false);
    final readList = read.toList(growable: false);

    var watchTime = Duration.zero;
    var readTime = Duration.zero;
    var episodesWatched = 0;
    final watchedShows = <String>{};
    final readTitles = <String>{};
    var chaptersRead = 0;
    final byShow = <String, _ShowAgg>{};
    final byCategory = <String, Duration>{};
    final dayMap = <DateTime, DayBucket>{};

    for (final w in watchList) {
      final d = w.watched;
      watchTime += d;
      if (w.finished) episodesWatched++;
      watchedShows.add(w.showId);
      final day = _bucket(dayMap, today, w.updatedAt);
      day.watches++;
      final agg = byShow.putIfAbsent(w.showId, () => _ShowAgg(w.showId, w.title));
      agg.time += d;
      agg.episodes++;
      if (w.category.isNotEmpty) {
        byCategory[w.category] = (byCategory[w.category] ?? Duration.zero) + d;
      }
    }

    for (final r in readList) {
      // Counted once per title, whether or not it is finished, and credited a
      // fixed reading session so the figure is stable rather than drifting with
      // a progress counter's units (pages vs permille).
      readTitles.add(r.title);
      chaptersRead += r.pos;
      readTime += Duration(minutes: readMinutesPerChapter);
      _bucket(dayMap, today, r.updatedAt).reads++;
    }

    final activeDays = dayMap.values
        .where((b) => b.watches > 0 || b.reads > 0)
        .length;

    final topShows = (byShow.values.toList()
          ..sort((a, b) => b.time.compareTo(a.time)))
        .map((a) => TopShow(showId: a.id, title: a.title, time: a.time, episodes: a.episodes))
        .toList(growable: false);

    final topCategories = (byCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .map((e) => (category: e.key, time: e.value))
        .toList(growable: false);

    return StatsSummary(
      watchTime: watchTime,
      readTime: readTime,
      titlesWatched: watchedShows.length,
      episodesWatched: episodesWatched,
      titlesRead: readTitles.length,
      chaptersRead: chaptersRead,
      streakDays: _streak(dayMap, today),
      activeDays: activeDays,
      last7: _window(dayMap, today, 7),
      last30: _window(dayMap, today, 30),
      topShows: topShows,
      topCategories: topCategories,
    );
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  static DayBucket _bucket(
    Map<DateTime, DayBucket> map,
    DateTime today,
    int updatedMs,
  ) {
    final raw = DateTime.fromMillisecondsSinceEpoch(updatedMs);
    final key = DateTime(raw.year, raw.month, raw.day);
    return map.putIfAbsent(key, () => DayBucket(key));
  }

  /// Consecutive days with activity, ending today or yesterday. A day with
  /// nothing watched/read breaks the run; yesterday still counts so the streak
  /// doesn't read 0 every morning before the first play.
  static int _streak(Map<DateTime, DayBucket> map, DateTime today) {
    var streak = 0;
    var cursor = today;
    if (!map.containsKey(cursor)) {
      cursor = today.subtract(const Duration(days: 1));
      if (!map.containsKey(cursor)) return 0;
    }
    while (map.containsKey(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// The last [days] calendar days, oldest first, with empty days present as
  /// zero buckets so the bar chart has a fixed-width axis.
  static List<DayBucket> _window(
    Map<DateTime, DayBucket> map,
    DateTime today,
    int days,
  ) {
    return List<DayBucket>.generate(days, (i) {
      final day = today.subtract(Duration(days: days - 1 - i));
      return map[day] ?? DayBucket(day);
    });
  }
}

class TopShow {
  const TopShow({
    required this.showId,
    required this.title,
    required this.time,
    required this.episodes,
  });

  final String showId;
  final String title;
  final Duration time;
  final int episodes;
}

class _ShowAgg {
  _ShowAgg(this.id, this.title);
  final String id;
  final String title;
  Duration time = Duration.zero;
  int episodes = 0;
}

/// Formats a [Duration] the way the stats page reads it: "3h 12m", "45m",
/// "12m". Never "0h 0m" — sub-minute reads as "<1m".
String formatStatDuration(Duration d) {
  final totalMinutes = d.inMinutes;
  if (totalMinutes < 1) return '<1m';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}
