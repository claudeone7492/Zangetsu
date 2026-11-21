import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../hive/safe_box.dart';

/// Global interface scale, ported from Hikari's `ui/UiScale.kt`.
///
/// Hikari rewrites the Activity's `Configuration` (fontScale 1, density ×
/// scale) so layout and text grow together. Flutter has no density override,
/// so the whole subtree is laid out at `1 / factor` and drawn at `factor`:
/// same visible result, and pointer hit testing follows the transform.
///
/// The system font scale still applies on top (Hikari pins it to 1); that is
/// the one deliberate divergence — accessibility settings keep working.
class UiScale {
  const UiScale._();

  /// Hikari's range: 70 %..130 %.
  static const double min = 0.7;
  static const double max = 1.3;

  static const String boxName = 'ui_prefs';
  static const String _key = 'uiScale';

  /// Bumped on every change so the root app rebuilds with the new factor.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static double _factor = 1.0;
  static bool _loaded = false;

  static double get factor => _factor;

  static bool get isDefault => _factor == 1.0;

  static int get percent => (_factor * 100).round();

  static double clamp(double value) => value.clamp(min, max);

  /// Reads the saved factor. Called once at boot, before the first frame.
  static Future<void> load() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final raw = Hive.box<dynamic>(boxName).get(_key);
    final value = raw is num ? raw.toDouble() : 1.0;
    _factor = clamp(value);
    _loaded = true;
  }

  /// Applies and persists [value] (clamped to [min]..[max]).
  static Future<void> set(double value) async {
    _factor = clamp(value);
    _loaded = true;
    revision.value++;
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    await Hive.box<dynamic>(boxName).put(_key, _factor);
  }

  static Future<void> setPercent(int value) => set(value / 100);

  /// [child] at the chosen scale; untouched at 100 %.
  static Widget wrap(BuildContext context, Widget child) {
    if (!_loaded || _factor == 1.0) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }
        final size = Size(
          constraints.maxWidth / _factor,
          constraints.maxHeight / _factor,
        );
        return ClipRect(
          child: Transform.scale(
            scale: _factor,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Applies without touching Hive, for widget tests (real box I/O inside
  /// `testWidgets` would wait on a clock the tester does not pump).
  @visibleForTesting
  static void debugSetFactor(double value) {
    _factor = clamp(value);
    _loaded = true;
    revision.value++;
  }

  @visibleForTesting
  static void resetForTest() {
    _factor = 1.0;
    _loaded = false;
  }
}
