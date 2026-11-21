import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/music/audio_output.dart';
import 'package:watch_app/core/music/music_models.dart';
import 'package:watch_app/core/music/music_player_controller.dart';
import 'package:watch_app/core/music/music_queue.dart';
import 'package:watch_app/core/music/music_service.dart';
import 'package:watch_app/core/music/music_source.dart';

/// Records what the controller asked the audio output to do.
class FakeOutput implements AudioOutput {
  final position = StreamController<Duration>.broadcast();
  final duration = StreamController<Duration>.broadcast();
  final playing = StreamController<bool>.broadcast();
  final buffering = StreamController<bool>.broadcast();
  final completed = StreamController<bool>.broadcast();

  final List<String> opened = [];
  final List<double> volumes = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  final List<Duration> seeks = [];
  bool disposed = false;

  /// Set to make [open] throw, for the playback-failure path.
  Object? openError;

  /// Held so a test can prove a slow open does not win over a newer one.
  /// Per-URL gates, so one slow open can be released independently.
  final Map<String, Completer<void>> gates = {};

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
  Future<void> open(String url) async {
    opened.add(url);
    final gate = gates[url];
    if (gate != null) await gate.future;
    if (openError != null) throw openError!;
  }

  @override
  Future<void> play() async => playCalls++;
  @override
  Future<void> pause() async => pauseCalls++;
  @override
  Future<void> stop() async => stopCalls++;
  @override
  Future<void> seek(Duration position) async => seeks.add(position);
  @override
  Future<void> setVolume(double value) async => volumes.add(value);

  @override
  Future<void> setAudioFilter(String? filter) async {}

  @override
  Future<void> dispose() async {
    disposed = true;
    await position.close();
    await duration.close();
    await playing.close();
    await buffering.close();
    await completed.close();
  }
}

class Catalogue implements MusicSource {
  Catalogue(this.tracks);

  final List<MusicTrack> tracks;
  final Map<String, String?> urls = {};
  Object? searchError;

  @override
  String get id => 'test';
  @override
  String get displayName => 'Test';
  @override
  bool get isConfigured => true;

  @override
  Future<List<MusicSection>> home() async => [
    MusicSection(title: 'Trending', tracks: tracks),
  ];

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    if (searchError != null) throw searchError!;
    return tracks;
  }

  @override
  Future<String?> streamFor(MusicTrack track) async =>
      urls.containsKey(track.id)
      ? urls[track.id]
      : 'https://audio/${track.id}.mp3';
}

MusicTrack track(String id) =>
    MusicTrack(id: id, title: 'Song $id', sourceId: 'test');

