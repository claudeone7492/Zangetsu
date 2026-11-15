// The placement solver is the port of the reference player's caption placement
// engine: it keeps a caption readable by moving it before it shrinks it, and by
// pulling it towards the speaker when the style asks for that. These pin the
// behaviour that matters — a caption never leaves the frame, a face is avoided
// harder than a graphic, and the anchor mode never follows a speaker.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/subtitle_layout.dart';

void main() {
  const screen = SubtitleRect(0, 0, 1000, 1000);

  SubtitleRect block({double height = 80, double width = 600}) => SubtitleRect(
    (1000 - width) / 2,
    900 - height,
    (1000 - width) / 2 + width,
    900,
  );

  const placement = SubtitlePlacement();

  group('SubtitleRect', () {
    test('overlap is detected and measured', () {
      const a = SubtitleRect(0, 0, 100, 50);
      const b = SubtitleRect(50, 25, 150, 75);
      expect(a.overlaps(b), isTrue);
      expect(a.overlapFraction(b), closeTo(0.25, 0.001));
    });

    test('touching edges do not count as overlapping', () {
      const a = SubtitleRect(0, 0, 100, 50);
      const b = SubtitleRect(100, 0, 200, 50);
      expect(a.overlaps(b), isFalse);
      expect(a.overlapFraction(b), 0);
    });

    test('a padding gap is what makes a near miss count', () {
      const a = SubtitleRect(0, 0, 100, 50);
      const b = SubtitleRect(103, 0, 200, 50);
      expect(a.overlaps(b), isFalse);
      expect(a.overlaps(b, 5), isTrue);
    });

    test('scaling about a point keeps that point fixed', () {
      const rect = SubtitleRect(0, 0, 100, 50);
      final scaled = rect.scaledAbout(50, 25, 0.5);
      expect(scaled.width, closeTo(50, 0.0001));
      expect(scaled.height, closeTo(25, 0.0001));
      expect(scaled.centerX, closeTo(50, 0.0001));
      expect(scaled.centerY, closeTo(25, 0.0001));
    });
  });

  group('SubtitlePlacementSolver', () {
    test('with nothing in the way the block stays where it was put', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: placement,
      );
      expect(result.rect.left, closeTo(block().left, 0.01));
      expect(result.scale, 1);
      expect(result.shifted, isFalse);
      expect(result.residualOverlap, 0);
    });

    test('an empty or degenerate block is passed through', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: const SubtitleRect(0, 0, 0, 0),
        placement: placement,
        obstacles: const [
          SubtitleObstacle(SubtitleRect(0, 0, 500, 500), ObstacleKind.speaker),
        ],
      );
      expect(result.rect.width, 0);
    });

    test('a lower third graphic pushes the caption up', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: placement,
        obstacles: const [
          SubtitleObstacle(
            SubtitleRect(100, 830, 900, 1000),
            ObstacleKind.lowerThird,
          ),
        ],
      );
      expect(result.rect.top, lessThan(830));
      expect(result.residualOverlap, closeTo(0, 0.001));
      expect(result.shifted, isTrue);
    });

    test('the caption never leaves the top of the screen', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: const SubtitlePlacement(
          allowScale: false,
          maxShiftFraction: 0.5,
        ),
        obstacles: const [
          SubtitleObstacle(
            SubtitleRect(0, 500, 1000, 1000),
            ObstacleKind.burnedInText,
          ),
        ],
      );
      expect(result.rect.top, greaterThanOrEqualTo(screen.top - 0.01));
      expect(result.rect.bottom, lessThanOrEqualTo(screen.bottom + 0.01));
    });

    test('a face is avoided harder than a graphic of the same size', () {
      const rect = SubtitleRect(200, 840, 800, 1000);
      final graphic = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: const SubtitlePlacement(allowScale: false),
        obstacles: const [
          SubtitleObstacle(rect, ObstacleKind.lowerThird),
        ],
      );
      final face = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: const SubtitlePlacement(allowScale: false),
        obstacles: const [
          SubtitleObstacle(rect, ObstacleKind.speaker, priority: 3),
        ],
      );
      expect(
        face.residualOverlap,
        lessThanOrEqualTo(graphic.residualOverlap + 0.0001),
      );
    });

    test('speaker tracking pulls the caption towards the speaker', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: const SubtitlePlacement(
          mode: SubtitlePlacementMode.speaker,
        ),
        obstacles: const [
          SubtitleObstacle(
            SubtitleRect(700, 400, 850, 550),
            ObstacleKind.speaker,
          ),
        ],
      );
      expect(result.rect.centerX, greaterThan(500));
      expect(result.trackedSpeaker, isNotNull);
    });

    test('speaker tracking stays inside the frame', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: const SubtitlePlacement(
          mode: SubtitlePlacementMode.speaker,
        ),
        obstacles: const [
          SubtitleObstacle(
            SubtitleRect(980, 400, 1000, 550),
            ObstacleKind.speaker,
          ),
        ],
      );
      expect(result.rect.left, greaterThanOrEqualTo(screen.left - 0.01));
      expect(result.rect.right, lessThanOrEqualTo(screen.right + 0.01));
    });

    test('the anchor mode does not follow a speaker', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: placement,
        obstacles: const [
          SubtitleObstacle(
            SubtitleRect(700, 400, 850, 550),
            ObstacleKind.speaker,
          ),
        ],
      );
      expect(result.trackedSpeaker, isNull);
      expect(result.rect.centerX, closeTo(block().centerX, 1));
    });

    test('when nothing clears, the block shrinks rather than being covered', () {
      final result = SubtitlePlacementSolver.solve(
        screen: screen,
        block: block(),
        placement: const SubtitlePlacement(
          allowScale: true,
          minScale: 0.6,
          maxShiftFraction: 0.05,
        ),
        obstacles: const [
          SubtitleObstacle(
            SubtitleRect(0, 820, 1000, 900),
            ObstacleKind.burnedInText,
          ),
        ],
        gapPx: 4,
      );
      expect(result.residualOverlap, lessThanOrEqualTo(0.5));
    });

    test('clampToSafeArea leaves an in-frame block untouched', () {
      final inFrame = block();
      expect(
        SubtitlePlacementSolver.clampToSafeArea(inFrame, screen),
        inFrame,
      );
    });
  });
}
