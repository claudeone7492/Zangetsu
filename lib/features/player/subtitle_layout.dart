import 'dart:math' as math;

/// Where a caption sits on the picture, as fractions of the frame.
///
/// This is the model behind dragging the caption. It is deliberately tiny and
/// pure: the drag gesture writes it, the studio's position controls write it,
/// and the renderer reads it, so all three agree on one pair of numbers instead
/// of each keeping its own idea of "where the subtitle is".
///
/// The anchor is bounded by the screen and nothing else, so a caption can be
/// dragged to every edge — the top, the bottom and both sides. What keeps the
/// text readable is not a bound on the anchor but the block being kept inside
/// the frame where it is drawn, which is what stops a drag from pushing half a
/// line off the picture. An earlier model bounded the anchor well inside the
/// frame as well, which put a band around the edges that a drag could not enter.
class SubtitleLayout {
  const SubtitleLayout({this.anchorX = 0.5, this.anchorY = 0.95});

  /// The block's horizontal centre, 0 (left) … 1 (right). 0.5 is centred.
  final double anchorX;

  /// The block's vertical position, 0 (top) … 1 (bottom). The default sits the
  /// caption near the bottom, where a viewer expects it.
  final double anchorY;

  /// This layout with the anchor set to a position.
  ///
  /// A drag passes the whole target rather than a delta because the settings
  /// behind this are written asynchronously: a delta would be applied against
  /// whatever the store had caught up to, so during a fast drag the caption
  /// would fall behind the finger. An absolute target has nothing to read back
  /// and so cannot race.
  SubtitleLayout movedTo({required double anchorX, required double anchorY}) =>
      SubtitleLayout(
        anchorX: anchorX.clamp(0.0, 1.0),
        anchorY: anchorY.clamp(0.0, 1.0),
      );

  /// This layout moved by a drag, as fractions of the screen.
  SubtitleLayout dragged({required double dxFraction, required double dyFraction}) =>
      movedTo(anchorX: anchorX + dxFraction, anchorY: anchorY + dyFraction);

  @override
  bool operator ==(Object other) =>
      other is SubtitleLayout &&
      other.anchorX == anchorX &&
      other.anchorY == anchorY;

  @override
  int get hashCode => Object.hash(anchorX, anchorY);
}

/// A rectangle in screen pixels.
///
/// Deliberately not a widget geometry type: the placement solver has to be
/// testable without a device, so it works on plain numbers.
class SubtitleRect {
  const SubtitleRect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  /// True when the two overlap once each is grown by its own [padding].
  bool overlaps(SubtitleRect other, [double padding = 0]) =>
      left - padding < other.right &&
      right + padding > other.left &&
      top - padding < other.bottom &&
      bottom + padding > other.top;

  /// How much area the two share, as a fraction of this rectangle.
  double overlapFraction(SubtitleRect other) {
    final overlapWidth =
        math.min(right, other.right) - math.max(left, other.left);
    final overlapHeight =
        math.min(bottom, other.bottom) - math.max(top, other.top);
    if (overlapWidth <= 0 || overlapHeight <= 0) return 0;
    final area = width * height;
    if (area <= 0) return 0;
    return (overlapWidth * overlapHeight) / area;
  }

  SubtitleRect translated(double dx, double dy) =>
      SubtitleRect(left + dx, top + dy, right + dx, bottom + dy);

