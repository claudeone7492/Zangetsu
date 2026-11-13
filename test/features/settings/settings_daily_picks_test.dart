import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/notify/daily_picks_prefs.dart';
import 'package:watch_app/features/settings/settings_daily_picks.dart';
import 'package:watch_app/l10n/app_localizations.dart';

/// The screen reads [DailyPicksPrefs] directly, and Hive's disk I/O only
/// completes outside `testWidgets`' fake-async zone — so every write in these
/// tests goes through [WidgetTester.runAsync]. (The write path itself, and the
/// day-stamp dedupe, are covered by `daily_picks_test.dart`; this file checks
/// what the screen *shows*.)
Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // A no-op scheduler: a widget test must not touch the notification
      // platform channels, which have no handler here.
      home: DailyPicksScreen(onEnabled: () async {}),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
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

  testWidgets('opens with the switch off and no slots listed', (tester) async {
    await _pump(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    // Slots only appear once the feature is on — off is a single, quiet row.
    expect(find.text('Morning'), findsNothing);
    expect(find.text('Afternoon'), findsNothing);
    expect(find.text('Evening'), findsNothing);
  });

  testWidgets('lists all three slots when the feature is on', (tester) async {
    await tester.runAsync(() => DailyPicksPrefs.setEnabled(true));
    await _pump(tester);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Afternoon'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);
    // The manual trigger sits under the slot list.
    expect(find.text("Send the day's picks now"), findsOneWidget);
  });

  testWidgets('a saved-off choice renders as off', (tester) async {
    await tester.runAsync(() => DailyPicksPrefs.setEnabled(false));
    await _pump(tester);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(find.text('Morning'), findsNothing);
  });
}
