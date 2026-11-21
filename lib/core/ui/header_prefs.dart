import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../hive/safe_box.dart';

/// Detail header height, ported from Hikari's `ui/HeaderPrefs.kt`.
///
/// 50..150 %, 100 = the height the banner always had. Hikari keeps it in its
/// own prefs file and exposes a `heightFactorFor(scale)` that never lets the
/// header shrink below 40 % of the viewport once the UI scale is applied.
class HeaderPrefs {
  const HeaderPrefs._();

  static const int minPercent = 50;
  static const int maxPercent = 150;
  static const int defaultPercent = 100;

  static const String boxName = 'ui_prefs';
  static const String _key = 'headerHeightPercent';

  /// Bumped on every change so the detail screen rebuilds its hero.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static int _percent = defaultPercent;

  /// 50..150, 100 = unchanged.
  static int get percent => _percent;

  /// [percent] as a multiplier (1 = unchanged).
  static double get factor => _percent / 100;

  /// [factor] clamped so `scale × factor` never drops under 0.4.
  static double factorFor(double scale) {
    final s = scale.clamp(0.5, 1.5);
    final f = factor;
    return s * f < 0.4 ? 0.4 / s : f;
  }

  static Future<void> load() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final raw = Hive.box<dynamic>(boxName).get(_key);
    _percent = (raw is num ? raw.toInt() : defaultPercent).clamp(
      minPercent,
      maxPercent,
    );
  }

  static Future<void> setPercent(int percent) async {
    _percent = percent.clamp(minPercent, maxPercent);
    revision.value++;
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    await Hive.box<dynamic>(boxName).put(_key, _percent);
  }

  static Future<void> reset() => setPercent(defaultPercent);

  @visibleForTesting
  static void resetForTest() => _percent = defaultPercent;
}
