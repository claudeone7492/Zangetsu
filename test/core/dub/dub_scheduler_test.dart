import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/dub/dub_scheduler.dart';
import 'package:watch_app/core/dub/srt_parser.dart';

DubCue _cue(int startSec, int endSec, String text) => DubCue(
  start: Duration(seconds: startSec),
  end: Duration(seconds: endSec),
  text: text,
);

void main() {
  group('DubScheduler', () {
    test('speaks a cue once its start is reached', () {
      final s = DubScheduler(
        cues: [_cue(1, 3, 'one'), _cue(5, 7, 'two')],
      );
      expect(s.dueAt(const Duration(milliseconds: 500)), isNull);
      expect(s.dueAt(const Duration(seconds: 1))?.text, 'one');
      expect(s.dueAt(const Duration(seconds: 2))?.text, isNull);
      expect(s.dueAt(const Duration(seconds: 5))?.text, 'two');
    });

    test('never speaks the same cue twice, even if the clock jitters back', () {
      final s = DubScheduler(cues: [_cue(1, 5, 'one')]);
      expect(s.dueAt(const Duration(seconds: 2))?.text, 'one');
      // The player's position can wobble backwards by a tick; the line must not
      // restart.
      expect(s.dueAt(const Duration(seconds: 1)), isNull);
      expect(s.dueAt(const Duration(milliseconds: 1500)), isNull);
    });

    test('a long gap does not replay the cues that were skipped', () {
      final s = DubScheduler(
        cues: [_cue(1, 2, 'a'), _cue(3, 4, 'b'), _cue(5, 6, 'c')],
      );
      // First tick lands after a and b are already over.
      expect(s.dueAt(const Duration(seconds: 5))?.text, 'c');
      expect(s.dueAt(const Duration(seconds: 6)), isNull);
    });

    test('lead time hands a cue over early', () {
      final s = DubScheduler(
        cues: [_cue(10, 12, 'ten')],
        lead: const Duration(milliseconds: 500),
      );
      expect(s.dueAt(const Duration(milliseconds: 9400)), isNull);
      expect(s.dueAt(const Duration(milliseconds: 9600))?.text, 'ten');
    });

    test('seekTo forward does not read the skipped cues', () {
      final s = DubScheduler(
        cues: [_cue(1, 2, 'a'), _cue(5, 6, 'b'), _cue(9, 10, 'c')],
      );
      s.seekTo(const Duration(seconds: 9));
      expect(s.dueAt(const Duration(seconds: 9))?.text, 'c');
    });

    test('seekTo backward lets an earlier cue be heard again', () {
      final s = DubScheduler(
        cues: [_cue(1, 3, 'a'), _cue(5, 7, 'b')],
      );
      expect(s.dueAt(const Duration(seconds: 5))?.text, 'b');
      s.seekTo(const Duration(seconds: 1));
      expect(s.dueAt(const Duration(seconds: 1))?.text, 'a');
    });

    test('seeking past the end leaves nothing to speak', () {
      final s = DubScheduler(cues: [_cue(1, 2, 'a')]);
      s.seekTo(const Duration(minutes: 5));
      expect(s.dueAt(const Duration(minutes: 5)), isNull);
      expect(s.dueAt(const Duration(seconds: 1)), isNull);
    });

    test('an empty cue list is inert', () {
      final s = DubScheduler(cues: const []);
      expect(s.isEmpty, isTrue);
      expect(s.dueAt(const Duration(seconds: 30)), isNull);
    });

    test('exposes its cues for the UI to count', () {
      final s = DubScheduler(cues: [_cue(1, 2, 'a'), _cue(3, 4, 'b')]);
      expect(s.cues, hasLength(2));
    });
  });
}
