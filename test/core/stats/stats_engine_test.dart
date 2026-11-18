import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/stats/stats_engine.dart';

WatchStat _w(
  String id, {
  Duration pos = const Duration(minutes: 20),
  Duration dur = const Duration(minutes: 24),
  int daysAgo = 0,
  String category = 'anime',
  bool finished = false,
}) => WatchStat(
  showId: id,
  title: 'Show $id',
  position: pos,
  duration: dur,
  updatedAt: DateTime(2026, 1, 10, 12)
      .subtract(Duration(days: daysAgo))
      .millisecondsSinceEpoch,
  category: category,
  finished: finished,
);

ReadStat _r(String title, {int pos = 10, int daysAgo = 0}) => ReadStat(
  title: title,
  type: 'manga',
  pos: pos,
  total: 100,
  updatedAt: DateTime(2026, 1, 10, 12)
      .subtract(Duration(days: daysAgo))
      .millisecondsSinceEpoch,
  finished: pos >= 99,
);

void main() {
  final now = DateTime(2026, 1, 10, 23);

  group('StatsSummary', () {
    test('sums watched time and caps it at the episode length', () {
      final s = StatsSummary.from([
        _w('a', pos: const Duration(minutes: 10), dur: const Duration(minutes: 24)),
        // Position past the duration must not inflate the total.
        _w('b', pos: const Duration(minutes: 40), dur: const Duration(minutes: 24)),
      ], const [], now: now);
      expect(s.watchTime, const Duration(minutes: 34));
    });

    test('counts distinct titles, finished episodes and reads', () {
      final s = StatsSummary.from([
        _w('a', finished: true),
        _w('a', finished: true),
        _w('b', finished: false),
      ], [
        _r('M1', pos: 12),
        _r('M2', pos: 3),
      ], now: now);
      expect(s.titlesWatched, 2);
      expect(s.episodesWatched, 2);
      expect(s.titlesRead, 2);
      expect(s.chaptersRead, 15);
    });

    test('derives reading time from the session estimate', () {
      final s = StatsSummary.from([], [_r('M1'), _r('M2')], now: now);
      expect(
        s.readTime,
        const Duration(minutes: StatsSummary.readMinutesPerChapter * 2),
      );
    });

    test('streak counts consecutive days up to today', () {
      final s = StatsSummary.from([
        _w('a', daysAgo: 0),
        _w('a', daysAgo: 1),
        _w('a', daysAgo: 2),
        // gap at day 3
        _w('a', daysAgo: 4),
      ], const [], now: now);
      expect(s.streakDays, 3);
    });

    test('streak still counts when the newest activity is yesterday', () {
      final s = StatsSummary.from([
        _w('a', daysAgo: 1),
        _w('a', daysAgo: 2),
      ], const [], now: now);
      expect(s.streakDays, 2);
    });

    test('streak is zero when nothing happened today or yesterday', () {
      final s = StatsSummary.from([_w('a', daysAgo: 5)], const [], now: now);
      expect(s.streakDays, 0);
    });

    test('windows are fixed-width, oldest first, with empty days as zeros', () {
      final s = StatsSummary.from([_w('a', daysAgo: 0)], const [], now: now);
      expect(s.last7.length, 7);
      expect(s.last30.length, 30);
      expect(s.last7.last.day, DateTime(2026, 1, 10));
      expect(s.last7.last.watches, 1);
      expect(s.last7.first.watches, 0);
    });

    test('ranks top shows by watched time and categories by total', () {
      final s = StatsSummary.from([
        _w('a', pos: const Duration(minutes: 5), dur: const Duration(minutes: 24), category: 'anime'),
        _w('b', pos: const Duration(minutes: 20), dur: const Duration(minutes: 24), category: 'movie'),
        _w('b', pos: const Duration(minutes: 20), dur: const Duration(minutes: 24), category: 'movie'),
      ], const [], now: now);
      expect(s.topShows.first.showId, 'b');
      expect(s.topShows.first.episodes, 2);
      expect(s.topCategories.first.category, 'movie');
    });

    test('empty history yields a zeroed report, not a crash', () {
      final s = StatsSummary.from(const [], const [], now: now);
      expect(s.watchTime, Duration.zero);
      expect(s.readTime, Duration.zero);
      expect(s.streakDays, 0);
      expect(s.activeDays, 0);
      expect(s.last7.every((b) => b.watches == 0 && b.reads == 0), isTrue);
    });
  });

  group('formatStatDuration', () {
    test('renders hours and minutes', () {
      expect(formatStatDuration(const Duration(hours: 3, minutes: 12)), '3h 12m');
      expect(formatStatDuration(const Duration(hours: 2)), '2h');
      expect(formatStatDuration(const Duration(minutes: 45)), '45m');
      expect(formatStatDuration(const Duration(seconds: 30)), '<1m');
      expect(formatStatDuration(Duration.zero), '<1m');
    });
  });
}
