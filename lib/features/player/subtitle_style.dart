import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/playback/playback_prefs.dart';
import 'subtitle_style_model.dart';

/// Subtitle outline-style presets for the Subtitle-style picker.
/// `(id, label)` — `id` is what's stored in [PlaybackPrefs.subtitleOutlineType].
const List<(String, String)> kSubtitleOutlineTypes = [
  ('none', 'None'),
  ('soft', 'Soft shadow'),
  ('outline', 'Outline'),
  ('bold', 'Bold outline'),
  ('shadow', 'Drop shadow'),
  ('glow', 'Glow'),
];

/// A ring of zero-blur shadows around a circle of [radius] — a cheap way to
/// draw a real text stroke in pure Flutter (no custom painter). Sample density
/// scales with radius so thick outlines stay smooth.
List<Shadow> _stroke(Color color, double radius) {
  if (radius <= 0) return const [];
  final n = math.max(12, (radius * 8).round());
  return [
    for (var i = 0; i < n; i++)
      Shadow(
        color: color,
        blurRadius: 0,
        offset: Offset(
          math.cos(2 * math.pi * i / n) * radius,
          math.sin(2 * math.pi * i / n) * radius,
        ),
      ),
  ];
}

/// The shadow list implementing a named outline preset.
List<Shadow> buildSubtitleShadows(String type, double width, Color outline) {
  switch (type) {
    case 'none':
      return const [];
    case 'outline':
      return _stroke(outline, width);
    case 'bold':
      return _stroke(outline, width * 1.8);
    case 'shadow':
      return [
        ..._stroke(outline, width * 0.6),
        Shadow(
          color: const Color(0xB3000000),
          offset: Offset(width, width),
          blurRadius: 2,
        ),
      ];
    case 'glow':
      return [
        ..._stroke(outline.withValues(alpha: 0.55), width * 0.5),
        Shadow(color: outline, blurRadius: 8 + width * 2),
      ];
    case 'soft':
    default:
      // Reproduces the legacy soft-shadow look (a soft dark halo) so the
      // default appearance is unchanged for existing users.
      return [Shadow(color: outline.withValues(alpha: 0.8), blurRadius: 4 + width)];
  }
}

/// The same presets, expressed as libass numbers: border thickness, blur and
/// shadow offset (all in libass units, sent as mpv's `sub-border-size`,
/// `sub-blur` and `sub-shadow-offset`).
///
/// libass has no "glow" of its own — a glow IS a coloured border with the blur
/// turned up. Kept beside [buildSubtitleShadows] on purpose: these two are the
/// same six presets drawn by two different renderers, and they drifted once
/// already. mpv used to be sent one hardcoded border size, so every preset
/// looked identical there while the preview promised otherwise.
({double border, double blur, double shadow}) libassOutline(
  String type,
  double width,
) => switch (type) {
  'none' => (border: 0, blur: 0, shadow: 0),
  'outline' => (border: width, blur: 0, shadow: 0),
  'bold' => (border: width * 1.8, blur: 0, shadow: 0),
  'shadow' => (border: width * 0.6, blur: 0, shadow: width),
  'glow' => (border: width * 0.8, blur: 6 + width * 2, shadow: 0),
  // 'soft' and anything unknown: the legacy soft halo.
  _ => (border: width * 0.5, blur: 3 + width, shadow: 0),
};

/// Parse a `#RRGGBB`/`#RRGGBBAA` hex into a [Color], scaling alpha by [opacity].
Color parseSubtitleHex(String hex, {double opacity = 1.0}) {
  var h = hex.replaceFirst('#', '').toUpperCase();
  if (h.length == 6) h = '${h}FF';
  if (h.length != 8) return const Color(0xFFFFFFFF);
  final r = int.tryParse(h.substring(0, 2), radix: 16) ?? 255;
  final g = int.tryParse(h.substring(2, 4), radix: 16) ?? 255;
  final b = int.tryParse(h.substring(4, 6), radix: 16) ?? 255;
  final a = int.tryParse(h.substring(6, 8), radix: 16) ?? 255;
  final alpha = (a * opacity.clamp(0.0, 1.0)).round().clamp(0, 255);
  return Color.fromARGB(alpha, r, g, b);
}

/// The single place the subtitle [TextStyle] is built — used by BOTH the
/// media_kit overlay ([SubtitleViewConfiguration]) and the live preview, so
/// what you see in the preview is exactly what renders on the video.
TextStyle buildSubtitleTextStyle(PlaybackPrefs p, {required double fontSize}) {
  return TextStyle(
    height: 1.4,
    fontSize: fontSize,
    fontFamily: p.subtitleFont.isEmpty ? null : p.subtitleFont,
    fontWeight: FontWeight.w600,
    color: parseSubtitleHex(p.subtitleColorHex, opacity: p.subtitleTextOpacity),
    backgroundColor:
        Color.fromRGBO(0, 0, 0, p.subtitleBgOpacity.clamp(0.0, 1.0)),
    shadows: buildSubtitleShadows(
      p.subtitleOutlineType,
      p.subtitleOutlineWidth,
      parseSubtitleHex(p.subtitleOutlineColorHex),
    ),
  );
}

