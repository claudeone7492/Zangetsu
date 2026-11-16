import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../core/playback/playback_prefs.dart';
import 'subtitle_style.dart' show parseSubtitleHex, buildSubtitleShadows;

/// The whole subtitle appearance, in one value.
///
/// Ported from the reference player's `SubtitleStyle`. The point of gathering it
/// into one object is that the renderer has to redraw the instant any control
/// moves, so the settings arrive as a single value it can diff rather than a
/// dozen independent reads that each repaint on their own.
///
/// Every field has a default, and [SubtitleStyle.fromPrefs] reads each from
/// [PlaybackPrefs] with the same default, so an older install decodes against a
/// newer schema without a migration.
@immutable
class SubtitleStyle {
  const SubtitleStyle({
    this.preset = SubtitleStylePreset.classic,
    this.weight = 600,
    this.widthAxis = 100,
    this.slant = 0,
    this.scale = 1,
    this.lineHeight = 1.4,
    this.letterSpacing = 0,
    this.wordSpacing = 1,
    this.uppercase = false,
    this.colorHex = '#FFFFFFFF',
    this.textOpacity = 1,
    this.align = SubtitleAlign.center,
    this.maxLines = 3,
    this.plateMode = SubtitlePlateMode.none,
    this.plateOpacity = 0.85,
    this.plateCorner = 8,
    this.platePadding = 6,
    this.glowEnabled = true,
    this.glowRadius = 2,
    this.glowIntensity = 0.9,
    this.glowColorHex = '#000000FF',
    this.shadowOffset = 2,
    this.shadowBlur = 4,
    this.entrance = SubtitleEntrance.none,
    this.entranceMs = 220,
    this.placementMode = SubtitlePlacementMode.anchor,
    this.maxShift = 0.28,
    this.allowScale = true,
    this.minScale = 0.75,
    this.ambientEnabled = false,
    this.ambientWarmth = 0.8,
    this.ambientDim = 0.35,
  });

  final SubtitleStylePreset preset;

  // Typography.
  final int weight;
  final double widthAxis;
  final double slant;
  final double scale;
  final double lineHeight;
  final double letterSpacing;
  final double wordSpacing;
  final bool uppercase;
  final String colorHex;
  final double textOpacity;

  // Layout.
  final SubtitleAlign align;
  final int maxLines;

  // The plate behind the text.
  final SubtitlePlateMode plateMode;
  final double plateOpacity;
  final double plateCorner;
  final double platePadding;

  // The edge glow, separate from the drop shadow because they do different
  // jobs: the shadow separates the glyph from the picture, the glow carries the
  // colour.
  final bool glowEnabled;
  final double glowRadius;
  final double glowIntensity;
  final String glowColorHex;
  final double shadowOffset;
  final double shadowBlur;

  // How a line arrives.
  final SubtitleEntrance entrance;
  final int entranceMs;

  // Where the block may be placed.
  final SubtitlePlacementMode placementMode;
  final double maxShift;
  final bool allowScale;
  final double minScale;

  // The late-night treatment.
  final bool ambientEnabled;
  final double ambientWarmth;
  final double ambientDim;

