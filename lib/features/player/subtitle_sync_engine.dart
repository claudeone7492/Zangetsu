import 'dart:math' as math;

import '../../core/playback/subtitle_exporter.dart' show SubtitleCue;

/// A caption's own timings fitted to the film it is being played over.
///
/// A downloaded caption is timed for the release it was authored against, and
/// that is often not the release being watched. Two things go wrong, and they
/// need different corrections:
///
/// - **A constant shift.** The caption's clock starts at a different point, so
///   every line is the same amount early or late. This is the delay: `+2.5s`.
/// - **A drift.** The caption's clock *runs* at a different rate, so the lines
///   start in step and slide further out the longer the film plays. This is what
///   a caption timed for 25 fps does over a 23.976 fps release: the two rates are
///   4.3% apart, which is under a tenth of a second at the first line and over a
///   minute by the end of a two-hour film. No single delay can fix it.
///
/// A caption can suffer both at once, which is why the fit has two parameters
/// rather than one: `shown = authored * rate + delay`.
class SubtitleSyncFit {
  const SubtitleSyncFit({
    required this.rate,
    required this.delayMillis,
    required this.matchedCues,
    required this.residualMillis,
    required this.confident,
  });

  /// Multiplier on every authored timestamp. 1 when the caption is not drifting.
  final double rate;

  /// Milliseconds added after the rate. 0 when the caption is not shifted.
  final int delayMillis;

  /// Matched lines behind the fit; a fit from a handful of points is a guess.
  final int matchedCues;

  /// Milliseconds of scatter left after the fit; the smaller, the better.
  final int residualMillis;

  /// Whether the fit was trusted enough to apply.
  final bool confident;

  /// Whether applying this fit would change anything.
  bool get isIdentity =>
      matchedCues == 0 ||
      ((rate - 1).abs() < rateEpsilon && delayMillis == 0);

  /// The time an authored line should be shown at, under this fit.
  int apply(int authoredMillis) =>
      (authoredMillis * rate).round() + delayMillis;

  /// A rate this close to 1 is drift too small to be worth correcting.
  static const double rateEpsilon = 0.0005;

  /// No correction, for when there is nothing to match against.
  static const SubtitleSyncFit none = SubtitleSyncFit(
    rate: 1,
    delayMillis: 0,
    matchedCues: 0,
    residualMillis: 0,
    confident: false,
  );
}

/// Fits [target]'s timings to [reference]'s, and reports how well it could.
///
/// Both lists must be ordered by start time.
///
/// A drift cannot be found by walking the two lists in step. The window that
/// makes a match trustworthy is a second or two, and a caption timed for the
/// wrong frame rate is *minutes* out by the end of a feature — so a walk that
/// starts from the opening shift can never reach the end of the track, and a
/// least-squares fit from the part it can reach reads a genuine 4.3% drift as a
/// fraction of a percent. The rate has to be searched for, not followed.
///
/// The search is coarse and then refined, because that is enough: a caption's
/// clock differs from the film's by one of a handful of frame-rate ratios, not
/// by an arbitrary amount.
class SubtitleSyncEngine {
  const SubtitleSyncEngine._();

  /// How far from the predicted position a line may be and still count as a
  /// match.
  static const int matchWindowMillis = 1500;

  /// Fewer matched lines than this cannot separate a drift from noise.
  static const int minMatchedCues = 6;

  /// Lines examined when seeding the opening shift.
  static const int bootstrapLines = 24;

  /// How much of the reference's span the matched pairs must cover.
  static const double minCoverage = 0.25;

  /// The rates searched. Bounded to what a caption's clock can actually be out
  /// by, which is a frame-rate conversion and nothing else.
  static const double minRate = 1.0 / 1.05;
  static const double maxRate = 1.05;

  /// The rates a caption's clock is realistically out by, as exact ratios.
  ///
  /// Snapping to one is what makes the end of a long film right: the exact ratio
  /// is right to the frame, and the difference is visible on the last line.
  static const List<double> standardRates = [
    1.0,
    24.0 / 25.0, // 24 -> 25 fps
    23.976 / 25.0, // 23.976 -> 25 fps
    24.0 / 23.976, // 23.976 -> 24 fps
    25.0 / 24.0, // 25 -> 24 fps
    25.0 / 23.976, // 25 -> 23.976 fps
    30.0 / 29.97, // 29.97 -> 30 fps
    29.97 / 30.0, // 30 -> 29.97 fps
  ];