/// Positions the complete subtitle block within the available video surface.
///
/// Used only when libass is off — the Flutter overlay then owns the whole
/// subtitle look, including placement, which the fixed
/// `SubtitleViewConfiguration` padding only approximated.
///
/// [position] runs 0 (top) … 100 (bottom) and [anchorX] runs 0 (left) … 1
/// (right); the two together are the caption's anchor. When [onDrag] is set the
/// block can be dragged: the gesture reports its movement as fractions of the
/// surface, and the caller folds them into the same anchor the position controls
/// write, so dragging and the sliders stay one source of truth.
///
/// When [studio] is given the block is drawn with the studio's full style — the
/// plate behind the text, the glow, the entrance animation and the late-night
/// treatment — rather than just a [TextStyle]. That is what makes the studio's
/// Look and Timing pages real on the video and not only in the preview.
class PositionedSubtitle extends StatefulWidget {
  const PositionedSubtitle({
    super.key,
    required this.text,
    required this.position,
    required this.style,
    this.anchorX = 0.5,
    this.onDrag,
    this.onTap,
    this.onScale,
    this.studio,
  });

  final String text;
  final int position;
  final TextStyle style;
  final double anchorX;

  /// Called with the drag movement as fractions of the surface width/height.
  final void Function(double dxFraction, double dyFraction)? onDrag;

  /// Called on a plain tap of the caption. The player uses it to cycle the
  /// plate behind the text (transparent → plate → glass → block) so the
  /// background can be changed right where the caption is, without a trip to
  /// the studio sheet.
  final VoidCallback? onTap;

  /// Called on a pinch of the caption, with the multiplier relative to the
  /// gesture's start. The player folds it into the subtitle scale so the text
  /// can be resized by pinching it directly.
  final ValueChanged<double>? onScale;

  /// The full studio style, when the overlay should draw the plate, glow and
  /// entrance itself. Null keeps the plain [style]-only rendering.
  final SubtitleStyle? studio;

  @override
  State<PositionedSubtitle> createState() => _PositionedSubtitleState();
}

class _PositionedSubtitleState extends State<PositionedSubtitle> {
  /// The text the entrance is animating, so a new cue replays the entrance and
  /// a redraw of the same cue does not.
  String _entranceKey = '';

  /// Pinch base, captured on scale start so the multiplier is relative to where
  /// the gesture began rather than compounding each frame.
  double _scaleBase = 1;

  @override
  Widget build(BuildContext context) {
    final child = LayoutBuilder(
      builder: (context, constraints) {
        // Keep the existing subtitle size relative to the video surface.
        final scale = math.sqrt(
          (constraints.maxWidth * constraints.maxHeight / (1920 * 1080)).clamp(
            0.0,
            1.0,
          ),
        );
        final w = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
        final h = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
        final studio = widget.studio;
        final text = studio?.displayText(widget.text) ?? widget.text;
        final style = studio?.textStyle(
              fontSize: widget.style.fontSize ?? 32,
              fontFamily: widget.style.fontFamily,
            ) ??
            widget.style;
        final align = studio?.textAlign ?? TextAlign.center;
        if (studio != null && text != _entranceKey) {
          _entranceKey = text;
        }
        final caption = studio == null
            ? Text(
                text,
                textAlign: align,
                style: style,
                textScaler: TextScaler.linear(scale),
              )
            : _StudioCaption(
                text: text,
                style: style,
                studio: studio,
                textScale: scale,
                align: align,
                entranceKey: _entranceKey,
              );
        final interactive = widget.onDrag != null ||
            widget.onTap != null ||
            widget.onScale != null;
        // Wrap ONLY the caption block, not the whole surface. The gesture then
        // sits on the glyphs themselves, so the touch area and what the user
        // sees are the same rectangle — the old full-surface wrap left a drag
        // starting anywhere but on the text doing nothing, which read as the
        // hit box being "somewhere else".
        //
        // A single scale recognizer carries BOTH the drag and the pinch: pan
        // and scale recognizers cannot coexist on one detector (scale is a
        // superset of pan), so the drag reads [focalPointDelta] and the pinch
        // reads [scale].
        final block = interactive
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                onScaleStart: (_) => _scaleBase = 1,
                onScaleUpdate: (d) {
                  final drag = widget.onDrag;
                  if (drag != null && d.pointerCount <= 1) {
                    final delta = d.focalPointDelta;
                    if (delta != Offset.zero) {
                      drag(delta.dx / w, delta.dy / h);
                    }
                  }
                  final scale = widget.onScale;
                  if (scale != null && d.pointerCount > 1 && d.scale > 0) {
                    scale(d.scale / _scaleBase);
                    _scaleBase = d.scale;
                  }
                },
                child: caption,
              )
            : caption;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment(
              (widget.anchorX.clamp(0.0, 1.0) * 2) - 1,
              widget.position.clamp(0, 100) / 50 - 1,
            ),
            child: block,
          ),
        );
      },
    );
    // A caption with no gesture stays inert so it never eats a tap meant for
    // the controls.
    final interactive = widget.onDrag != null ||
        widget.onTap != null ||
        widget.onScale != null;
    return interactive ? child : IgnorePointer(child: child);
  }
}

