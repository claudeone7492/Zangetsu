import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/music/music_models.dart';
import 'package:watch_app/core/music/music_queue.dart';

MusicTrack track(String id) =>
    MusicTrack(id: id, title: 'Track $id', sourceId: 'test');

List<MusicTrack> tracks(int n) => [for (var i = 0; i < n; i++) track('$i')];

void main() {
  group('cursor', () {
    test('starts on the requested track', () {
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 1);
      expect(queue.current?.id, '1');
      expect(queue.length, 3);
    });

    test('advance walks forward and stops at the end with repeat off', () {
      final queue = MusicQueue(tracks: tracks(3));
      expect(queue.current?.id, '0');
      expect(queue.advance()?.id, '1');
      expect(queue.advance()?.id, '2');
      expect(queue.advance(), isNull, reason: 'end of queue, repeat off');
      expect(queue.current?.id, '2', reason: 'cursor stays on the last track');
    });

    test('rewind walks back and holds at the start with repeat off', () {
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 2);
      expect(queue.rewind()?.id, '1');
      expect(queue.rewind()?.id, '0');
      expect(queue.rewind()?.id, '0', reason: 'no wrap without repeat all');
    });

    test('next/previous peek without moving the cursor', () {
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 1);
      expect(queue.next?.id, '2');
      expect(queue.previous?.id, '0');
      expect(queue.current?.id, '1', reason: 'peeking must not advance');
    });

    test('an empty queue has no current track and never advances', () {
      final queue = MusicQueue();
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
      expect(queue.advance(), isNull);
      expect(queue.next, isNull);
    });

    test('a single-track queue advances to itself only with repeat', () {
      final queue = MusicQueue(tracks: tracks(1));
      expect(queue.advance(), isNull);
      queue.repeat = MusicRepeat.all;
      expect(queue.advance()?.id, '0');
    });
  });

  group('repeat', () {
    test('repeat all wraps from the end to the start', () {
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 2)
        ..repeat = MusicRepeat.all;
      expect(queue.advance()?.id, '0');
      expect(queue.previous?.id, '2');
    });

    test('repeat one keeps returning the current track', () {
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 1)
        ..repeat = MusicRepeat.one;
      expect(queue.advance()?.id, '1');
      expect(queue.advance()?.id, '1');
      expect(queue.current?.id, '1');
    });

    test('repeat one still allows an explicit skip to the next track', () {
      // "Repeat one" must not trap the user: tapping skip is a deliberate
      // override, and only automatic advance repeats.
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 0)
        ..repeat = MusicRepeat.one;
      expect(queue.jumpToPosition(1), isTrue);
      expect(queue.current?.id, '1');
    });
  });

  group('shuffle', () {
    test('enabling keeps the playing track and permutes the rest', () {
      final queue = MusicQueue(
        tracks: tracks(8),
        initialIndex: 3,
        random: Random(7),
      );
      final playing = queue.current;
      queue.setShuffle(true);
      expect(queue.isShuffled, isTrue);
      expect(
        queue.current,
        playing,
        reason: 'the playing track must not change',
      );
      expect(
        queue.orderedTracks.map((t) => t.id).toSet(),
        tracks(8).map((t) => t.id).toSet(),
        reason: 'shuffle reorders, it must not drop or duplicate tracks',
      );
    });

    test('disabling shuffle restores catalogue order on the same track', () {
      final queue = MusicQueue(
        tracks: tracks(8),
        initialIndex: 2,
        shuffle: true,
        random: Random(3),
      );
      final playing = queue.current;
      queue.setShuffle(false);
      expect(queue.isShuffled, isFalse);
      expect(queue.current, playing);
      expect(queue.orderedTracks.map((t) => t.id).toList(), [
        for (var i = 0; i < 8; i++) '$i',
      ]);
    });

    test('advance follows the shuffled order, not catalogue order', () {
      final queue = MusicQueue(
        tracks: tracks(10),
        shuffle: true,
        random: Random(11),
      );
      final order = queue.orderedTracks.map((t) => t.id).toList();
      expect(queue.advance()?.id, order[1]);
      expect(queue.advance()?.id, order[2]);
    });

    test('repeat all reshuffles for the next lap', () {
      final queue = MusicQueue(
        tracks: tracks(12),
        shuffle: true,
        repeat: MusicRepeat.all,
        random: Random(5),
      );
      final firstLap = queue.orderedTracks.map((t) => t.id).toList();
      for (var i = 0; i < 11; i++) {
        queue.advance();
      }
      expect(queue.current?.id, firstLap.last);
      queue.advance(); // wraps
      expect(
        queue.orderedTracks.map((t) => t.id).toList(),
        isNot(firstLap),
        reason: 'a new lap should not replay the identical order',
      );
      expect(queue.orderedTracks.length, 12);
    });
  });

  group('jumping', () {
    test('jumpTo finds a track by identity', () {
      final queue = MusicQueue(tracks: tracks(4));
      expect(queue.jumpTo(track('2')), isTrue);
      expect(queue.current?.id, '2');
    });

    test('jumpTo reports a miss rather than moving the cursor', () {
      final queue = MusicQueue(tracks: tracks(4), initialIndex: 1);
      expect(queue.jumpTo(track('nope')), isFalse);
      expect(queue.current?.id, '1');
    });

    test('jumpToPosition rejects out-of-range positions', () {
      final queue = MusicQueue(tracks: tracks(2));
      expect(queue.jumpToPosition(-1), isFalse);
      expect(queue.jumpToPosition(2), isFalse);
      expect(queue.jumpToPosition(1), isTrue);
    });
  });

  group('replace', () {
    test('swapping the queue resets the cursor and drops the old tracks', () {
      final queue = MusicQueue(tracks: tracks(3), initialIndex: 2);
      queue.replace([track('x'), track('y')], startAt: 1);
      expect(queue.length, 2);
      expect(queue.current?.id, 'y');
      expect(queue.advance(), isNull);
    });

    test('replace clamps an out-of-range start', () {
      final queue = MusicQueue(tracks: tracks(3));
      queue.replace([track('x')], startAt: 9);
      expect(queue.current?.id, 'x');
    });

    test('replace while shuffled keeps the requested track current', () {
      final queue = MusicQueue(
        tracks: tracks(6),
        shuffle: true,
        random: Random(2),
      );
      queue.replace([track('a'), track('b'), track('c')], startAt: 2);
      expect(queue.current?.id, 'c');
      expect(queue.orderedTracks.length, 3);
    });

    test('replacing with an empty list empties the queue safely', () {
      final queue = MusicQueue(tracks: tracks(3));
      queue.replace(const []);
      expect(queue.isEmpty, isTrue);
      expect(queue.current, isNull);
      expect(queue.advance(), isNull);
    });
  });

  test('tracks is a read-only view', () {
    final queue = MusicQueue(tracks: tracks(2));
    expect(() => queue.tracks.add(track('z')), throwsUnsupportedError);
  });

  test('shuffle can be toggled on an empty queue', () {
    final q = MusicQueue();
    // Reachable from the player UI: the shuffle button exists before any list
    // has been tapped.
    expect(() => q.setShuffle(true), returnsNormally);
    expect(q.isShuffled, isTrue);
    expect(() => q.setShuffle(false), returnsNormally);
    expect(q.isShuffled, isFalse);
    expect(q.current, isNull);
  });
}
