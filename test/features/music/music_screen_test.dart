import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/music/audio_output.dart';
import 'package:watch_app/core/music/music_models.dart';
import 'package:watch_app/core/music/music_player_controller.dart';
import 'package:watch_app/core/music/music_service.dart';
import 'package:watch_app/core/music/music_source.dart';
import 'package:watch_app/features/music/music_player_sheet.dart';
import 'package:watch_app/features/music/music_screen.dart';
import 'package:watch_app/l10n/app_localizations.dart';

/// Audio output that records calls and never touches libmpv.
class _SilentOutput implements AudioOutput {
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration>.broadcast();
  final playing = StreamController<bool>.broadcast();
  final buffering = StreamController<bool>.broadcast();
  final completed = StreamController<bool>.broadcast();

  final List<String> opened = [];

  @override
  Stream<Duration> get positionStream => position.stream;
  @override
  Stream<Duration> get durationStream => duration.stream;
  @override
  Stream<bool> get playingStream => playing.stream;
  @override
  Stream<bool> get bufferingStream => buffering.stream;
  @override
  Stream<bool> get completedStream => completed.stream;

  @override
  Future<void> open(String url) async => opened.add(url);
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> setVolume(double value) async {}
  @override
  Future<void> dispose() async {
    await position.close();
    await duration.close();
    await playing.close();
    await buffering.close();
    await completed.close();
  }
}

class _Catalogue implements MusicSource {
  _Catalogue({
    this.sections = const [],
    this.results,
    this.homeError,
    this.configured = true,
  });

  final bool configured;

  final List<MusicSection> sections;
  final List<MusicTrack>? results;
  final Object? homeError;

  /// Set to resolve no URL, which drives the "can't play" path.
  bool resolveNothing = false;

  @override
  String get id => 'test';
  @override
  String get displayName => 'Test catalogue';
  @override
  bool get isConfigured => configured;

  @override
  Future<List<MusicSection>> home() async {
    if (homeError != null) throw homeError!;
    return sections;
  }

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async =>
      results ?? const [];

  @override
  Future<String?> streamFor(MusicTrack track) async =>
      resolveNothing ? null : 'https://audio/${track.id}.mp3';
}

MusicTrack _track(String id) => MusicTrack(
  id: id,
  title: 'Song $id',
  sourceId: 'test',
  artist: 'Artist $id',
);

