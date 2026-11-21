import '../theme/theme_controller.dart';

/// Pointer support for TV.
///
/// A leanback box with a remote has no pointer; a TV stick with a mouse or a
/// desktop-style air remote does. With mouse mode on, hovering a [TvFocusable]
/// moves focus to it (so the highlight follows the pointer) and the cursor
/// becomes a hand. Off by default; inert on a D-pad-only device.
class MouseMode {
  const MouseMode._();

  static bool get enabled => ThemeController.mouseMode;
}
