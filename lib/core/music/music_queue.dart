import 'dart:math';

import 'music_models.dart';

/// What the queue should do when a track ends.
enum MusicRepeat { off, all, one }

/// An ordered playlist with a cursor.
///
/// Pure Dart on purpose: shuffle, repeat and "next/previous" are the parts of a
/// music player most likely to grow subtle bugs (skipping when shuffling,
/// wrapping at the end, repeating one track while still allowing "next"), and
/// keeping them out of the audio engine means they are cheap to test.
class MusicQueue {
  MusicQueue({
    List<MusicTrack> tracks = const [],
    int initialIndex = 0,
    this.repeat = MusicRepeat.off,
    bool shuffle = false,
    Random? random,
  }) : _tracks = List<MusicTrack>.of(tracks),
       _shuffle = shuffle,
       _random = random ?? Random() {
    _shuffledOrder = List<int>.generate(_tracks.length, (i) => i);
    if (_tracks.isEmpty) return;
    // [initialIndex] is a catalogue index; after shuffling the cursor counts
    // play-order positions instead. _applyShuffle(keepFirst:) puts the wanted
    // track at play-order 0, so the cursor is already right — overwriting it
    // with the catalogue index would land on a different track.
    if (_shuffle) {
      _applyShuffle(keepFirst: initialIndex.clamp(0, _tracks.length - 1));
    } else {
      _index = initialIndex.clamp(0, _tracks.length - 1);
    }
  }

  final List<MusicTrack> _tracks;
  final Random _random;

  /// Play order as indices into [_tracks]. Identity order when not shuffled.
  late List<int> _shuffledOrder;

  /// Position in [_shuffledOrder], not in [_tracks].
  int _index = 0;

  MusicRepeat repeat;
  bool _shuffle;

  List<MusicTrack> get tracks => List.unmodifiable(_tracks);

  bool get isEmpty => _tracks.isEmpty;

  int get length => _tracks.length;

  bool get isShuffled => _shuffle;

  MusicTrack? get current =>
      _tracks.isEmpty ? null : _tracks[_shuffledOrder[_index]];

  /// The track after [current], or null at the end with repeat off.
  MusicTrack? get next {
    if (_tracks.isEmpty) return null;
    if (repeat == MusicRepeat.one) return current;
    if (_index + 1 < _shuffledOrder.length) {
      return _tracks[_shuffledOrder[_index + 1]];
    }
    return repeat == MusicRepeat.all ? _tracks[_shuffledOrder.first] : null;
  }

  /// The track before [current], or null at the start with repeat off.
  MusicTrack? get previous {
    if (_tracks.isEmpty) return null;
    if (repeat == MusicRepeat.one) return current;
    if (_index > 0) return _tracks[_shuffledOrder[_index - 1]];
    return repeat == MusicRepeat.all ? _tracks[_shuffledOrder.last] : null;
  }

  /// Advance the cursor and return the new track. Null means playback should
  /// stop (end of queue, repeat off).
  MusicTrack? advance() {
    if (_tracks.isEmpty) return null;
    if (repeat == MusicRepeat.one) return current;
    if (_index + 1 < _shuffledOrder.length) {
      _index++;
      return current;
    }
    if (repeat == MusicRepeat.all) {
      if (_shuffle) {
        // A fresh shuffle per lap so "repeat all + shuffle" doesn't replay the
        // same order forever, with the track that just finished kept off the
        // top so a reshuffle can't immediately replay it.
        _applyShuffle(avoidFirst: _shuffledOrder[_index]);
      } else {
        _index = 0;
      }
      return current;
    }
    return null;
  }

  /// Step back and return the new track.
  MusicTrack? rewind() {
    if (_tracks.isEmpty) return null;
    if (_index > 0) {
      _index--;
      return current;
    }
    if (repeat == MusicRepeat.all) {
      _index = _shuffledOrder.length - 1;
      return current;
    }
    return current;
  }

  /// Jump to [track] if it is in the queue. Returns whether it was found.
  bool jumpTo(MusicTrack track) {
    final position = _shuffledOrder.indexOf(
      _tracks.indexWhere((t) => t == track),
    );
    if (position < 0) return false;
    _index = position;
    return true;
  }

  /// Jump to a position in play order (what the UI lists).
  bool jumpToPosition(int position) {
    if (position < 0 || position >= _shuffledOrder.length) return false;
    _index = position;
    return true;
  }

  /// The play-order list the UI should render, so the highlighted row matches
  /// what "next" will actually play.
  List<MusicTrack> get orderedTracks =>
      [for (final i in _shuffledOrder) _tracks[i]];

  /// Current position in play order.
  int get position => _index;

  /// Turn shuffle on or off.
  ///
  /// Enabling keeps the current track playing and shuffles everything after it,
  /// which is what listeners expect — re-shuffling under the playing track would
  /// silently change what "next" means. Disabling restores catalogue order and
  /// re-points the cursor at the same track.
  void setShuffle(bool value) {
    if (value == _shuffle) return;
    _shuffle = value;
    final playing = current;
    if (value) {
      _applyShuffle(keepFirst: _shuffledOrder[_index]);
    } else {
      _shuffledOrder = List<int>.generate(_tracks.length, (i) => i);
      if (playing != null) {
        final at = _tracks.indexOf(playing);
        if (at >= 0) _index = at;
      }
    }
  }

  /// Replace the queue contents, e.g. when the user taps a different row.
  void replace(List<MusicTrack> tracks, {int startAt = 0}) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _shuffledOrder = List<int>.generate(_tracks.length, (i) => i);
    _index = _tracks.isEmpty ? 0 : startAt.clamp(0, _tracks.length - 1);
    if (_shuffle) _applyShuffle(keepFirst: _tracks.isEmpty ? null : _shuffledOrder[_index]);
  }

  /// Rebuild the play order.
  ///
  /// [keepFirst] pins a track to play-order 0 (used when shuffle is switched on
  /// mid-playback, so the playing track stays current). [avoidFirst] instead
  /// keeps a track OUT of position 0 (used at a repeat-all lap boundary, so the
  /// track that just finished doesn't immediately play again).
  void _applyShuffle({int? keepFirst, int? avoidFirst}) {
    _shuffledOrder = List<int>.generate(_tracks.length, (i) => i);
    if (keepFirst != null && keepFirst >= 0 && keepFirst < _tracks.length) {
      _shuffledOrder.remove(keepFirst);
      _shuffledOrder.shuffle(_random);
      _shuffledOrder.insert(0, keepFirst);
    } else if (avoidFirst != null &&
        avoidFirst >= 0 &&
        avoidFirst < _tracks.length &&
        _tracks.length > 1) {
      _shuffledOrder.remove(avoidFirst);
      _shuffledOrder.shuffle(_random);
      _shuffledOrder.insert(1 + _random.nextInt(_shuffledOrder.length), avoidFirst);
    } else {
      _shuffledOrder.shuffle(_random);
    }
    _index = 0;
  }
}
