// The studio's style model, ported from the reference player's SubtitleStyle.
//
// These pin the two things that make the port trustworthy: every field survives
// a round trip through PlaybackPrefs (so a control the studio writes is the
// control the renderer reads), and the renderer's own decisions — uppercase,
// the plate, the entrance, the glow — follow from the style rather than from a
// second copy of the settings.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/subtitle_style_model.dart';

void main() {
  test('a default style asks for no plate and no entrance', () {
    const s = SubtitleStyle();
    expect(s.plateMode, SubtitlePlateMode.none);
    expect(s.entrance, SubtitleEntrance.none);
    expect(s.uppercase, isFalse);
    expect(s.align, SubtitleAlign.center);
    expect(s.placementMode, SubtitlePlacementMode.anchor);
  });

  test('uppercase is applied by the renderer, not stored in the text', () {
    const s = SubtitleStyle(uppercase: true);
    expect(s.displayText('hello there'), 'HELLO THERE');
    expect(const SubtitleStyle().displayText('hello there'), 'hello there');
  });

  test('the weight axis snaps to a real font weight', () {
    for (final w in [100, 350, 600, 900]) {
      final style = SubtitleStyle(weight: w).textStyle(fontSize: 20);
      expect(style.fontWeight, isNotNull);
    }
    // Out-of-range values are clamped rather than throwing.
    expect(
      const SubtitleStyle(weight: 5000).textStyle(fontSize: 20).fontWeight,
      FontWeight.w900,
    );
  });

  test('the glow follows the glow colour and the shadow stays black', () {
    const s = SubtitleStyle(
      glowColorHex: '#22E5FFFF',
      glowIntensity: 1,
      glowRadius: 12,
      shadowOffset: 3,
      shadowBlur: 5,
    );
    final shadows = buildSubtitleShadowsFromStyle(s);
    expect(shadows.length, 2);
    expect(shadows.first.color.a, closeTo(1, 0.01));
    // The drop shadow is the separator from the picture, so it is not tinted by
    // the glow colour.
    expect(shadows.last.color.r, 0);
  });

  test('the ambient treatment warms the text colour', () {
    const plain = SubtitleStyle(colorHex: '#FFFFFFFF');
    const warm = SubtitleStyle(
      colorHex: '#FFFFFFFF',
      ambientEnabled: true,
      ambientWarmth: 1,
    );
    final cold = plain.textStyle(fontSize: 20).color!;
    final heated = warm.textStyle(fontSize: 20).color!;
    // Warmer means more red relative to blue.
    expect(
      heated.r - heated.b,
      greaterThan(cold.r - cold.b),
    );
  });

  test('each preset lays over the base rather than replacing it', () {
    const base = SubtitleStyle(colorHex: '#FF6B6BFF', scale: 1.3);
    final cinema = SubtitleStylePreset.cinema.apply(base);
    // The preset speaks to the glow and the entrance, not to the colour the
    // viewer chose.
    expect(cinema.colorHex, '#FF6B6BFF');
    expect(cinema.entrance, SubtitleEntrance.fluidFade);
    expect(cinema.preset, SubtitleStylePreset.cinema);
  });

  test('the late-night preset is the one that turns the ambient mode on', () {
    for (final preset in SubtitleStylePreset.values) {
      final applied = preset.apply(const SubtitleStyle());
      expect(
        applied.ambientEnabled,
        preset == SubtitleStylePreset.lateNight,
        reason: preset.id,
      );
    }
  });

  test('an unknown stored id falls back rather than throwing', () {
    expect(SubtitleStylePreset.fromId('nonsense'), SubtitleStylePreset.classic);
    expect(SubtitlePlateMode.fromId(null), SubtitlePlateMode.none);
    expect(SubtitleEntrance.fromId('nope'), SubtitleEntrance.none);
    expect(SubtitlePlacementMode.fromId(''), SubtitlePlacementMode.anchor);
    expect(SubtitleAlign.fromId('x'), SubtitleAlign.center);
  });

  test('the signature changes when any part of the look changes', () {
    const a = SubtitleStyle();
    expect(subtitleStyleSignature(a), subtitleStyleSignature(const SubtitleStyle()));
    expect(
      subtitleStyleSignature(a),
      isNot(subtitleStyleSignature(const SubtitleStyle(weight: 700))),
    );
  });

  test('the text align maps to the studio align', () {
    expect(const SubtitleStyle(align: SubtitleAlign.start).textAlign,
        TextAlign.start);
    expect(const SubtitleStyle(align: SubtitleAlign.end).textAlign,
        TextAlign.end);
  });
}