  /// How close a measured rate must be to a standard ratio before it is snapped.
  static const double snapTolerance = 3e-3;

  /// The fewest pairs a fit may be built from, as a fraction of the lines the
  /// caption could offer. Stops a fit being read into a coincidence.
  static const double minScore = 0.02;

  /// How much better a rate must explain the caption than a plain shift before
  /// it is believed.
  static const double minRateImprovement = 1.15;

  /// How finely the rate is stepped. A half-step of 1e-4 over a 2 h feature is
  /// under a second.
  static const double coarseRateStep = 1e-4;

  /// How much a refinement pass may move the rate before it is worth another.
  static const double refineEpsilon = 1e-6;

  static const int maxRefinePasses = 12;

  /// The largest scatter, in milliseconds, that a fit may leave and still be
  /// applied. Absolute, deliberately not a fraction of the span.
  static const int maxResidualMillis = 400;

  /// Fits [target] to [reference].
  ///
  /// Returns [SubtitleSyncFit.none] rather than throwing when there is too little
  /// to work with: a caption that cannot be fitted is left exactly as authored.
  static SubtitleSyncFit fit({
    required List<SubtitleCue> reference,
    required List<SubtitleCue> target,
  }) {
    if (reference.length < minMatchedCues || target.length < minMatchedCues) {
      return SubtitleSyncFit.none;
    }

    var best = _Candidate(1, 0, const []);
    for (var rate = minRate; rate <= maxRate; rate += coarseRateStep) {
      final candidate = _score(
        reference,
        target,
        rate,
        _shiftFor(reference, target, rate),
      );
      if (candidate.pairs.length > best.pairs.length) best = candidate;
    }

    // The shift alone is the null hypothesis, and a rate has to beat it clearly
    // to be believed.
    final delayOnly = _score(
      reference,
      target,
      1.0,
      _shiftFor(reference, target, 1.0),
    );
    if (best.pairs.length < delayOnly.pairs.length * minRateImprovement) {
      best = delayOnly;
    }
    if (best.pairs.length < minMatchedCues) return SubtitleSyncFit.none;

    final snapped = _snapToStandardRate(reference, target, best);
    if (snapped != null && snapped.pairs.length >= best.pairs.length) {
      best = snapped;
    }

    if (best.pairs.length <
        math.min(reference.length, target.length) * minScore) {
      return SubtitleSyncFit.none;
    }

    for (var pass = 0; pass < maxRefinePasses; pass++) {
      final measured = _leastSquares(best.pairs);
      if ((measured.rate - best.rate).abs() < refineEpsilon) continue;
      final candidate = _score(
        reference,
        target,
        measured.rate,
        measured.delayMillis,
      );
      if (candidate.pairs.length < best.pairs.length) continue;
      best = candidate;
    }

    final pairs = best.pairs;
    final referenceSpan = math.max(
      1,
      reference.last.startMillis - reference.first.startMillis,
    );
    final pairSpan = pairs.last.referenceStartMillis -
        pairs.first.referenceStartMillis;
    if (pairSpan < referenceSpan * minCoverage) return SubtitleSyncFit.none;

    final base = SubtitleSyncFit(
      rate: best.rate,
      delayMillis: best.delayMillis.round(),
      matchedCues: pairs.length,
      residualMillis: 0,
      confident: true,
    );
    final residual = _medianResidual(pairs, base);
    return SubtitleSyncFit(
      rate: base.rate,
      delayMillis: base.delayMillis,
      matchedCues: base.matchedCues,
      residualMillis: residual,
      confident: residual <= maxResidualMillis,
    );
  }

  /// The nearest frame-rate ratio to [candidate]'s rate, re-scored, or null if
  /// none is close enough.
  static _Candidate? _snapToStandardRate(
    List<SubtitleCue> reference,
    List<SubtitleCue> target,
    _Candidate candidate,
  ) {
    double? nearest;
    var bestDelta = double.infinity;
    for (final r in standardRates) {
      final d = (r - candidate.rate).abs();
      if (d < bestDelta) {
        bestDelta = d;
        nearest = r;
      }
    }
    if (nearest == null) return null;
    if ((nearest - candidate.rate).abs() > snapTolerance) return null;
    if (nearest == candidate.rate) return null;
    return _score(reference, target, nearest, _shiftFor(reference, target, nearest));
  }