/// The caption as the studio draws it: the plate, the glow, the entrance and the
/// late-night dim, all from one [SubtitleStyle].
class _StudioCaption extends StatelessWidget {
  const _StudioCaption({
    required this.text,
    required this.style,
    required this.studio,
    required this.textScale,
    required this.align,
    required this.entranceKey,
  });

  final String text;
  final TextStyle style;
  final SubtitleStyle studio;
  final double textScale;
  final TextAlign align;
  final String entranceKey;

  @override
  Widget build(BuildContext context) {
    final plate = _plate();
    final caption = DecoratedBox(
      decoration: plate ?? const BoxDecoration(),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: studio.plateMode == SubtitlePlateMode.none
              ? 0
              : studio.platePadding,
          vertical: studio.plateMode == SubtitlePlateMode.none
              ? 0
              : studio.platePadding * 0.5,
        ),
        child: Text(
          text,
          textAlign: align,
          maxLines: studio.maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
          textScaler: TextScaler.linear(textScale),
        ),
      ),
    );
    return _entrance(caption);
  }

  /// The plate behind the text, or null when the style asks for none.
  BoxDecoration? _plate() {
    if (studio.plateMode == SubtitlePlateMode.none) return null;
    final radius = BorderRadius.circular(studio.plateCorner);
    switch (studio.plateMode) {
      case SubtitlePlateMode.blur:
        // A true blur of the frame behind is not reachable from a Flutter
        // overlay over a native surface, so "glass" is approximated: a lighter
        // translucent fill with a hairline highlight edge, which reads as
        // frosted rather than as the flat black of the solid plate.
        return BoxDecoration(
          color: Color.fromRGBO(0, 0, 0, studio.plateOpacity * 0.55),
          borderRadius: radius,
          border: Border.all(
            color: const Color(0x4DFFFFFF),
            width: 1,
          ),
        );
      case SubtitlePlateMode.plate:
      case SubtitlePlateMode.block:
      case SubtitlePlateMode.none:
        return BoxDecoration(
          color: Color.fromRGBO(0, 0, 0, studio.plateOpacity),
          borderRadius: radius,
        );
    }
  }

  /// The entrance animation, keyed on [entranceKey] so each new cue replays it.
  Widget _entrance(Widget child) {
    if (studio.entrance == SubtitleEntrance.none) return child;
    return _EntranceTransition(
      key: ValueKey(entranceKey),
      entrance: studio.entrance,
      duration: Duration(milliseconds: studio.entranceMs),
      child: child,
    );
  }
}

/// Plays the studio's entrance on first build and then leaves the child alone.
///
/// Each entrance is a real transform of the drawn text — a slide, a rise, a
/// scale — rather than a cross-fade of two copies, which is what makes the
/// motion read as the caption moving rather than the screen flickering.
class _EntranceTransition extends StatefulWidget {
  const _EntranceTransition({
    super.key,
    required this.entrance,
    required this.duration,
    required this.child,
  });

  final SubtitleEntrance entrance;
  final Duration duration;
  final Widget child;

  @override
  State<_EntranceTransition> createState() => _EntranceTransitionState();
}

class _EntranceTransitionState extends State<_EntranceTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _c,
      curve: widget.entrance == SubtitleEntrance.spring
          ? Curves.elasticOut
          : Curves.easeOutCubic,
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        switch (widget.entrance) {
          case SubtitleEntrance.none:
            return child!;
          case SubtitleEntrance.fluidFade:
            return Opacity(opacity: t.clamp(0.0, 1.0), child: child);
          case SubtitleEntrance.riseFade:
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 18),
                child: child,
              ),
            );
          case SubtitleEntrance.spring:
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
            );
          case SubtitleEntrance.reveal:
            return ClipRect(
              child: Align(
                widthFactor: 1,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: t.clamp(0.0, 1.0),
                  alignment: Alignment.centerLeft,
                  child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
                ),
              ),
            );
          case SubtitleEntrance.slide:
            return Opacity(
              opacity: t.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset((1 - t) * -40, 0),
                child: child,
              ),
            );
        }
      },
      child: widget.child,
    );
  }
}
