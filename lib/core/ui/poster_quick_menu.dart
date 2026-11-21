import 'dart:async';

import 'package:flutter/material.dart';

/// The four discs of Hikari's poster quick menu, in its order.
enum PosterQuickAction { details, play, library, close }

/// Hikari's `ui/components/PosterQuickMenu.kt`: hold a poster for a second and
/// a dimmed strip of four discs slides up over the art; slide to the one you
/// want and let go. A tap or a scroll never opens it.
///
/// The Compose original paints its discs on a Canvas; this builds the same
/// layout from widgets, which keeps the labels translatable and the discs
/// tappable by screen readers.
class PosterQuickMenuOverlay extends StatelessWidget {
  const PosterQuickMenuOverlay({
    super.key,
    required this.selected,
    required this.labels,
    required this.hint,
  }) : assert(labels.length == 4, 'one label per disc');

  /// 0..3 — which disc is under the finger.
  final int selected;

  /// Details, Play, Library, Close.
  final List<String> labels;

  /// "Slide to explore".
  final String hint;

  static const List<IconData> icons = [
    Icons.info_outline_rounded,
    Icons.play_arrow_rounded,
    Icons.library_add_outlined,
    Icons.close_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(color: Color(0x4D000000)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < 4; i++)
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 120),
                                width: i == selected ? 30 : 26,
                                height: i == selected ? 30 : 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == selected
                                      ? scheme.primary
                                      : Colors.white.withValues(alpha: 0.18),
                                ),
                                child: Icon(
                                  icons[i],
                                  size: i == selected ? 18 : 15,
                                  color: i == selected
                                      ? scheme.onPrimary
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                labels[i],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: i == selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The hold-and-slide gesture around a poster.
///
/// [builder] gets `menuOpen` so the card can drop its own tap/long-press
/// handlers while the menu owns the pointer — otherwise letting go would fire
/// both the pick and the card's tap.
class PosterQuickMenuArea extends StatefulWidget {
  const PosterQuickMenuArea({
    super.key,
    required this.builder,
    required this.onPick,
    this.labels = const ['Details', 'Play', 'Library', 'Close'],
    this.hint = 'Slide to explore',
    this.enabled = true,
    this.hold = const Duration(seconds: 1),
    this.slop = 18,
  });

  final Widget Function(BuildContext context, bool menuOpen) builder;
  final ValueChanged<PosterQuickAction> onPick;
  final List<String> labels;
  final String hint;
  final bool enabled;

  /// Hikari's `QUICK_MENU_HOLD_MS`.
  final Duration hold;

  /// Movement beyond this cancels the hold (a scroll, not a press).
  final double slop;

  @override
  State<PosterQuickMenuArea> createState() => _PosterQuickMenuAreaState();
}

class _PosterQuickMenuAreaState extends State<PosterQuickMenuArea> {
  Timer? _holdTimer;
  Offset? _start;
  bool _open = false;
  int _selected = 1;
  double _width = 1;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled) return;
    _start = event.localPosition;
    _holdTimer?.cancel();
    _holdTimer = Timer(widget.hold, () {
      if (!mounted) return;
      setState(() {
        _open = true;
        _selected = 1;
      });
    });
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    if (start == null) return;
    if (!_open) {
      if ((event.localPosition - start).distance > widget.slop) {
        _holdTimer?.cancel();
        _holdTimer = null;
      }
      return;
    }
    final next = ((event.localPosition.dx / _width) * 4)
        .floor()
        .clamp(0, 3);
    if (next != _selected) setState(() => _selected = next);
  }

  void _up() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _start = null;
    if (!_open) return;
    final picked = PosterQuickAction.values[_selected];
    setState(() => _open = false);
    widget.onPick(picked);
  }

  void _cancel() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _start = null;
    if (_open) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth <= 0 ? 1 : constraints.maxWidth;
        return Listener(
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _cancel(),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.builder(context, _open),
              if (_open)
                PosterQuickMenuOverlay(
                  selected: _selected,
                  labels: widget.labels,
                  hint: widget.hint,
                ),
            ],
          ),
        );
      },
    );
  }
}
