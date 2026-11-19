import 'srt_parser.dart';

/// Decides which cue should be spoken as playback advances.
///
/// Kept free of Flutter and of the TTS engine so the hard part — deciding
/// *when* to speak, and not speaking twice — can be tested directly. The
/// caller drives it with the player's position on every tick and speaks
/// whatever comes back.
///
/// Two behaviours matter more than they look:
///
///  * **A cue is spoken once.** The player's position is sampled repeatedly and
///    may jitter backwards by a few milliseconds; without a floor, the same
///    line would restart every tick.
///  * **Seeking resets the floor.** Jumping forward must not replay every cue
///    that was skipped, and jumping back must let an earlier cue speak again.
class DubScheduler {
  DubScheduler({required List<DubCue> cues, this.lead = Duration.zero})
    : _cues = cues;

  final List<DubCue> _cues;

  /// How far ahead of the cue's start to hand it over. Speech takes a moment to
  /// begin, so a small lead makes the words land with the picture.
  final Duration lead;

  /// Index of the last cue handed out, so it is not handed out twice.
  int _lastSpoken = -1;

  List<DubCue> get cues => List.unmodifiable(_cues);
  bool get isEmpty => _cues.isEmpty;

  /// The cue that should start speaking now, or null.
  ///
  /// A cue qualifies when its lead-adjusted start has been reached and its end
  /// has not passed. Cues are scanned from the last one spoken, so a long gap
  /// in the subtitles does not replay history.
  DubCue? dueAt(Duration position) {
    if (_cues.isEmpty) return null;
    final now = position + lead;
    for (var i = _lastSpoken + 1; i < _cues.length; i++) {
      final cue = _cues[i];
      if (cue.end < now) {
        // Already over — it was skipped (a seek, or the app was backgrounded).
        // Mark it consumed so it cannot fire later.
        _lastSpoken = i;
        continue;
      }
      if (cue.start <= now) {
        _lastSpoken = i;
        return cue;
      }
      // Cues are sorted, so the first one that has not started yet ends the
      // scan: nothing after it can be due either.
      break;
    }
    return null;
  }

  /// Forget what was spoken and re-anchor at [position]: the first cue at or
  /// after it becomes eligible. Call this on every seek — forward so skipped
  /// cues are not read out in a burst, backward so the lines can be heard
  /// again.
  void seekTo(Duration position) {
    _lastSpoken = -1;
    for (var i = 0; i < _cues.length; i++) {
      if (_cues[i].start >= position) {
        _lastSpoken = i - 1;
        return;
      }
    }
    // Past the end: nothing left to speak.
    _lastSpoken = _cues.length;
  }

  /// Silence the current line without consuming the next one — used when the
  /// user pauses, so the tail of a sentence is not read over a frozen frame.
  void stop() {
    // Nothing to do: the engine is stopped by the caller. Kept as an explicit
    // hook so a future scheduler that queues cues has one place to clear.
  }
}
