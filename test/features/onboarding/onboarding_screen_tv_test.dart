import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/core/tv/tv_focusable.dart';
import 'package:watch_app/features/onboarding/onboarding_screen.dart'
    show isOnboarded;
import 'package:watch_app/features/onboarding/onboarding_screen_tv.dart';

// ── Tests ─────────────────────────────────────────────────────────────────────
//
// The TV onboarding is a single automatic step: the sources are bundled and
// installed during boot, so this only activates the default source, primes
// Home, marks the first run done, and hands off. There are no buttons and no
// D-pad focus targets anymore — the old "Get Started / Skip for now" pair is
// gone. `_setup()` reads DI singletons inside a try/catch and only touches
// Hive unconditionally, so the screen is safe to pump with none registered.

void main() {
  late Directory dir;

  setUp(() async {
    GetIt.instance.registerSingleton<AppMode>(const AppMode(isTv: true));
    dir = await Directory.systemTemp.createTemp('onboarding_tv_test');
    Hive.init(dir.path);
    await Hive.openBox(ActiveSourceCubit.boxName);
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('renders the intro with no buttons and no focus targets', (
    tester,
  ) async {
    // The screen kicks off `_setup()` in a post-frame callback, and that path
    // awaits a REAL Hive disk write. Under the widget test's fake-async zone a
    // real I/O future never resolves, so the frame that starts it never
    // settles. runAsync forwards to the real event loop for this test.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreenTv(onDone: () {})),
      );
      await tester.pump();

      // Welcome heading is displayed.
      expect(find.textContaining('Welcome to'), findsOneWidget);

      // A progress spinner replaces the old action buttons.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Get Started'), findsNothing);
      expect(find.text('Skip for now'), findsNothing);

      // Nothing is focusable — there is nothing to press.
      expect(find.byType(TvFocusable), findsNothing);

      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });

  testWidgets('setup marks onboarded and calls onDone', (tester) async {
    var done = false;
    expect(isOnboarded(), isFalse);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreenTv(onDone: () => done = true)),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(done, isTrue);
    expect(isOnboarded(), isTrue);
  });
}
