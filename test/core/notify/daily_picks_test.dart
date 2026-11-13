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
      // different industry-standard layout — big-text, big-picture, inbox.
      final styles = DailyPickSlot.values.map((s) => s.style).toSet();
      expect(styles.length, 3);
      expect(styles, {
        DailyPickStyle.bigText,
        DailyPickStyle.bigPicture,
        DailyPickStyle.inbox,
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

    test('every slot carries an l10n label key', () {
      for (final s in DailyPickSlot.values) {
        expect(s.titleKey, startsWith('dailyPicks'));
      }
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