/// Pumps the microtask queue so the controller's awaits settle.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeOutput output;
  late Catalogue catalogue;
  late MusicPlayerController controller;

  setUp(() {
    output = FakeOutput();
    catalogue = Catalogue([track('1'), track('2'), track('3')]);
    controller = MusicPlayerController(
      service: MusicService(sources: [catalogue]),
      output: output,
    );
  });

  tearDown(() => controller.dispose());

  test('playAll resolves a URL and opens it', () async {
    await controller.playAll(catalogue.tracks);
    expect(output.opened, ['https://audio/1.mp3']);
    expect(output.playCalls, 1);
    expect(controller.current?.id, '1');
    expect(controller.hasTrack, isTrue);
  });

  test('playFrom starts the list at the tapped track', () async {
    await controller.playFrom(catalogue.tracks, catalogue.tracks[2]);
    expect(controller.current?.id, '3');
    expect(output.opened.single, 'https://audio/3.mp3');
  });

  test('playFrom on an absent track falls back to the first', () async {
    await controller.playFrom(catalogue.tracks, track('999'));
    expect(controller.current?.id, '1');
  });

  test('next advances and opens the following track', () async {
    await controller.playAll(catalogue.tracks);
    await controller.next();
    expect(controller.current?.id, '2');
    expect(output.opened.last, 'https://audio/2.mp3');
  });

  test('next at the end pauses instead of stopping', () async {
    await controller.playAll(catalogue.tracks, startAt: 2);
    await controller.next();
    expect(output.pauseCalls, 1);
    expect(
      controller.current?.id,
      '3',
      reason: 'cursor stays on the last track',
    );
  });

  test('previous restarts a track that is past its start', () async {
    await controller.playAll(catalogue.tracks, startAt: 1);
    output.position.add(const Duration(seconds: 30));
    await settle();
    await controller.previous();
    expect(output.seeks, [Duration.zero]);
    expect(controller.current?.id, '2', reason: 'same track, rewound');
  });

  test('previous goes back when the track just started', () async {
    await controller.playAll(catalogue.tracks, startAt: 1);
    await controller.previous();
    expect(controller.current?.id, '1');
  });

  test('a finished track advances the queue', () async {
    await controller.playAll(catalogue.tracks);
    output.completed.add(true);
    await settle();
    expect(controller.current?.id, '2');
  });

  test('repeat one replays the same track on completion', () async {
    await controller.playAll(catalogue.tracks);
    controller.cycleRepeat(); // off -> all
    controller.cycleRepeat(); // all -> one
    output.completed.add(true);
    await settle();
    expect(controller.current?.id, '1');
    expect(controller.repeat, MusicRepeat.one);
  });

  test('completion at the end with repeat off stops advancing', () async {
    await controller.playAll(catalogue.tracks, startAt: 2);
    output.completed.add(true);
    await settle();
    expect(controller.current?.id, '3');
    expect(controller.playing, isFalse);
  });

  test('togglePlayPause pauses when playing', () async {
    await controller.playAll(catalogue.tracks);
    output.playing.add(true);
    await settle();
    await controller.togglePlayPause();
    expect(output.pauseCalls, 1);
  });

  test('togglePlayPause resumes when paused', () async {
    await controller.playAll(catalogue.tracks);
    output.playing.add(false);
    await settle();
    final before = output.playCalls;
    await controller.togglePlayPause();
    expect(output.playCalls, before + 1);
  });

  test('after stop, play resumes the queue from its cursor', () async {
    await controller.playAll(catalogue.tracks);
    await controller.stop();
    expect(controller.current, isNull);
    output.opened.clear();
    await controller.togglePlayPause();
    // stop() clears what is playing but keeps the queue, so play starts the
    // cursor track again rather than silently doing nothing.
    expect(output.opened, ['https://audio/1.mp3']);
    expect(controller.current?.id, '1');
  });

  test('seek clamps to the known duration', () async {
    await controller.playAll(catalogue.tracks);
    output.duration.add(const Duration(minutes: 3));
    await settle();
    await controller.seek(const Duration(minutes: 10));
    expect(output.seeks.single, const Duration(minutes: 3));

    await controller.seek(const Duration(seconds: -5));
    expect(output.seeks.last, Duration.zero);
  });

  test('volume is clamped and forwarded', () async {
    await controller.setVolume(1.8);
    expect(controller.volume, 1.0);
    await controller.setVolume(-0.4);
    expect(controller.volume, 0.0);
    expect(output.volumes, [1.0, 0.0]);
  });

  test('a catalogue with no URL surfaces a playable error', () async {
    catalogue.urls['1'] = null;
    await controller.playAll(catalogue.tracks);
    expect(controller.error, "Couldn't play this song");
    expect(output.opened, isEmpty);
    expect(controller.playing, isFalse);
  });

  test(
    'an output that throws surfaces an error rather than crashing',
    () async {
      output.openError = StateError('decoder missing');
      await controller.playAll(catalogue.tracks);
      expect(controller.error, "Couldn't play this song");
      expect(controller.buffering, isFalse);
    },
  );

  test('a slow load for a skipped track does not win', () async {
    final slowGate = Completer<void>();
    output.gates['https://audio/1.mp3'] = slowGate;
    final slow = controller.playAll(catalogue.tracks); // track 1, blocked
    await settle();
    expect(output.opened, ['https://audio/1.mp3']);

    await controller.next(); // track 2 opens immediately
    expect(controller.current?.id, '2');

    // Releasing the first open must not take over the playing track.
    slowGate.complete();
    await slow;
    expect(controller.current?.id, '2');
    expect(
      output.playCalls,
      1,
      reason: 'the superseded load must not start audio',
    );
  });

  test('shuffle and repeat cycle through their states', () async {
    expect(controller.shuffle, isFalse);
    controller.setShuffle(true);
    expect(controller.shuffle, isTrue);
    controller.setShuffle(false);
    expect(controller.shuffle, isFalse);

    expect(controller.repeat, MusicRepeat.off);
    controller.cycleRepeat();
    expect(controller.repeat, MusicRepeat.all);
    controller.cycleRepeat();
    expect(controller.repeat, MusicRepeat.one);
    controller.cycleRepeat();
    expect(controller.repeat, MusicRepeat.off);
  });

  test('upNext reflects play order, not catalogue order', () async {
    await controller.playAll(catalogue.tracks);
    controller.setShuffle(true);
    final ids = controller.upNext.map((t) => t.id).toList();
    expect(ids.toSet(), {'1', '2', '3'});
    expect(ids.first, '1', reason: 'the playing track stays first');
  });

  test('stop clears the current track and stops the output', () async {
    await controller.playAll(catalogue.tracks);
    await controller.stop();
    expect(controller.current, isNull);
    expect(output.stopCalls, 1);
    expect(controller.position, Duration.zero);
  });

  test('position and duration are mirrored from the output', () async {
    await controller.playAll(catalogue.tracks);
    output.position.add(const Duration(seconds: 42));
    output.duration.add(const Duration(minutes: 4));
    await settle();
    expect(controller.position, const Duration(seconds: 42));
    expect(controller.duration, const Duration(minutes: 4));
  });

  test(
    'a zero duration is ignored so the UI keeps the catalogue value',
    () async {
      await controller.playAll([
        MusicTrack(
          id: '1',
          title: 'x',
          sourceId: 'test',
          duration: const Duration(minutes: 2),
        ),
      ]);
      expect(controller.duration, const Duration(minutes: 2));
      output.duration.add(Duration.zero);
      await settle();
      expect(controller.duration, const Duration(minutes: 2));
    },
  );

  test('dispose cancels subscriptions and disposes the output', () async {
    await controller.playAll(catalogue.tracks);
    controller.dispose();
    await settle();
    expect(output.disposed, isTrue);
    // Re-create so tearDown's dispose is harmless.
    controller = MusicPlayerController(
      service: MusicService(sources: [catalogue]),
      output: FakeOutput(),
    );
  });
}
