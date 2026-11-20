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

  testWidgets('offers Music and reports the pick', (t) async {
    ContentMode? mode;
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: true,
        current: (ContentMode.anime, StreamKind.anime),
        onLiveTv: () {},
        onPicked: (m, _) => mode = m,
      ),
    )));
    expect(find.text('Music'), findsOneWidget);
    await t.tap(find.text('Music'));
    expect(mode, ContentMode.music);
  });

  testWidgets('Music is selectable and never reads as Anime', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(
      body: ModeBar(
        open: true,
        // Anime's Movie/TV entry shares the anime ContentMode; music must not
        // be highlighted by that match, and anime must not highlight music.
        current: (ContentMode.music, StreamKind.anime),
        onLiveTv: () {},
        onPicked: (_, _) {},
      ),
    )));
    expect(find.text('Music'), findsOneWidget);
    expect(iconForMode(ContentMode.music, StreamKind.anime),
        Icons.music_note_outlined);
  });
}
