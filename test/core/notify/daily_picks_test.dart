import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/notify/daily_picks_prefs.dart';

void main() {
  group('Daily picks slots', () {
    test('there are exactly three, one per time of day', () {
      expect(DailyPickSlot.values.length, 3);
      expect(DailyPickSlot.values.map((s) => s.name), [
        'morning',
        'afternoon',
        'evening',
      ]);
    });

    test('each slot uses a different card design', () {
      // The whole point of the feature: three notifications a day, each a
      // different industry-standard layout — big-picture, big-text, inbox.
      final styles = DailyPickSlot.values.map((s) => s.style).toSet();
      expect(styles.length, 3);
      expect(styles, {
        DailyPickStyle.bigPicture,
        DailyPickStyle.bigText,
        DailyPickStyle.inbox,
      });
    });

    test('each slot is a different kind of suggestion', () {
      // One trending, one picked-for-you, one new — the Netflix trio.
      final kinds = DailyPickSlot.values.map((s) => s.kind).toSet();
      expect(kinds, {
        DailyPickKind.trending,
        DailyPickKind.recommended,
        DailyPickKind.newRelease,
      });
    });

    test('the slots are spread across the day and strictly ordered', () {
      final minutes = [
        for (final s in DailyPickSlot.values) s.hour * 60 + s.minute,
      ];
      expect(minutes, orderedEquals([...minutes]..sort()));
      expect(minutes.first, lessThan(minutes.last));
      // No two slots share a time, so they never replace one another.
      expect(minutes.toSet().length, 3);
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

    test('the switch defaults off', () {
      expect(DailyPicksPrefs.enabled, isFalse);
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
    });
  });
}