  static _Candidate _score(
    List<SubtitleCue> reference,
    List<SubtitleCue> target,
    double rate,
    double delayMillis,
  ) => _Candidate(rate, delayMillis, _match(reference, target, rate, delayMillis));

  /// Pairs reference lines with caption lines, given a rate and a shift to
  /// predict with.
  ///
  /// A greedy walk rather than "nearest line to each reference line", because
  /// nearest-line mis-pairs by exactly one line whenever the caption sits near
  /// the midpoint between two reference lines.
  static List<_Pair> _match(
    List<SubtitleCue> reference,
    List<SubtitleCue> target,
    double rate,
    double delayMillis,
  ) {
    final pairs = <_Pair>[];
    var referenceIndex = 0;
    var targetIndex = 0;

    double predictedCaption(int index) =>
        (reference[index].startMillis - delayMillis) / rate;

    while (referenceIndex < reference.length && targetIndex < target.length) {
      final predicted = predictedCaption(referenceIndex);
      if ((target[targetIndex].startMillis - predicted).abs() <=
          matchWindowMillis) {
        pairs.add(
          _Pair(
            targetStartMillis: target[targetIndex].startMillis,
            referenceStartMillis: reference[referenceIndex].startMillis,
          ),
        );
        referenceIndex++;
        targetIndex++;
        continue;
      }

      final ifReferenceSkipped = referenceIndex + 1 < reference.length
          ? (target[targetIndex].startMillis -
                    predictedCaption(referenceIndex + 1))
                .abs()
          : double.maxFinite;
      final ifTargetSkipped = targetIndex + 1 < target.length
          ? (target[targetIndex + 1].startMillis - predicted).abs()
          : double.maxFinite;
      if (ifReferenceSkipped <= ifTargetSkipped) {
        referenceIndex++;
      } else {
        targetIndex++;
      }
    }

    return pairs;
  }

  /// The opening shift that best pairs the two tracks at [rate], as a median.
  ///
  /// Paired by index, not by nearest time: a caption an hour out has its line 900
  /// beside the film's line 1, and pairing by proximity would fit the two tracks
  /// to each other's *end*.
  static double _shiftFor(
    List<SubtitleCue> reference,
    List<SubtitleCue> target,
    double rate,
  ) {
    final lines = math.min(
      math.min(reference.length, target.length),
      bootstrapLines,
    );
    if (lines == 0) return 0;
    final offsets = <double>[
      for (var i = 0; i < lines; i++)
        reference[i].startMillis - rate * target[i].startMillis,
    ]..sort();
    return offsets[offsets.length ~/ 2];
  }

  /// The least-squares line through the pairs: `reference = caption * rate + delay`.
  static _Candidate _leastSquares(List<_Pair> pairs) {
    final count = pairs.length;
    final meanTarget =
        pairs.fold<double>(0, (s, p) => s + p.targetStartMillis) / count;
    final meanReference =
        pairs.fold<double>(0, (s, p) => s + p.referenceStartMillis) / count;

    var covariance = 0.0;
    var variance = 0.0;
    for (final p in pairs) {
      final dx = p.targetStartMillis - meanTarget;
      covariance += dx * (p.referenceStartMillis - meanReference);
      variance += dx * dx;
    }

    if (variance <= 0) {
      return _Candidate(1, meanReference - meanTarget, pairs);
    }

    final rate = (covariance / variance).clamp(minRate, maxRate);
    return _Candidate(rate, meanReference - rate * meanTarget, pairs);
  }

  /// The median distance between a pair and the fitted line.
  static int _medianResidual(List<_Pair> pairs, SubtitleSyncFit fit) {
    final residuals = [
      for (final p in pairs)
        (p.referenceStartMillis - fit.apply(p.targetStartMillis)).abs(),
    ]..sort();
    return residuals[residuals.length ~/ 2];
  }
}

/// One matched line: where the caption puts it, and where the reference does.
class _Pair {
  const _Pair({
    required this.targetStartMillis,
    required this.referenceStartMillis,
  });

  final int targetStartMillis;
  final int referenceStartMillis;
}

/// A candidate fit, with the pairs it matched.
class _Candidate {
  const _Candidate(this.rate, this.delayMillis, this.pairs);

  final double rate;
  final double delayMillis;
  final List<_Pair> pairs;
}
