import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/dub/dub_engine.dart';
import 'package:watch_app/core/dub/dub_narrator.dart';
import 'package:watch_app/core/dub/dub_prefs.dart';
import 'package:watch_app/features/player/dub_sheet.dart';

/// Speaks on demand and records what it was asked to say, so the assertions are
/// on the calls the sheet actually causes.
class _FakeDubEngine implements DubEngine {
  final List<String> spoken = [];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<DubVoice>> voices() async => const [
    DubVoice(name: 'Test', locale: 'en-GB'),
  ];

  @override
  Future<void> speak(
    String text, {
    String? voice,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}
}

/// The sheet shows a spinner while it reads the device's voices, and a spinner
/// never stops animating, so [WidgetTester.pumpAndSettle] would spin until it
/// times out. A few fixed frames are enough to let the futures resolve.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // Hive's file I/O never completes inside a widget test's fake-async zone, so
  // the box is opened and closed around the suite rather than per test.
  late Directory dir;
  late DubPrefs prefs;
  late _FakeDubEngine engine;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
    prefs = await DubPrefs.open();
  });

  tearDownAll(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  setUp(() async {
    engine = _FakeDubEngine();
    final sl = GetIt.instance;
    await sl.reset();
    sl.registerSingleton<DubPrefs>(prefs);
    sl.registerSingleton<DubEngine>(engine);
  });

  tearDown(() => GetIt.instance.reset());

  /// Taps in the real async zone: the sheet's controls write to Hive, and a
  /// Hive write never completes under a widget test's fake clock.
  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    // The sheet scrolls; a chip can sit below the fold on a small surface.
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(finder);
      // Let the write the tap starts finish before the fake clock resumes.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle(tester);
  }

  Future<void> openSheet(
    WidgetTester tester, {
    DubNarrator? narrator,
    bool available = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDubSheet(
                context,
                available: available,
                narrator: narrator,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('the switch writes through to the prefs', (tester) async {
    await openSheet(tester);

    expect(prefs.enabled, isFalse);
    await tapAndSettle(tester, find.text('Narrate subtitles'));

    expect(prefs.enabled, isTrue);
  });

  testWidgets('a device with no engine explains itself instead of offering '
      'controls', (tester) async {
    await openSheet(tester, available: false);

    expect(find.textContaining('No speech engine'), findsOneWidget);
    expect(find.text('Narrate subtitles'), findsNothing);
  });

  testWidgets('the installed voices are offered as choices', (tester) async {
    await openSheet(tester);

    expect(find.textContaining('Test (en-GB)'), findsOneWidget);
    await tapAndSettle(tester, find.textContaining('Test (en-GB)'));

    expect(prefs.voice, 'Test');
  });

  testWidgets('picking a narration language is remembered', (tester) async {
    await openSheet(tester);

    await tapAndSettle(tester, find.text('Spanish'));

    expect(prefs.language, 'es');
  });

  testWidgets('opened from Settings there is no playback to describe', (
    tester,
  ) async {
    // No narrator: the sheet must not claim there are no cues, because there is
    // no track in play to have cues from.
    await tester.runAsync(() => prefs.setEnabled(true));
    await openSheet(tester);

    expect(find.textContaining('No subtitle cues loaded'), findsNothing);
  });

  testWidgets('the line being narrated is shown while it plays', (tester) async {
    final narrator = DubNarrator(prefs: prefs, engine: engine);
    addTearDown(narrator.dispose);
    await tester.runAsync(() => prefs.setEnabled(true));
    await openSheet(tester, narrator: narrator);

    await narrator.load(
      'ep1',
      '1\n00:00:01,000 --> 00:00:04,000\nHello there\n',
    );
    await narrator.onPosition(const Duration(seconds: 2));
    await settle(tester);

    expect(find.text('Hello there'), findsOneWidget);
  });
}
