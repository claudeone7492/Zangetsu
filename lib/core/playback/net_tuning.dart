import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// The "slow connection mode" multiplier.
///
/// Probe and playback timeouts are tuned for a healthy link; on a congested
/// mobile network those budgets expire before the first byte arrives. Rather
/// than scatter a second set of constants, every network budget goes through
/// [timeout], which doubles while the user has the toggle on.
class NetTuning {
  const NetTuning._();

  static const String boxName = 'net_tuning';

  static Box<dynamic>? _box;

  static Future<void> init() async {
    _box ??= await openBoxSafely<dynamic>(boxName);
  }

  static bool get slow => _box?.get('slow', defaultValue: false) == true;

  static Future<void> setSlow(bool value) async {
    await _box?.put('slow', value);
  }

  static Duration timeout(Duration base) => slow
      ? Duration(milliseconds: base.inMilliseconds * 2)
      : base;
}