  /// The style as stored by [PlaybackPrefs].
  static SubtitleStyle fromPrefs(PlaybackPrefs p) => SubtitleStyle(
    preset: SubtitleStylePreset.fromId(p.subtitlePreset),
    weight: p.subtitleWeight,
    widthAxis: p.subtitleWidthAxis,
    slant: p.subtitleSlant,
    scale: p.subtitleScale,
    lineHeight: p.subtitleLineHeight,
    letterSpacing: p.subtitleLetterSpacing,
    wordSpacing: p.subtitleWordSpacing,
    uppercase: p.subtitleUppercase,
    colorHex: p.subtitleColorHex,
    textOpacity: p.subtitleTextOpacity,
    align: SubtitleAlign.fromId(p.subtitleAlign),
    maxLines: p.subtitleMaxLines,
    plateMode: SubtitlePlateMode.fromId(p.subtitlePlateMode),
    plateOpacity: p.subtitlePlateOpacity,
    plateCorner: p.subtitlePlateCorner,
    platePadding: p.subtitlePlatePadding,
    glowEnabled: p.subtitleGlowEnabled,
    glowRadius: p.subtitleGlowRadius,
    glowIntensity: p.subtitleGlowIntensity,
    glowColorHex: p.subtitleGlowColorHex,
    shadowOffset: p.subtitleShadowOffset,
    shadowBlur: p.subtitleShadowBlur,
    entrance: SubtitleEntrance.fromId(p.subtitleEntrance),
    entranceMs: p.subtitleEntranceMs,
    placementMode: SubtitlePlacementMode.fromId(p.subtitlePlacementMode),
    maxShift: p.subtitleMaxShift,
    allowScale: p.subtitleAllowScale,
    minScale: p.subtitleMinScale,
    ambientEnabled: p.subtitleAmbientEnabled,
    ambientWarmth: p.subtitleAmbientWarmth,
    ambientDim: p.subtitleAmbientDim,
  );

  /// Write every field back to [PlaybackPrefs]. Used when a preset is applied.
  Future<void> saveTo(PlaybackPrefs p) async {
    await p.setSubtitlePreset(preset.id);
    await p.setSubtitleWeight(weight);
    await p.setSubtitleWidthAxis(widthAxis);
    await p.setSubtitleSlant(slant);
    await p.setSubtitleScale(scale);
    await p.setSubtitleLineHeight(lineHeight);
    await p.setSubtitleLetterSpacing(letterSpacing);
    await p.setSubtitleWordSpacing(wordSpacing);
    await p.setSubtitleUppercase(uppercase);
    await p.setSubtitleColorHex(colorHex);
    await p.setSubtitleTextOpacity(textOpacity);
    await p.setSubtitleAlign(align.id);
    await p.setSubtitleMaxLines(maxLines);
    await p.setSubtitlePlateMode(plateMode.id);
    await p.setSubtitlePlateOpacity(plateOpacity);
    await p.setSubtitlePlateCorner(plateCorner);
    await p.setSubtitlePlatePadding(platePadding);
    await p.setSubtitleGlowEnabled(glowEnabled);
    await p.setSubtitleGlowRadius(glowRadius);
    await p.setSubtitleGlowIntensity(glowIntensity);
    await p.setSubtitleGlowColorHex(glowColorHex);
    await p.setSubtitleShadowOffset(shadowOffset);
    await p.setSubtitleShadowBlur(shadowBlur);
    await p.setSubtitleEntrance(entrance.id);
    await p.setSubtitleEntranceMs(entranceMs);
    await p.setSubtitlePlacementMode(placementMode.id);
    await p.setSubtitleMaxShift(maxShift);
    await p.setSubtitleAllowScale(allowScale);
    await p.setSubtitleMinScale(minScale);
    await p.setSubtitleAmbientEnabled(ambientEnabled);
    await p.setSubtitleAmbientWarmth(ambientWarmth);
    await p.setSubtitleAmbientDim(ambientDim);
  }