  /// This rectangle scaled about a point, so a shrink can keep the bottom edge
  /// (where the text is anchored) fixed.
  SubtitleRect scaledAbout(double anchorX, double anchorY, double factor) {
    final halfWidth = width / 2 * factor;
    final halfHeight = height / 2 * factor;
    return SubtitleRect(
      anchorX - halfWidth,
      anchorY - halfHeight,
      anchorX + halfWidth,
      anchorY + halfHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleRect &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'SubtitleRect($left, $top, $right, $bottom)';
}

/// Something on screen the caption must not sit on top of.
///
/// A speaker, a burned-in title, a lower-third graphic, a phone notch and a
/// hardware bezel are all the same kind of thing to the solver — a rectangle to
/// avoid — which is why there is one type rather than four. The only difference
/// is how much they matter, which is what [priority] carries.
class SubtitleObstacle {
  const SubtitleObstacle(this.rect, this.kind, {this.priority = 0});

  final SubtitleRect rect;
  final ObstacleKind kind;

  /// Higher is avoided harder. A speaker's face outranks a lower-third graphic.
  final int priority;
}

enum ObstacleKind {
  /// A face or a speaking region, from speaker detection.
  speaker,

  /// Burned-in text: credits, place names, already-rendered captions.
  burnedInText,

  /// Logos, score bugs, news tickers.
  lowerThird,

  /// A camera cut-out or a notch in the display.
  cutout,

  /// A hardware bezel or a rounded corner.
  bezel,

  /// The status bar, the navigation bar, or the player's own controls.
  systemInset,
}

/// How the block is allowed to be placed.
enum SubtitlePlacementMode {
  /// Always the configured anchor.
  anchor,

  /// Follows the active speaker's side of the frame.
  speaker,

  /// Moves when something occupies the anchor, but does not follow a speaker.
  collision,

  /// Speaker tracking and anti-collision together.
  adaptive;

  bool get tracksSpeaker => this == speaker || this == adaptive;
}

/// The numbers behind [SubtitlePlacementMode].
class SubtitlePlacement {
  const SubtitlePlacement({
    this.mode = SubtitlePlacementMode.anchor,
    this.maxShiftFraction = 0.28,
    this.allowScale = true,
    this.minScale = 0.75,
    this.collisionGap = 6,
    this.respectSystemInsets = true,
  });

  final SubtitlePlacementMode mode;

  /// Fraction of the screen height the block may move up from its anchor.
  final double maxShiftFraction;

  /// Whether the block may shrink to fit a tighter gap.
  final bool allowScale;

  /// The smallest it may shrink to.
  final double minScale;

  /// How close two blocks may come before they are considered to collide.
  final double collisionGap;

  /// Whether the block avoids the status bar and the navigation bar.
  final bool respectSystemInsets;
}

/// Where a caption should be drawn, after speaker tracking and collision
/// avoidance.
class SubtitlePlacementResult {
  const SubtitlePlacementResult({
    required this.rect,
    required this.scale,
    required this.residualOverlap,
    required this.shifted,
    required this.scaled,
    required this.trackedSpeaker,
  });

  final SubtitleRect rect;
  final double scale;

  /// How much of the block is still covered, 0..1. Zero is a clean placement.
  final double residualOverlap;

  /// Whether the block had to be moved from the configured anchor.
  final bool shifted;

  /// Whether the block had to be shrunk.
  final bool scaled;

  /// The speaker the block was pulled towards, if any.
  final SubtitleObstacle? trackedSpeaker;
}

/// Places a caption so it stays readable.
///
/// Two things happen, in this order, and the order matters:
///
/// 1. **Speaker tracking** biases the block horizontally towards the active
///    speaker, clamped to the safe width. Doing this first means collision
///    avoidance starts from the side the caption wants to be on.
/// 2. **Collision avoidance** moves the block up, and then shrinks it, until it
///    clears. Moving is tried before shrinking because shrinking costs the
///    viewer legibility, while moving costs them nothing.
///
/// The search is a small fixed sweep rather than a solver: a caption has to be
/// placed inside one frame, and a bounded search that is always correct enough
/// beats an optimum that sometimes misses its deadline.
class SubtitlePlacementSolver {
  const SubtitlePlacementSolver._();

  /// How many vertical positions are tried before shrinking.
  static const int shiftSteps = 24;

  /// How many sizes are tried before giving up and taking the least-bad one.
  static const int scaleSteps = 6;

  /// How hard the block is pulled towards a speaker, 0..1.
  static const double speakerPull = 0.75;

  static const double _priorityWeight = 0.5;
  static const double _nearMissPenalty = 0.05;

  /// Keeps [block] inside [screen], moving it only as far as it must.
  ///
  /// A caption already inside the safe area is returned unchanged, so this
  /// cannot drift a deliberately-placed line.
  static SubtitleRect clampToSafeArea(SubtitleRect block, SubtitleRect screen) {
    if (block.width <= 0 ||
        block.height <= 0 ||
        screen.width <= 0 ||
        screen.height <= 0) {
      return block;
    }
    final left = block.left
        .clamp(screen.left, math.max(screen.left, screen.right - block.width))
        .toDouble();
    final top = block.top
        .clamp(screen.top, math.max(screen.top, screen.bottom - block.height))
        .toDouble();
    return SubtitleRect(left, top, left + block.width, top + block.height);
  }

  /// Resolves the placement.
  ///
  /// [screen] is the drawable area in pixels, already excluding any inset the
  /// caller wants respected. [block] is the caption's natural size at its
  /// configured scale. [obstacles] is everything to avoid.
  static SubtitlePlacementResult solve({
    required SubtitleRect screen,
    required SubtitleRect block,
    required SubtitlePlacement placement,
    List<SubtitleObstacle> obstacles = const [],
    double gapPx = 0,
  }) {
    if (block.width <= 0 ||
        block.height <= 0 ||
        screen.width <= 0 ||
        screen.height <= 0) {
      return SubtitlePlacementResult(
        rect: block,
        scale: 1,
        residualOverlap: 0,
        shifted: false,
        scaled: false,
        trackedSpeaker: null,
      );
    }

    final anchor = _anchorRect(screen, block, placement);
    final relevant = obstacles
        .where((o) => o.rect.width > 0 && o.rect.height > 0)
        .toList();

    final speaker = placement.mode.tracksSpeaker
        ? _pickSpeaker(anchor, relevant)
        : null;

    final tracked = speaker != null
        ? _pullTowards(anchor, speaker.rect, screen)
        : anchor;

    final resolved = _resolve(tracked, screen, relevant, placement, gapPx);
    final shifted =
        (resolved.rect.centerY - anchor.centerY).abs() > 1 ||
        (resolved.rect.centerX - anchor.centerX).abs() > 1;
    return SubtitlePlacementResult(
      rect: resolved.rect,
      scale: resolved.scale,
      residualOverlap: resolved.residualOverlap,
      shifted: shifted,
      scaled: resolved.scaled,
      trackedSpeaker: speaker,
    );
  }

  /// The block's position at the configured anchor, before anything moves it.
  ///
  /// The caller has already baked the anchor into [block]'s top. What is left is
  /// to clamp the block inside the safe area.
  static SubtitleRect _anchorRect(
    SubtitleRect screen,
    SubtitleRect block,
    SubtitlePlacement placement,
  ) {
    final maxShift = screen.height * placement.maxShiftFraction.clamp(0.0, 0.9).toDouble();
    final lowestTop = screen.bottom - block.height;
    final highestTop = math.max(screen.top, lowestTop - maxShift);
    final top = block.top
        .clamp(highestTop, math.max(highestTop, lowestTop))
        .toDouble();
    final left = block.left
        .clamp(screen.left, math.max(screen.left, screen.right - block.width))
        .toDouble();
    return SubtitleRect(left, top, left + block.width, top + block.height);
  }

  /// The speaker the caption should follow: nearest the anchor, weighted by
  /// priority.
  ///
  /// Nearest rather than most-important, because a caption that jumps to a face
  /// on the far side of the frame is more distracting than one that stays where
  /// the last speaker was.
  static SubtitleObstacle? _pickSpeaker(
    SubtitleRect anchor,
    List<SubtitleObstacle> obstacles,
  ) {
    final speakers = obstacles
        .where((o) => o.kind == ObstacleKind.speaker)
        .toList();
    if (speakers.isEmpty) return null;
    SubtitleObstacle? best;
    var bestScore = double.infinity;
    for (final o in speakers) {
      // Horizontal distance dominates: a caption moves sideways to follow a
      // speaker, and moving it up to follow one would put it over the picture.
      final horizontal =
          (o.rect.centerX - anchor.centerX).abs() /
          math.max(1, anchor.width);
      final vertical =
          (o.rect.centerY - anchor.centerY).abs() /
          math.max(1, anchor.height);
      final score = horizontal * 2 + vertical - o.priority * 0.1;
      if (score < bestScore) {
        bestScore = score;
        best = o;
      }
    }
    return best;
  }

  /// Moves [rect] sideways towards [target], never past the safe area or by more
  /// than the pull.
  static SubtitleRect _pullTowards(
    SubtitleRect rect,
    SubtitleRect target,
    SubtitleRect screen,
  ) {
    final desiredCenter =
        rect.centerX + (target.centerX - rect.centerX) * speakerPull;
    final halfWidth = rect.width / 2;
    final minCenter = screen.left + halfWidth;
    final clampedCenter = desiredCenter.clamp(
      minCenter,
      math.max(minCenter, screen.right - halfWidth),
    );
    return rect.translated(clampedCenter - rect.centerX, 0);
  }

  /// Finds the best position and size for the block.
  ///
  /// Shifts are tried first, from the anchor upwards, because moving costs the
  /// viewer nothing. Shrinking is tried only if no shift clears the obstacles,
  /// because it costs legibility. If nothing is clean, the least-covered
  /// placement wins.
  static SubtitlePlacementResult _resolve(
    SubtitleRect start,
    SubtitleRect screen,
    List<SubtitleObstacle> obstacles,
    SubtitlePlacement placement,
    double gapPx,
  ) {
    final maxShift = screen.height * placement.maxShiftFraction.clamp(0.0, 0.9).toDouble();

    var best = start;
    var bestOverlap = _coverage(start, obstacles, gapPx);
    var bestScale = 1.0;

    if (bestOverlap <= 0) {
      return SubtitlePlacementResult(
        rect: start,
        scale: 1,
        residualOverlap: 0,
        shifted: false,
        scaled: false,
        trackedSpeaker: null,
      );
    }

    // 1. Shift upwards, keeping the size.
    for (var step = 1; step <= shiftSteps; step++) {
      final fraction = step / shiftSteps;
      final candidate = start.translated(0, -maxShift * fraction);
      if (candidate.top < screen.top) break;
      final overlap = _coverage(candidate, obstacles, gapPx);
      if (overlap < bestOverlap) {
        best = candidate;
        bestOverlap = overlap;
      }
      if (overlap <= 0) {
        return SubtitlePlacementResult(
          rect: candidate,
          scale: 1,
          residualOverlap: 0,
          shifted: true,
          scaled: false,
          trackedSpeaker: null,
        );
      }
    }

    // 2. Shrink, if allowed, and re-shift from the smaller size.
    if (placement.allowScale) {
      final minScale = placement.minScale.clamp(0.3, 1.0);
      for (var step = 1; step <= scaleSteps; step++) {
        final scale = 1 - (1 - minScale) * (step / scaleSteps);
        final smaller = start.scaledAbout(start.centerX, start.bottom, scale);
        if (smaller.height <= 0 || smaller.width <= 0) continue;
        final anchoredLeft = smaller.left
            .clamp(screen.left, math.max(screen.left, screen.right - smaller.width))
            .toDouble();
        final anchoredTop = math.max(screen.top, start.bottom - smaller.height);
        final fixed = SubtitleRect(
          anchoredLeft,
          anchoredTop,
          anchoredLeft + smaller.width,
          anchoredTop + smaller.height,
        );
        for (var shiftStep = 0; shiftStep <= shiftSteps; shiftStep++) {
          final dy = -maxShift * (shiftStep / shiftSteps);
          final candidate = fixed.translated(0, dy);
          if (candidate.top < screen.top) break;
          final overlap = _coverage(candidate, obstacles, gapPx);
          if (overlap < bestOverlap) {
            best = candidate;
            bestOverlap = overlap;
            bestScale = scale;
          }
          if (overlap <= 0) {
            return SubtitlePlacementResult(
              rect: candidate,
              scale: scale,
              residualOverlap: 0,
              shifted: true,
              scaled: true,
              trackedSpeaker: null,
            );
          }
        }
      }
    }

    return SubtitlePlacementResult(
      rect: best,
      scale: bestScale,
      residualOverlap: bestOverlap,
      shifted: true,
      scaled: bestScale < 1,
      trackedSpeaker: null,
    );
  }

  /// How badly [rect] is covered, weighted so a face counts for more than a
  /// graphic.
  static double _coverage(
    SubtitleRect rect,
    List<SubtitleObstacle> obstacles,
    double gapPx,
  ) {
    var total = 0.0;
    for (final o in obstacles) {
      final share = rect.overlapFraction(o.rect);
      if (share > 0) {
        total += share * (1 + o.priority * _priorityWeight);
      } else if (rect.overlaps(o.rect, gapPx)) {
        // Close enough to look cramped, but not actually covered: a small
        // penalty, so a placement with breathing room is preferred.
        total += _nearMissPenalty;
      }
    }
    return total;
  }
}
