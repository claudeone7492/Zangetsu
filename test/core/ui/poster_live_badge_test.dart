import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'dart:io';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/ui/poster_card.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('poster_live');
    Hive.init(dir.path);
    await Hive.openBox(PlaybackPrefs.boxName);
    GetIt.I.registerSingleton<PlaybackPrefs>(PlaybackPrefs());
  });

  tearDown(() async {
    await GetIt.I.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('an in-play fixture shows its LIVE chip and info line', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PosterCard(
          title: 'England vs Croatia',
          liveBadge: 'LIVE',
          liveInfo: 'UEFA Nations League',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('UEFA Nations League'), findsOneWidget);
  });

  testWidgets('a countdown badge still reads on the poster', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const PosterCard(
          title: 'England vs Croatia',
          liveBadge: 'in 2h 10m',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('in 2h 10m'), findsOneWidget);
  });

  testWidgets('an ordinary title carries no live chip', (tester) async {
    await tester.pumpWidget(_wrap(const PosterCard(title: 'X')));
    await tester.pump();
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('the LIVE chip takes the corner from the dub badge', (
    tester,
  ) async {
    // A live match is never also an anime sub/dub listing, so when both are
    // present the live chip wins rather than stacking two pills in one corner.
    await tester.pumpWidget(
      _wrap(
        const PosterCard(
          title: 'X',
          liveBadge: 'LIVE',
          dubBadge: 'SUB',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('SUB'), findsNothing);
  });

  test('copyWith carries the live fields', () {
    const item = MediaItem(
      id: 'a',
      title: 'A',
      url: 'live:a|',
      type: ProviderType.movie,
      sourceId: 'streamfree',
      liveBadge: 'LIVE',
      liveInfo: 'AFCON',
      liveStartMs: 1700000000000,
    );
    final copy = item.copyWith(sourceId: 'other');
    expect(copy.liveBadge, 'LIVE');
    expect(copy.liveInfo, 'AFCON');
    expect(copy.liveStartMs, 1700000000000);
  });
}