  SubtitleStyle copyWith({
    SubtitleStylePreset? preset,
    int? weight,
    double? widthAxis,
    double? slant,
    double? scale,
    double? lineHeight,
    double? letterSpacing,
    double? wordSpacing,
    bool? uppercase,
    String? colorHex,
    double? textOpacity,
    SubtitleAlign? align,
    int? maxLines,
    SubtitlePlateMode? plateMode,
    double? plateOpacity,
    double? plateCorner,
    double? platePadding,
    bool? glowEnabled,
    double? glowRadius,
    double? glowIntensity,
    String? glowColorHex,
    double? shadowOffset,
    double? shadowBlur,
    SubtitleEntrance? entrance,
    int? entranceMs,
    SubtitlePlacementMode? placementMode,
    double? maxShift,
    bool? allowScale,
    double? minScale,
    bool? ambientEnabled,
    double? ambientWarmth,
    double? ambientDim,
  }) => SubtitleStyle(
    preset: preset ?? this.preset,
    weight: weight ?? this.weight,
    widthAxis: widthAxis ?? this.widthAxis,
    slant: slant ?? this.slant,
    scale: scale ?? this.scale,
    lineHeight: lineHeight ?? this.lineHeight,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    wordSpacing: wordSpacing ?? this.wordSpacing,
    uppercase: uppercase ?? this.uppercase,
    colorHex: colorHex ?? this.colorHex,
    textOpacity: textOpacity ?? this.textOpacity,
    align: align ?? this.align,
    maxLines: maxLines ?? this.maxLines,
    plateMode: plateMode ?? this.plateMode,
    plateOpacity: plateOpacity ?? this.plateOpacity,
    plateCorner: plateCorner ?? this.plateCorner,
    platePadding: platePadding ?? this.platePadding,
    glowEnabled: glowEnabled ?? this.glowEnabled,
    glowRadius: glowRadius ?? this.glowRadius,
    glowIntensity: glowIntensity ?? this.glowIntensity,
    glowColorHex: glowColorHex ?? this.glowColorHex,
    shadowOffset: shadowOffset ?? this.shadowOffset,
    shadowBlur: shadowBlur ?? this.shadowBlur,
    entrance: entrance ?? this.entrance,
    entranceMs: entranceMs ?? this.entranceMs,
    placementMode: placementMode ?? this.placementMode,
    maxShift: maxShift ?? this.maxShift,
    allowScale: allowScale ?? this.allowScale,
    minScale: minScale ?? this.minScale,
    ambientEnabled: ambientEnabled ?? this.ambientEnabled,
    ambientWarmth: ambientWarmth ?? this.ambientWarmth,
    ambientDim: ambientDim ?? this.ambientDim,
  );

  /// The text as the renderer should draw it: uppercased when the style asks,
  /// and with the words re-joined so word spacing is a real gap.
  String displayText(String raw) =>
      uppercase ? raw.toUpperCase() : raw;

  /// The caption's text style, shared by the on-video overlay and the studio
  /// preview so what the preview promises is what the video delivers.
  ///
  /// [fontSize] is the base size in logical pixels; the style's own [scale] and
  /// the caller's surface scale multiply it, not this method.
  TextStyle textStyle({required double fontSize, String? fontFamily}) {
    final colour = parseSubtitleHex(colorHex, opacity: textOpacity);
    final warm = ambientEnabled
        ? Color.lerp(
            colour,
            const Color(0xFFFFB066),
            ambientWarmth.clamp(0.0, 1.0),
          )!
        : colour;
    return TextStyle(
      height: lineHeight,
      fontSize: fontSize,
      fontFamily: (fontFamily ?? '').isEmpty ? null : fontFamily,
      fontWeight: _weightOf(weight),
      fontStyle: slant == 0 ? FontStyle.normal : FontStyle.italic,
      letterSpacing: letterSpacing * fontSize,
      wordSpacing: (wordSpacing - 1) * fontSize * 0.35,
      color: warm,
      shadows: buildSubtitleShadowsFromStyle(this),
    );
  }

  /// The text alignment the style asks for.
  TextAlign get textAlign => switch (align) {
    SubtitleAlign.start => TextAlign.start,
    SubtitleAlign.center => TextAlign.center,
    SubtitleAlign.end => TextAlign.end,
  };

  static FontWeight _weightOf(int w) {
    final clamped = w.clamp(100, 900);
    // FontWeight is a 100-step enum; snap to the nearest defined step.
    final index = ((clamped / 100).round() - 1).clamp(0, 8);
    return FontWeight.values[index];
  }
}

