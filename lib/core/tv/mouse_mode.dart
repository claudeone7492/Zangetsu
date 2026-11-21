import 'package:flutter/material.dart';

/// Pointer support for TV.
///
/// A leanback box with a remote has no pointer; a TV stick with a mouse or a
/// desktop-style air remote does. Hikari's `MouseMode.kt` turns hover into a
/// visible cursor. In Flutter the equivalent is a click cursor plus hover
/// feedback on focusable tiles.
class MouseMode {
  const MouseMode._();

  static bool _enabled = false;
  static bool get enabled => _enabled;
  static void setEnabled(bool value) => _enabled = value;

  static Widget wrap(Widget child) {
    if (!_enabled) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: child,
    );
  }
}
