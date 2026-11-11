import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/features/onboarding/onboarding_screen.dart';

// Onboarding is a single automatic step now: the sources are bundled and
// installed during boot, so the screen only activates the default source,
// primes Home, marks the first run done, and hands off. There are no pages,
// no "Add sources now", and no "I'll do it later" — those belong to the old
// flow where the app shipped with zero sources and asked the user to add a
// repo. The tests below pin that: nothing to press, onDone fires, and the
// onboarded flag lands in Hive.
//
// `_setup()` reads DI singletons (ActiveSourceCubit, ProviderRegistry,
// HomeCubit) inside a try/catch and only touches Hive unconditionally, so the
// screen is safe to pump with none of those registered — the same coverage
// boundary the TV test uses.

void main() {
  late Directory dir;

  setUp(() async {
    GetIt.instance.registerSingleton<AppMode>(const AppMode(isTv: false));
    dir = await Directory.systemTemp.createTemp('onboarding_test');
    Hive.init(dir.path);
    await Hive.openBox(ActiveSourceCubit.boxName);
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('renders the intro and no old setup affordances', (tester) async {
    // The screen kicks off `_setup()` in a post-frame callback, and that path
    // awaits a REAL Hive disk write. Under the widget test's fake-async zone a
    // real I/O future never resolves, so the frame that starts it never
    // settles. runAsync forwards to the real event loop for this test.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () {})),
      );
      await tester.pump();

      // The single automatic step shows a progress spinner, not buttons.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Get Started'), findsNothing);
      expect(find.text('Add sources now'), findsNothing);
      expect(find.text("I'll do it later"), findsNothing);

      // The old "we'll install the official source catalog" pitch is gone, and
      // the manga/novel recommended-repo suggestion never leaks in either.
      expect(find.textContaining('install the official'), findsNothing);
      expect(find.textContaining('Sozo'), findsNothing);
      expect(find.textContaining('RECOMMENDED'), findsNothing);

      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });

  testWidgets('setup marks onboarded and calls onDone', (tester) async {
    var done = false;
    expect(isOnboarded(), isFalse);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(home: OnboardingScreen(onDone: () => done = true)),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(done, isTrue);
    expect(isOnboarded(), isTrue);
  });
}
