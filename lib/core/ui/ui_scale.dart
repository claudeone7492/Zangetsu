import 'package:flutter/material.dart';

/// A global UI scale on top of the system text scale.
///
/// Hikari's `UiScale.kt` lets the viewer enlarge the whole interface, not just
/// text. Flutter already honours the system scale; this adds an in-app factor
/// applied once at the root so every `MediaQuery.textScalerOf` sees it.
class UiScale {
  const UiScale._();

  static const double min = 0.8;
  static const double max = 1.4;

  static double _factor = 1.0;
  static double get factor => _factor;

  static void set(double value) => _factor = value.clamp(min, max);

  static Widget wrap(BuildContext context, Widget child) {
    if (_factor == 1.0) return child;
    final media = MediaQuery.of(context);
    final base = media.textScaler.scale(1);
    return MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear((base * _factor).clamp(0.5, 3.0)),
      ),
      child: child,
    );
  }
}