MusicSection _row(
  List<MusicTrack> tracks, {
  String? id,
  String title = 'Trending',
}) => MusicSection(id: id, title: title, tracks: tracks);

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  late _SilentOutput output;
  late MusicPlayerController player;

  setUp(() {
    output = _SilentOutput();
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpMusic(
    WidgetTester tester, {
    required MusicService service,
  }) async {
    player = MusicPlayerController(service: service, output: output);
    GetIt.instance
      ..registerSingleton<MusicService>(service)
      ..registerSingleton<MusicPlayerController>(player);
    await tester.pumpWidget(_app(const MusicScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a home row and its tracks', (tester) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1'), _track('2')]),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('Song 2'), findsOneWidget);
    expect(find.text('Artist 1'), findsOneWidget);
  });

  testWidgets('a standard row heading follows the row id, not its wording', (
    tester,
  ) async {
    // The catalogue calls this row "Hot right now"; the app still shows its own
    // word for `trending`. Matching on the English title would have failed here.
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1')], id: 'trending', title: 'Hot right now'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Hot right now'), findsNothing);
  });

  testWidgets('an unrecognised row keeps the catalogue its own heading', (
    tester,
  ) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1')], id: 'editorPicks', title: 'Editor picks'),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Editor picks'), findsOneWidget);
  });

  testWidgets('tapping a card starts that row and opens the player', (
    tester,
  ) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1'), _track('2')]),
            ],
          ),
        ],
      ),
    );

    await tester.tap(find.text('Song 2'));
    await tester.pumpAndSettle();

    expect(output.opened, ['https://audio/2.mp3']);
    expect(player.current?.id, '2');
    expect(find.byType(MusicPlayerSheet), findsOneWidget);
    expect(find.text('Now playing'), findsOneWidget);
  });

  testWidgets('an empty catalogue shows the empty state, not a blank page', (
    tester,
  ) async {
    await pumpMusic(tester, service: MusicService(sources: [_Catalogue()]));
    expect(find.text('No songs here yet'), findsOneWidget);
  });

  testWidgets('one dead catalogue does not blank the mode', (tester) async {
    // A source outage must cost only that source's rows. The failing one is
    // listed first so a naive "first source wins" would show nothing.
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(homeError: MusicSourceException('down')),
          _Catalogue(
            sections: [
              _row([_track('1')]),
            ],
          ),
        ],
      ),
    );

    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Song 1'), findsOneWidget);
    expect(find.text('No songs here yet'), findsNothing);
  });

  testWidgets('search replaces the rows with results', (tester) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1')]),
            ],
            results: [_track('9')],
          ),
        ],
      ),
    );

    await tester.enterText(find.byType(TextField), 'query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Song 9'), findsOneWidget);
    expect(find.text('Trending'), findsNothing);
  });

  testWidgets('an empty search shows No results', (tester) async {
    await pumpMusic(
      tester,
      service: MusicService(sources: [_Catalogue(results: const [])]),
    );

    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('the mini player appears once a song is loaded', (tester) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1')]),
            ],
          ),
        ],
      ),
    );

    expect(find.byIcon(Icons.skip_next_rounded), findsNothing);

    await tester.tap(find.text('Song 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
  });

  testWidgets('the player shows the queue', (tester) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1'), _track('2'), _track('3')]),
            ],
          ),
        ],
      ),
    );

    await tester.tap(find.text('Song 1'));
    await tester.pumpAndSettle();

    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('Song 2'), findsWidgets);
    expect(find.text('Song 3'), findsWidgets);
  });

  testWidgets('shuffle and repeat toggles reflect the controller', (
    tester,
  ) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1'), _track('2')]),
            ],
          ),
        ],
      ),
    );

    await tester.tap(find.text('Song 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.shuffle_rounded));
    await tester.pumpAndSettle();
    expect(player.shuffle, isTrue);

    // off -> all -> one
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.repeat_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.repeat_one_rounded), findsOneWidget);
  });

  testWidgets('next in the sheet advances the queue', (tester) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1'), _track('2')]),
            ],
          ),
        ],
      ),
    );

    await tester.tap(find.text('Song 1'));
    await tester.pumpAndSettle();

    // The mini player behind the sheet carries the same icon, so scope the tap
    // to the sheet's own controls.
    await tester.tap(
      find.descendant(
        of: find.byType(MusicPlayerSheet),
        matching: find.byIcon(Icons.skip_next_rounded),
      ),
    );
    await tester.pumpAndSettle();

    expect(player.current?.id, '2');
    expect(output.opened.last, 'https://audio/2.mp3');
  });

  testWidgets('an unplayable track reports it instead of opening silence', (
    tester,
  ) async {
    await pumpMusic(
      tester,
      service: MusicService(
        sources: [
          _Catalogue(
            sections: [
              _row([_track('1')]),
            ],
          )..resolveNothing = true,
        ],
      ),
    );

    await tester.tap(find.text('Song 1'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(MusicPlayerSheet), findsNothing);
    expect(output.opened, isEmpty);
  });

  testWidgets('the search tab opens focused and prompts for a query', (
    tester,
  ) async {
    final service = MusicService(
      sources: [
        _Catalogue(results: [_track('5')]),
      ],
    );
    player = MusicPlayerController(service: service, output: output);
    GetIt.instance
      ..registerSingleton<MusicService>(service)
      ..registerSingleton<MusicPlayerController>(player);

    await tester.pumpWidget(_app(const MusicScreen(searchOnOpen: true)));
    await tester.pumpAndSettle();

    // Titled for searching, and the field has focus so the keyboard is up.
    expect(find.text('Search songs'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode?.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Song 5'), findsOneWidget);
  });

  testWidgets('the search tab does not load the Home rows', (tester) async {
    // A catalogue whose home() would fail the test if called: search mode must
    // not spend a request on rows nobody asked to see.
    final service = MusicService(sources: [_ExplodingHome()]);
    player = MusicPlayerController(service: service, output: output);
    GetIt.instance
      ..registerSingleton<MusicService>(service)
      ..registerSingleton<MusicPlayerController>(player);

    await tester.pumpWidget(_app(const MusicScreen(searchOnOpen: true)));
    await tester.pumpAndSettle();

    expect(find.text('No songs here yet'), findsNothing);
    expect(find.text('Search songs'), findsOneWidget);
  });

  testWidgets('an unusable catalogue says so instead of claiming it is empty', (
    tester,
  ) async {
    await pumpMusic(
      tester,
      service: MusicService(sources: [_Catalogue(configured: false)]),
    );

    expect(find.text('Music unavailable'), findsOneWidget);
    expect(find.text('No songs here yet'), findsNothing);
  });
}

/// A catalogue that fails loudly if Home is ever requested.
class _ExplodingHome implements MusicSource {
  @override
  String get id => 'exploding';
  @override
  String get displayName => 'Exploding';
  @override
  bool get isConfigured => true;

  @override
  Future<List<MusicSection>> home() async =>
      throw StateError('home() must not run in search mode');

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async =>
      const [];

  @override
  Future<String?> streamFor(MusicTrack track) async => null;
}
