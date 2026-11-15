import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/zmode/zmode_prefs.dart';
import 'package:watch_app/features/shell/mode_bar.dart';

void main() {
  testWidgets('shows exactly four content modes and reports the pick', (t) async {
    ContentMode? mode;
    StreamKind? kind;
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: true,
        current: (ContentMode.anime, StreamKind.anime),
        onLiveTv: () {},
        onPicked: (m, k) { mode = m; kind = k; },
      ),
    )));
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('Movie/TV'), findsOneWidget);
    expect(find.text('Manga'), findsOneWidget);
    expect(find.text('Novel'), findsOneWidget);
    expect(find.text('Sources'), findsNothing);
    expect(find.text('Streaming'), findsNothing);
    await t.tap(find.text('Movie/TV'));
    expect(mode, ContentMode.anime);
    expect(kind, StreamKind.movie);
    await t.tap(find.text('Manga'));
    expect(mode, ContentMode.manga);
  });

  testWidgets('offers Live TV beside the modes and reports the tap', (
    t,
  ) async {
    var opened = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: true,
        current: (ContentMode.anime, StreamKind.anime),
        onLiveTv: () => opened++,
        onPicked: (_, _) {},
      ),
    )));
    // The user's content list is Anime / Movie / Manga / Novel / Shorts /
    // Live TV, so the bar carries the destination too — not just the dock menu.
    expect(find.text('Shorts'), findsOneWidget);
    expect(find.text('Live TV'), findsOneWidget);
    await t.tap(find.text('Live TV'));
    expect(opened, 1);
  });

  testWidgets('closed bar ignores taps', (t) async {
    var picked = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: false,
        current: (ContentMode.anime, StreamKind.anime),
        onLiveTv: () {},
        onPicked: (_, _) => picked++,
      ),
    )));
    await t.tap(find.text('Manga'), warnIfMissed: false);
    expect(picked, 0);
  });
}
