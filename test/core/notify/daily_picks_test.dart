import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/notify/daily_picks_prefs.dart';

void main() {
  group('Daily picks slots', () {
    test('there are exactly five, spread across the day', () {
      expect(DailyPickSlot.values.length, 5);
      expect(DailyPickSlot.values.map((s) => s.name), [
        'morning',
        'midday',
        'afternoon',
        'evening',
        'night',
      ]);
    });

    test('the five slots rotate the three card designs', () {
      // The feature has five cards but three industry-standard layouts;
      // the layouts alternate so consecutive cards never look identical.
      final styles = DailyPickSlot.values.map((s) => s.style).toSet();
      expect(styles, {
        DailyPickStyle.bigPicture,
        DailyPickStyle.bigText,
        DailyPickStyle.inbox,
      });
      expect(
        DailyPickSlot.values.first.style,
        isNot(DailyPickSlot.values[1].style),
      );
    });

    test('each slot is a different kind of suggestion', () {
      final kinds = DailyPickSlot.values.map((s) => s.kind).toSet();
      expect(kinds, {
        DailyPickKind.trendingMovies,
        DailyPickKind.football,
        DailyPickKind.trendingAnime,
        DailyPickKind.newRelease,
        DailyPickKind.recommended,
      });
    });

    test('the cards fire at 06:00, 13:00, 15:00, 19:00 and 23:00', () {
      expect(
        [for (final s in DailyPickSlot.values) s.hour * 60 + s.minute],
        [6 * 60, 13 * 60, 15 * 60, 19 * 60, 23 * 60],
      );
    });

    test('the slots are spread across the day and strictly ordered', () {
      final minutes = [
        for (final s in DailyPickSlot.values) s.hour * 60 + s.minute,
      ];
      expect(minutes, orderedEquals([...minutes]..sort()));
      expect(minutes.first, lessThan(minutes.last));
      // No two slots share a time, so they never replace one another.
      expect(minutes.toSet().length, 5);
    });

    test('the jitter windows never overlap', () {
      // Random per-day offsets are only safe while the windows stay disjoint;
      // overlapping windows would let the evening card fire before the morning
      // one on some days.
      var previousEnd = -1;
      for (final s in DailyPickSlot.values) {
        final start = s.baseMinuteOfDay - s.jitterMinutes;
        final end = s.baseMinuteOfDay + s.jitterMinutes;
        expect(start, greaterThan(previousEnd));
        previousEnd = end;
      }
    });

    test('every slot carries an l10n label key', () {
      for (final s in DailyPickSlot.values) {
        expect(s.titleKey, startsWith('dailyPicks'));
      }
    });
  });

  group('Daily picks random time', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp();
      Hive.init(dir.path);
      await Hive.openBox(DailyPicksPrefs.boxName);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('the chosen minute is inside the slot window', () async {
      const day = '2026-01-01';
      for (final slot in DailyPickSlot.values) {
        final minute = await DailyPicksPrefs.resolveMinuteOfDay(slot, day);
        expect(
          minute,
          greaterThanOrEqualTo(slot.baseMinuteOfDay - slot.jitterMinutes),
        );
        expect(
          minute,
          lessThanOrEqualTo(slot.baseMinuteOfDay + slot.jitterMinutes),
        );
      }
    });

    test('the choice is stable within a day and redrawn the next', () async {
      const day = '2026-01-01';
      final first = await DailyPicksPrefs.resolveMinuteOfDay(
        DailyPickSlot.morning,
        day,
      );
      final again = await DailyPicksPrefs.resolveMinuteOfDay(
        DailyPickSlot.morning,
        day,
      );
      expect(again, first);
      // A new day has no stored offset, so the previous day's stamp no longer
      // answers for it.
      await DailyPicksPrefs.resolveMinuteOfDay(
        DailyPickSlot.morning,
        '2026-01-02',
      );
      expect(DailyPicksPrefs.jitter(DailyPickSlot.morning, day), isNull);
    });
  });

  group('Daily picks dedupe', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp();
      Hive.init(dir.path);
      await Hive.openBox(DailyPicksPrefs.boxName);
    });

    tearDown(() async {
      await Hive.deleteFromDisk();
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    test('the switch defaults on', () {
      expect(DailyPicksPrefs.enabled, isTrue);
    });

    test('the switch round-trips', () async {
      await DailyPicksPrefs.setEnabled(true);
      expect(DailyPicksPrefs.enabled, isTrue);
      await DailyPicksPrefs.setEnabled(false);
      expect(DailyPicksPrefs.enabled, isFalse);
    });

    test('a slot needs filling until it is stamped for that day', () async {
      const day = '2026-01-01';
      expect(DailyPicksPrefs.needsFill(DailyPickSlot.morning, day), isTrue);
      await DailyPicksPrefs.markFilled(DailyPickSlot.morning, day);
      expect(DailyPicksPrefs.needsFill(DailyPickSlot.morning, day), isFalse);
    });

    test('the next day re-arms the slot', () async {
      await DailyPicksPrefs.markFilled(DailyPickSlot.evening, '2026-01-01');
      expect(
        DailyPicksPrefs.needsFill(DailyPickSlot.evening, '2026-01-02'),
        isTrue,
      );
    });

    test('slots dedupe independently', () async {
      await DailyPicksPrefs.markFilled(DailyPickSlot.morning, '2026-01-01');
      expect(
        DailyPicksPrefs.needsFill(DailyPickSlot.morning, '2026-01-01'),
        isFalse,
      );
      expect(
        DailyPicksPrefs.needsFill(DailyPickSlot.afternoon, '2026-01-01'),
        isTrue,
      );
      expect(
        DailyPicksPrefs.needsFill(DailyPickSlot.evening, '2026-01-01'),
        isTrue,
      );
      expect(
        DailyPicksPrefs.needsFill(DailyPickSlot.night, '2026-01-01'),
        isTrue,
      );
    });
  });
}
