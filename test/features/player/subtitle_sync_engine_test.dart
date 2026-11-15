// Guards the fit that puts a downloaded caption back in step with the film.
//
// Two failures matter and both are tested here. A fit that does not find a drift
// leaves the caption sliding out over the film — the exact complaint this exists
// to fix — and a fit that invents one from noise moves lines that were already
// correct, which is worse than leaving them alone. The confidence gate is the
// thing that separates the two, so it is tested from both sides.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitle_exporter.dart'
    show SubtitleCue;
import 'package:watch_app/features/player/subtitle_sync_engine.dart';

void main() {
  SubtitleCue cue(int startMillis, {int? endMillis, String text = 'L'}) =>
      SubtitleCue(
        startMillis: startMillis,
        endMillis: endMillis ?? startMillis + 1500,
        text: text,
      );

  /// A timeline of [count] lines, [spacing] apart, with `start * rate + delay`
  /// applied — the way a real pair of tracks relates.
  List<SubtitleCue> timeline(
    int count, {
    int spacing = 4000,
    double rate = 1.0,
    int delay = 0,
    int offset = 0,
  }) => [
    for (var i = 0; i < count; i++)
      cue((offset + i * spacing) * rate ~/ 1 + delay, text: 'Line $i'),
  ];

  test('a caption that already fits reports no correction', () {
    final reference = timeline(60);
    final fit = SubtitleSyncEngine.fit(
      reference: reference,
      target: timeline(60),
    );
    expect(fit.confident, isTrue);
    expect(fit.rate, closeTo(1, 0.002));
    expect(fit.delayMillis, 0);
    expect(fit.isIdentity, isTrue);
  });

  test('a caption that runs late is pulled back', () {
    final fit = SubtitleSyncEngine.fit(
      reference: timeline(60),
      target: timeline(60, delay: 2500),
    );
    expect(fit.confident, isTrue);
    expect(fit.rate, closeTo(1, 0.002));
    expect(fit.delayMillis, -2500);
  });

  test('a caption that starts minutes out is still matched', () {
    final fit = SubtitleSyncEngine.fit(
      reference: timeline(60),
      target: timeline(60, delay: -125000),
    );
    expect(fit.confident, isTrue);
    expect(fit.delayMillis, 125000);
  });

  test('a caption timed for the wrong frame rate is measured as a drift', () {
    final reference = timeline(900, spacing: 5000);
    final caption = timeline(900, spacing: 5000, rate: 25.0 / 23.976);
    final fit = SubtitleSyncEngine.fit(reference: reference, target: caption);
    expect(fit.confident, isTrue, reason: 'a 4.3% drift must be found');
    expect(fit.rate, closeTo(23.976 / 25.0, 0.001));
    final lastAuthored = caption.last.startMillis;
    expect(
      (fit.apply(lastAuthored) - reference.last.startMillis).abs(),
      lessThanOrEqualTo(250),
    );
  });

  test('a drift and a shift together are both corrected', () {
    final reference = timeline(900, spacing: 5000);
    final caption = timeline(900, spacing: 5000, rate: 1.0427, delay: 3000);
    final fit = SubtitleSyncEngine.fit(reference: reference, target: caption);
    expect(fit.confident, isTrue);
    expect(fit.rate, closeTo(1 / 1.0427, 0.002));
    expect(
      (fit.apply(caption.first.startMillis) - reference.first.startMillis).abs(),
      lessThanOrEqualTo(250),
    );
    expect(
      (fit.apply(caption.last.startMillis) - reference.last.startMillis).abs(),
      lessThanOrEqualTo(250),
    );
  });

  test('a caption from a different film is refused', () {
    final reference = timeline(40, spacing: 4000);
    final unrelated = [
      for (var i = 0; i < 40; i++) cue(i * 37, text: 'Other $i'),
    ];
    final fit = SubtitleSyncEngine.fit(
      reference: reference,
      target: unrelated,
    );
    expect(fit.confident, isFalse);
  });

  test('too little to work with is refused rather than guessed', () {
    final fit = SubtitleSyncEngine.fit(
      reference: timeline(3),
      target: timeline(3, delay: 1000),
    );
    expect(fit.matchedCues, 0);
    expect(fit.confident, isFalse);
    expect(fit.isIdentity, isTrue);
  });

  test('a caption covering only the start is refused', () {
    final fit = SubtitleSyncEngine.fit(
      reference: timeline(200, spacing: 4000),
      target: timeline(40, spacing: 4000, delay: 1000),
    );
    expect(fit.confident, isFalse);
  });

  test('a caption that is merely offset is given a shift, not a rate', () {
    final reference = timeline(600, spacing: 5000);
    final caption = timeline(600, spacing: 5000, delay: 1800);
    final fit = SubtitleSyncEngine.fit(reference: reference, target: caption);
    expect(fit.confident, isTrue);
    expect(fit.rate, closeTo(1, 0.0001), reason: 'no rate for an offset');
    expect(fit.delayMillis, -1800);
    expect(
      (fit.apply(caption.last.startMillis) - reference.last.startMillis).abs(),
      lessThanOrEqualTo(250),
    );
  });

  test('a short reference does not invent a drift', () {
    final reference = timeline(600, spacing: 5000);
    final caption = timeline(600, spacing: 5000, delay: 900);
    final fit = SubtitleSyncEngine.fit(
      reference: reference.take(20).toList(),
      target: caption.take(20).toList(),
    );
    expect(fit.confident, isTrue);
    expect(fit.rate, closeTo(1, 0.0001));
  });

  test('a frame-rate drift is snapped to the exact ratio', () {
    final reference = timeline(900, spacing: 4000);
    final caption = [
      for (final c in reference)
        cue(
          (c.startMillis * 23.976 / 25.0).round(),
          endMillis: (c.endMillis * 23.976 / 25.0).round(),
          text: c.text,
        ),
    ];
    final fit = SubtitleSyncEngine.fit(reference: reference, target: caption);
    expect(fit.confident, isTrue);
    expect(fit.rate, closeTo(25 / 23.976, 0.0005));
  });

  test('a caption on a different rhythm is refused', () {
    final reference = timeline(200, spacing: 7000);
    final denser = [
      for (var i = 0; i < 200; i++)
        cue(500 + i * 3100, endMillis: 1700 + i * 3100, text: 'd$i'),
    ];
    final fit = SubtitleSyncEngine.fit(reference: reference, target: denser);
    expect(fit.confident, isFalse);
  });

  test('a fit measured from the opening still lands the end', () {
    final reference = timeline(1200, spacing: 5000);
    final caption = timeline(1200, spacing: 5000, rate: 25.0 / 23.976);
    final fit = SubtitleSyncEngine.fit(
      reference: reference.take(20).toList(),
      target: caption.take(20).toList(),
    );
    expect(fit.confident, isTrue, reason: 'twenty lines must measure the drift');
    expect(
      (fit.apply(caption.last.startMillis) - reference.last.startMillis).abs(),
      lessThanOrEqualTo(250),
    );
  });

  test('the fit maps an authored time to where the line belongs', () {
    const fit = SubtitleSyncFit(
      rate: 1.04,
      delayMillis: 2000,
      matchedCues: 50,
      residualMillis: 40,
      confident: true,
    );
    expect(fit.apply(100000), 2000 + 104000);
  });
}
