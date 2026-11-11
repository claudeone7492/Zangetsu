import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/zmode/movie_regions.dart';
import 'package:watch_app/core/zmode/zmode_prefs.dart';
import 'package:watch_app/features/home/movies_tv_submenu.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('movies_tv_submenu');
    Hive.init(dir.path);
    await ZModePrefs.init();
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app({void Function(MovieRegion)? onSelected}) => MaterialApp(
    home: Scaffold(body: MoviesTvRegionBar(onSelected: onSelected)),
  );

  testWidgets('lists one chip per region with All selected by default', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    for (final r in MovieRegion.values) {
      expect(find.text(r.label), findsOneWidget, reason: r.name);
    }
    // The bar is identifiable for the screens that mount it conditionally.
    expect(find.byKey(const ValueKey('movies-tv-submenu')), findsOneWidget);
  });

  testWidgets('tapping a chip reports the pick without touching DI', (
    tester,
  ) async {
    MovieRegion? picked;
    await tester.pumpWidget(app(onSelected: (r) => picked = r));
    await tester.tap(find.text('Nollywood'));
    expect(picked, MovieRegion.nollywood);
  });

  testWidgets('tapping the already-selected chip is a no-op', (tester) async {
    var picks = 0;
    await tester.pumpWidget(app(onSelected: (_) => picks++));
    await tester.tap(find.text('All'));
    expect(picks, 0);
  });

  // Plain test, not testWidgets: this awaits the real Hive write in
  // [MoviesTvRegionBar.applyRegion], which never completes inside the widget
  // test's fake-async zone. It also covers the shell case the isRegistered
  // guards exist for — DI has neither MetadataRepository nor HomeCubit
  // registered here, and the swap must still write the pick.
  test('applyRegion writes the pick and tolerates an empty registry', () async {
    await MoviesTvRegionBar.applyRegion(MovieRegion.nollywood);
    expect(MovieRegionPrefs.region, MovieRegion.nollywood);
  });
}