/// A one-tap look, built from the fields above rather than beside them.
///
/// A preset that stored its own values would be a second source of truth; these
/// are the same fields the studio edits, so a preset can be applied and then
/// dialled, and the studio always shows what is actually in effect.
enum SubtitleStylePreset {
  classic('classic', 'Classic'),
  cinema('cinema', 'Cinema'),
  broadcast('broadcast', 'Broadcast'),
  neon('neon', 'Neon'),
  lateNight('late_night', 'Late night');

  const SubtitleStylePreset(this.id, this.label);

  final String id;
  final String label;

  /// The style this preset stands for, laid over [base] so the parts a preset
  /// does not speak to are left as the viewer set them.
  SubtitleStyle apply(SubtitleStyle base) {
    switch (this) {
      case SubtitleStylePreset.classic:
        return base.copyWith(
          preset: this,
          weight: 600,
          lineHeight: 1.2,
          letterSpacing: 0,
          glowEnabled: true,
          glowRadius: 6,
          glowIntensity: 0.65,
          plateMode: SubtitlePlateMode.none,
          ambientEnabled: false,
        );
      case SubtitleStylePreset.cinema:
        return base.copyWith(
          preset: this,
          weight: 500,
          lineHeight: 1.35,
          letterSpacing: 0.01,
          scale: 0.95,
          glowEnabled: true,
          glowRadius: 4,
          glowIntensity: 0.5,
          plateMode: SubtitlePlateMode.none,
          entrance: SubtitleEntrance.fluidFade,
          ambientEnabled: false,
        );
      case SubtitleStylePreset.broadcast:
        return base.copyWith(
          preset: this,
          weight: 700,
          lineHeight: 1.25,
          letterSpacing: 0.005,
          uppercase: false,
          glowEnabled: true,
          glowRadius: 3,
          glowIntensity: 0.9,
          plateMode: SubtitlePlateMode.plate,
          plateOpacity: 0.7,
          entrance: SubtitleEntrance.none,
          ambientEnabled: false,
        );
      case SubtitleStylePreset.neon:
        return base.copyWith(
          preset: this,
          weight: 700,
          letterSpacing: 0.03,
          widthAxis: 105,
          glowEnabled: true,
          glowRadius: 14,
          glowIntensity: 1,
          glowColorHex: '#22E5FFFF',
          plateMode: SubtitlePlateMode.none,
          entrance: SubtitleEntrance.spring,
          ambientEnabled: false,
        );
      case SubtitleStylePreset.lateNight:
        return base.copyWith(
          preset: this,
          weight: 500,
          lineHeight: 1.4,
          letterSpacing: 0.01,
          scale: 0.98,
          glowEnabled: true,
          glowRadius: 10,
          glowIntensity: 0.55,
          glowColorHex: '#3A1E00FF',
          plateMode: SubtitlePlateMode.blur,
          plateOpacity: 0.6,
          entrance: SubtitleEntrance.fluidFade,
          entranceMs: 320,
          ambientEnabled: true,
          ambientWarmth: 0.85,
          ambientDim: 0.4,
        );
    }
  }

  static SubtitleStylePreset fromId(String? id) => values.firstWhere(
    (p) => p.id == id,
    orElse: () => SubtitleStylePreset.classic,
  );
}

enum SubtitleAlign {
  start('start', 'Left'),
  center('center', 'Centre'),
  end('end', 'Right');

  const SubtitleAlign(this.id, this.label);

  final String id;
  final String label;

  static SubtitleAlign fromId(String? id) =>
      values.firstWhere((a) => a.id == id, orElse: () => SubtitleAlign.center);
}

enum SubtitlePlateMode {
  none('none', 'None'),
  plate('plate', 'Plate'),
  block('block', 'Block'),
  blur('blur', 'Glass');

  const SubtitlePlateMode(this.id, this.label);

  final String id;
  final String label;

