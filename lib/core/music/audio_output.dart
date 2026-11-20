import 'dart:async';

import 'package:media_kit/media_kit.dart';

/// The slice of an audio player the music mode needs.
///
/// A seam rather than a `Player` field: `media_kit` needs libmpv initialised, so
/// a test cannot construct one, and queue behaviour (what plays next, what
/// happens at the end) is exactly the part worth testing without a device.
abstract class AudioOutput {
  /// Playback head, in the current track.
  Stream<Duration> get positionStream;

  /// Length of the current track, once known.
  Stream<Duration> get durationStream;

  /// True while audio is actually running (false when paused or stalled).
  Stream<bool> get playingStream;

  /// True while the player is filling its buffer.
  Stream<bool> get bufferingStream;

  /// Emits true when the current track plays to its end. Pausing never fires
  /// this; the distinction matters because it is what advances the queue.
  Stream<bool> get completedStream;

  Future<void> open(String url);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);

  /// [value] is 0..1.
  Future<void> setVolume(double value);

  Future<void> dispose();
}

/// The real output, over one `media_kit` [Player].
class MediaKitAudioOutput implements AudioOutput {
  MediaKitAudioOutput({Player? player}) : _player = player ?? Player();

  final Player _player;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Future<void> open(String url) => _player.open(Media(url));

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// `media_kit` takes volume as 0..100.
  @override
  Future<void> setVolume(double value) =>
      _player.setVolume((value.clamp(0.0, 1.0) * 100).toDouble());

  @override
  Future<void> dispose() => _player.dispose();
}
