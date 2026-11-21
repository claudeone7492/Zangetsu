import 'dart:io';

import 'package:flutter/material.dart';

import 'theme_controller.dart';

/// The user's background photo, painted behind the whole shell.
///
/// Reads [ThemeController] rather than holding state: the appearance screen
/// writes through the same box, and the root app rebuilds on
/// [ThemeController.revision], so a change shows up on the next frame without
/// a restart.
class BackgroundPref {
  const BackgroundPref._();

  static String? get path => ThemeController.backgroundImage;

  static double get opacity => ThemeController.backgroundImageOpacity;

  static Widget apply(Widget child) {
    final file = path;
    if (file == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: opacity,
          child: Image.file(
            File(file),
            fit: BoxFit.cover,
            // A deleted file must not take the shell down with it.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
        child,
      ],
    );
  }
}
