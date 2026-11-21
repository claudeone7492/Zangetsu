import 'dart:io';

import 'package:flutter/material.dart';

/// A user-supplied background image behind the app shell.
class BackgroundPref {
  const BackgroundPref._();

  static String? _path;
  static double _opacity = 0.35;

  static String? get path => _path;
  static double get opacity => _opacity;

  static void set({String? path, double? opacity}) {
    _path = path;
    if (opacity != null) _opacity = opacity.clamp(0.05, 1.0);
  }

  static Widget apply(Widget child) {
    final file = _path;
    if (file == null || !File(file).existsSync()) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: _opacity,
          child: Image.file(File(file), fit: BoxFit.cover),
        ),
        child,
      ],
    );
  }
}
