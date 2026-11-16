// The studio writes PlaybackPrefs; the renderer reads SubtitleStyle.fromPrefs.
// If the two ever drift, a control would move and the video would not — so this
// pins the round trip field by field, and pins that a stored value of the wrong
// type reads as the default rather than throwing.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/features/player/subtitle_style_model.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('subtitle_studio_test');
    Hive.init(directory.path);
    await Hive.openBox<dynamic>(PlaybackPrefs.boxName);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('the model reads the prefs defaults', () async {
    final style = SubtitleStyle.fromPrefs(PlaybackPrefs());
    const expected = SubtitleStyle();
    expect(style.weight, expected.weight);
    expect(style.lineHeight, expected.lineHeight);
    expect(style.plateMode, expected.plateMode);
    expect(style.entrance, expected.entrance);
    expect(style.placementMode, expected.placementMode);
    expect(style.ambientEnabled, expected.ambientEnabled);
  });

  test('every studio field survives a save and a reload', () async {
    final prefs = PlaybackPrefs();
    const style = SubtitleStyle(
      preset: SubtitleStylePreset.neon,
      weight: 800,
      widthAxis: 110,
      slant: 6,
      scale: 1.4,
      lineHeight: 1.7,
      letterSpacing: 0.05,
      wordSpacing: 1.4,
      uppercase: true,
      colorHex: '#00E5FFFF',
      textOpacity: 0.8,
      align: SubtitleAlign.end,
      maxLines: 2,
      plateMode: SubtitlePlateMode.block,
      plateOpacity: 0.6,
      plateCorner: 14,
      platePadding: 12,
      glowEnabled: false,
      glowRadius: 18,
      glowIntensity: 0.4,
      glowColorHex: '#22E5FFFF',
      shadowOffset: 6,
      shadowBlur: 10,
      entrance: SubtitleEntrance.spring,
      entranceMs: 400,
      placementMode: SubtitlePlacementMode.speaker,
      maxShift: 0.4,
      allowScale: false,
      minScale: 0.6,
      ambientEnabled: true,
      ambientWarmth: 0.5,
      ambientDim: 0.6,
    );
    await style.saveTo(prefs);
    final restored = SubtitleStyle.fromPrefs(PlaybackPrefs());
    expect(subtitleStyleSignature(restored), subtitleStyleSignature(style));
    expect(restored.maxLines, 2);
    expect(restored.glowRadius, 18);
    expect(restored.allowScale, isFalse);
  });

  test('a tap on the caption cycles solid → glass → block → transparent', () {
    // The order matters: the first tap has to change a transparent caption, so
    // solid leads, and every mode is reachable before it wraps.
    expect(SubtitlePlateMode.none.nextOnTap, SubtitlePlateMode.plate);
    expect(SubtitlePlateMode.plate.nextOnTap, SubtitlePlateMode.blur);
    expect(SubtitlePlateMode.blur.nextOnTap, SubtitlePlateMode.block);
    expect(SubtitlePlateMode.block.nextOnTap, SubtitlePlateMode.none);
    // Every mode is in the cycle — none is unreachable by tapping.
    expect(
      SubtitlePlateMode.tapCycle.toSet(),
      SubtitlePlateMode.values.toSet(),
    );
  });

  test('a stored value of the wrong type reads as the default', () async {
    final box = Hive.box<dynamic>(PlaybackPrefs.boxName);
    await box.put('subtitleWeight', 'heavy');
    await box.put('subtitlePlateMode', 42);
    await box.put('subtitleMaxShift', 'wide');
    await box.put('subtitleAmbientDim', double.nan);
    final prefs = PlaybackPrefs();
    expect(prefs.subtitleWeight, 600);
    expect(prefs.subtitlePlateMode, 'none');
    expect(prefs.subtitleMaxShift, closeTo(0.28, 0.0001));
    expect(prefs.subtitleAmbientDim, closeTo(0.35, 0.0001));
  });

  test('out-of-range writes are clamped, not stored raw', () async {
    final prefs = PlaybackPrefs();
    await prefs.setSubtitleWeight(5000);
    await prefs.setSubtitleGlowRadius(-4);
    await prefs.setSubtitleMaxLines(99);
    await prefs.setSubtitleRate(3);
    expect(prefs.subtitleWeight, 900);
    expect(prefs.subtitleGlowRadius, 0);
    expect(prefs.subtitleMaxLines, 4);
    expect(prefs.subtitleRate, closeTo(1.1, 0.0001));
  });

  test('the horizontal anchor defaults to centred and is bounded', () async {
    final prefs = PlaybackPrefs();
    expect(prefs.subtitlePositionX, closeTo(0.5, 0.0001));
    await prefs.setSubtitlePositionX(5);
    expect(prefs.subtitlePositionX, 1.0);
    await prefs.setSubtitlePositionX(-5);
    expect(prefs.subtitlePositionX, 0.0);
  });
}