  static SubtitlePlateMode fromId(String? id) =>
      values.firstWhere((m) => m.id == id, orElse: () => SubtitlePlateMode.none);

  /// The order a tap cycles the background through: solid → glass → block →
  /// transparent, then back to solid. Solid first so the very first tap does
  /// something visible on a caption that starts transparent. Pure, so the tap
  /// behaviour is testable without a player.
  static const List<SubtitlePlateMode> tapCycle = [
    plate,
    blur,
    block,
    none,
  ];

  /// The mode one tap ahead of [current] in [tapCycle].
  SubtitlePlateMode get nextOnTap {
    final i = tapCycle.indexOf(this);
    return tapCycle[(i + 1) % tapCycle.length];
  }
}

/// How a line arrives and leaves.
///
/// Each of these is a real transform applied to the drawn text, not a cross-fade
/// of two copies: the difference is what makes the motion read as the caption
/// moving rather than the screen flickering.
enum SubtitleEntrance {
  none('none', 'None'),
  fluidFade('fluid_fade', 'Fluid fade'),
  riseFade('rise_fade', 'Rise + fade'),
  spring('spring', 'Spring scale'),
  reveal('reveal', 'Text reveal'),
  slide('slide', 'Slide in');

  const SubtitleEntrance(this.id, this.label);

  final String id;
  final String label;

  static SubtitleEntrance fromId(String? id) =>
      values.firstWhere((e) => e.id == id, orElse: () => SubtitleEntrance.none);
}

/// Where the block is allowed to be placed. Mirrors
/// [SubtitlePlacementMode] in `subtitle_layout.dart`, but is stored and named
/// here so the studio can list it.
enum SubtitlePlacementMode {
  anchor('anchor', 'Fixed position'),
  speaker('speaker', 'Speaker tracking'),
  collision('collision', 'Anti-collision'),
  adaptive('adaptive', 'Adaptive');

  const SubtitlePlacementMode(this.id, this.label);

  final String id;
  final String label;

  static SubtitlePlacementMode fromId(String? id) => values.firstWhere(
    (m) => m.id == id,
    orElse: () => SubtitlePlacementMode.anchor,
  );
}

/// The shadows implementing the glow + drop-shadow fields.
///
/// Kept beside [buildSubtitleShadows] so the six legacy outline presets and this
/// richer model draw from the same primitive and cannot drift.
List<Shadow> buildSubtitleShadowsFromStyle(SubtitleStyle s) {
  final glow = parseSubtitleHex(
    s.glowColorHex,
    opacity: s.glowEnabled ? s.glowIntensity : 0,
  );
  final shadows = <Shadow>[];
  if (s.glowEnabled && s.glowRadius > 0) {
    shadows.add(Shadow(color: glow, blurRadius: s.glowRadius));
  }
  if (s.shadowOffset > 0 || s.shadowBlur > 0) {
    shadows.add(
      Shadow(
        color: const Color(0xB3000000),
        offset: Offset(s.shadowOffset, s.shadowOffset),
        blurRadius: s.shadowBlur,
      ),
    );
  }
  return shadows;
}

/// A stable, comparable signature of a style, for tests and cache keys.
String subtitleStyleSignature(SubtitleStyle s) => jsonEncode({
  'preset': s.preset.id,
  'weight': s.weight,
  'width': s.widthAxis,
  'slant': s.slant,
  'scale': s.scale,
  'lineHeight': s.lineHeight,
  'letterSpacing': s.letterSpacing,
  'wordSpacing': s.wordSpacing,
  'uppercase': s.uppercase,
  'color': s.colorHex,
  'opacity': s.textOpacity,
  'align': s.align.id,
  'maxLines': s.maxLines,
  'plate': s.plateMode.id,
  'glow': s.glowEnabled,
  'entrance': s.entrance.id,
  'placement': s.placementMode.id,
  'ambient': s.ambientEnabled,
});
