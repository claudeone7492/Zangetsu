import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/music/audio_output.dart';
import 'package:watch_app/core/music/music_models.dart';
import 'package:watch_app/core/music/music_player_controller.dart';
import 'package:watch_app/core/music/music_service.dart';
import 'package:watch_app/core/music/music_source.dart';
import 'package:watch_app/features/home/home_screen.dart';
import 'package:watch_app/features/music/music_screen.dart';
import 'package:watch_app/core/tv/tv_focusable.dart';
import 'package:watch_app/core/tv/tv_text_field.dart';
import 'package:watch_app/l10n/app_localizations.dart';

import '../../support/picker_deps.dart';

class _SilentOutput implements AudioOutput {
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  Stream<bool> get completedStream => _completed.stream;
  final List<String> opened = [];

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
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> dispose() async {}
}

class _Catalogue implements MusicSource {
  @override
  String get id => 'probe';
  @override
  String get displayName => 'Probe';
  @override
  bool get isConfigured => true;

  @override
  Future<List<MusicSection>> home() async => [
    MusicSection(
      id: 'trending',
      title: 'Trending',
      tracks: const [
        MusicTrack(
          id: '1',
          title: 'Probe Song',
          sourceId: 'probe',
          artist: 'Probe Artist',
        ),
      ],
    ),
  ];

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async =>
      const [];

  @override
  Future<String?> streamFor(MusicTrack track) async => 'https://audio/1.mp3';
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('tv_music_probe');
    Hive.init(temp.path);
    await registerPickerDeps(mode: ContentMode.music);
  });

  tearDown(() async {
    await disposePickerDeps();
    await GetIt.I.reset();
    await Hive.close();
    await temp.delete(recursive: true);
  });

  testWidgets('TV music mode shows the music surface, not the video Home', (
    tester,
  ) async {
    final service = MusicService(sources: [_Catalogue()]);
    GetIt.instance
      ..unregister<AppMode>()
      ..registerSingleton<AppMode>(const AppMode(isTv: true))
      ..registerSingleton<MusicService>(service)
      ..registerSingleton<MusicPlayerController>(
        MusicPlayerController(service: service, output: _SilentOutput()),
      );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const HomeScreen(),
      ),
    );
    await tester.pump();

    await tester.pumpAndSettle();

    expect(find.byType(MusicScreen), findsOneWidget);
    // A phone-built MusicScreen renders fine on leanback but nothing in it can
    // take D-pad focus, so a remote user could see songs and reach none of
    // them. Every actionable thing on this screen must be a TvFocusable.
    expect(
      find.byType(TvFocusable),
      findsWidgets,
      reason: 'TV music must be D-pad navigable',
    );
    expect(find.text('Probe Song'), findsOneWidget);

    // The track card itself has to be a focus target, not just the chrome.
    final card = find.ancestor(
      of: find.text('Probe Song'),
      matching: find.byType(TvFocusable),
    );
    expect(card, findsWidgets, reason: 'track card must be focusable');

    // And the search field must be the leanback-safe one: a plain TextField
    // raises the IME on focus and then swallows every direction press.
    expect(find.byType(TvTextField), findsOneWidget);
  });

  testWidgets('OK on a focused track card starts that song', (tester) async {
    final service = MusicService(sources: [_Catalogue()]);
    final output = _SilentOutput();
    GetIt.instance
      ..unregister<AppMode>()
      ..registerSingleton<AppMode>(const AppMode(isTv: true))
      ..registerSingleton<MusicService>(service)
      ..registerSingleton<MusicPlayerController>(
        MusicPlayerController(service: service, output: output),
      );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MusicScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Walk focus onto the track card the way a remote would, then press OK.
    // This is the actual product behaviour: wrapping a card in TvFocusable
    // proves nothing if the press never reaches the handler.
    final card = find.ancestor(
      of: find.text('Probe Song'),
      matching: find.byType(TvFocusable),
    );
    expect(card, findsWidgets, reason: 'track card must be focusable');

    // Focus.of looks *up*, so ask from a descendant of the TvFocusable — that
    // returns the focus node the remote would actually land on.
    final node = Focus.of(tester.element(find.text('Probe Song')));
    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(
      output.opened,
      isNotEmpty,
      reason: 'OK on a track card must start playback',
    );
  });

  testWidgets('phone music stays free of TV focus wrappers', (tester) async {
    final service = MusicService(sources: [_Catalogue()]);
    GetIt.instance
      ..unregister<AppMode>()
      ..registerSingleton<AppMode>(const AppMode(isTv: false))
      ..registerSingleton<MusicService>(service)
      ..registerSingleton<MusicPlayerController>(
        MusicPlayerController(service: service, output: _SilentOutput()),
      );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const MusicScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Probe Song'), findsOneWidget);
    // TvFocusable adds a focus ring and swallows taps for touch users, and
    // TvTextField exists only to dodge the leanback IME. Neither belongs here.
    expect(find.byType(TvFocusable), findsNothing);
    expect(find.byType(TvTextField), findsNothing);
  });
}
