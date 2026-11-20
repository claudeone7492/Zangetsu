import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio_output.dart';
import 'music_models.dart';
import 'music_queue.dart';
import 'music_service.dart';

/// Drives playback for music mode: owns the queue, resolves stream URLs, and
/// turns the audio output's events into state the UI can render.
///
/// The queue is pure Dart and the output is behind [AudioOutput], so the whole
/// controller runs in a test with a fake output — no libmpv, no network.
class MusicPlayerController extends ChangeNotifier {
  MusicPlayerController({
    required MusicService service,
    required AudioOutput output,
  }) : _service = service,
       _output = output {
    _subs.addAll([
      _output.positionStream.listen((p) {
        if (_position == p) return;
        _position = p;
        notifyListeners();
      }),
      _output.durationStream.listen((d) {
        if (d.inMilliseconds == 0 || _duration == d) return;
        _duration = d;
        notifyListeners();
      }),
      _output.playingStream.listen((v) {
        if (_playing == v) return;
        _playing = v;
        notifyListeners();
      }),
      _output.bufferingStream.listen((v) {
        if (_buffering == v) return;
        _buffering = v;
        notifyListeners();
      }),
      _output.completedStream.listen((done) {
        if (done) unawaited(_onTrackEnded());
      }),
    ]);
  }

  final MusicService _service;
  final AudioOutput _output;
  final List<StreamSubscription<Object?>> _subs = [];

  final MusicQueue _queue = MusicQueue();

  MusicTrack? _current;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  String? _error;
  double _volume = 1;

  /// Bumped on every load. A slow URL resolve for a track the user has already
  /// skipped past must not start playing over the new one.
  int _loadGeneration = 0;

  MusicQueue get queue => _queue;
  MusicTrack? get current => _current;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get playing => _playing;
  bool get buffering => _buffering;
  bool get hasTrack => _current != null;
  String? get error => _error;
  bool get shuffle => _queue.isShuffled;
  MusicRepeat get repeat => _queue.repeat;
  double get volume => _volume;

  /// The queue in play order, which is what the UI should list so the
  /// highlighted row matches what "next" will play.
  List<MusicTrack> get upNext => _queue.orderedTracks;

  /// Start [tracks] from [startAt], replacing whatever was playing.
  Future<void> playAll(List<MusicTrack> tracks, {int startAt = 0}) async {
    if (tracks.isEmpty) return;
    _queue.replace(tracks, startAt: startAt);
    await _load(_queue.current, play: true);
  }

  /// Play [track] and everything after it in [tracks], so tapping a row in a
  /// list starts that list rather than a one-song queue.
  Future<void> playFrom(List<MusicTrack> tracks, MusicTrack track) {
    final index = tracks.indexOf(track);
    return playAll(tracks, startAt: index < 0 ? 0 : index);
  }

  /// Jump to an existing queue entry.
  Future<void> jumpTo(int position) async {
    if (!_queue.jumpToPosition(position)) return;
    await _load(_queue.current, play: true);
  }

  Future<void> next() async {
    final track = _queue.advance();
    if (track == null) {
      await _output.pause();
      return;
    }
    await _load(track, play: true);
  }

  Future<void> previous() async {
    // Standard music-player behaviour: restart the track unless the listener
    // is near its start, where "previous" is what they must have meant.
    if (_position > const Duration(seconds: 3)) {
      await _output.seek(Duration.zero);
      return;
    }
    final track = _queue.rewind();
    if (track == null) return;
    await _load(track, play: true);
  }

  Future<void> togglePlayPause() async {
    if (_current == null) {
      final first = _queue.current;
      if (first == null) return;
      await _load(first, play: true);
      return;
    }
    if (_playing) {
      await _output.pause();
    } else {
      await _output.play();
    }
  }

  Future<void> seek(Duration position) async {
    final clamped = position < Duration.zero
        ? Duration.zero
        : (_duration > Duration.zero && position > _duration
              ? _duration
              : position);
    await _output.seek(clamped);
    _position = clamped;
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await _output.setVolume(_volume);
    notifyListeners();
  }

  void setShuffle(bool value) {
    if (value == _queue.isShuffled) return;
    _queue.setShuffle(value);
    notifyListeners();
  }

  void cycleRepeat() {
    _queue.repeat = switch (_queue.repeat) {
      MusicRepeat.off => MusicRepeat.all,
      MusicRepeat.all => MusicRepeat.one,
      MusicRepeat.one => MusicRepeat.off,
    };
    notifyListeners();
  }

  Future<void> stop() async {
    _loadGeneration++;
    await _output.stop();
    _current = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _playing = false;
    notifyListeners();
  }

  /// Clear a surfaced error once the UI has shown it.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<void> _onTrackEnded() async {
    // A finished track is the queue's cue to advance, not a pause.
    final track = _queue.advance();
    if (track == null) {
      _playing = false;
      notifyListeners();
      return;
    }
    await _load(track, play: true);
  }

  Future<void> _load(MusicTrack? track, {required bool play}) async {
    if (track == null) return;
    final generation = ++_loadGeneration;
    _current = track;
    _position = Duration.zero;
    _duration = track.duration ?? Duration.zero;
    _error = null;
    _buffering = true;
    notifyListeners();

    final url = await _service.streamFor(track);
    if (generation != _loadGeneration) return;

    if (url == null || url.isEmpty) {
      _buffering = false;
      _error = 'Couldn\'t play this song';
      _playing = false;
      notifyListeners();
      return;
    }

    try {
      await _output.open(url);
      if (generation != _loadGeneration) return;
      await _output.setVolume(_volume);
      if (play) await _output.play();
    } catch (e) {
      if (generation != _loadGeneration) return;
      _buffering = false;
      _playing = false;
      _error = 'Couldn\'t play this song';
      debugPrint('[music] playback failed: $e');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    unawaited(_output.dispose());
    super.dispose();
  }
}
