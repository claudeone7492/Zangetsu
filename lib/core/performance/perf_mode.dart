import 'package:flutter/painting.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// Drops the work that costs the most memory on a constrained device.
///
/// Flutter's image cache is the biggest lever an app controls directly: the
/// default holds a thousand decoded images (100 MB). Performance mode halves
/// that ceiling, and televisions get it automatically because a streaming
/// stick has far less headroom than a phone.
class PerfMode {
  const PerfMode._();

  static const String boxName = 'perf_mode';

  static Box<dynamic>? _box;
  static bool _on = false;
  static bool _tvOn = false;

  static bool get on => _on;
  static bool get tvOn => _tvOn;
  static bool get active => _on || _tvOn;

  static Future<void> init() async {
    _box = await openBoxSafely<dynamic>(boxName);
    _on = _box?.get('on', defaultValue: false) == true;
    _tvOn = _box?.get('tvOn', defaultValue: false) == true;
    apply();
  }

  static Future<void> set(bool value) async {
    _on = value;
    await _box?.put('on', value);
    apply();
  }

  static void setTvDevice(bool value) {
    if (_tvOn == value) return;
    _tvOn = value;
    apply();
  }

  static void apply() {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = active ? 200 : 1000;
    cache.maximumSizeBytes = (active ? 64 : 100) << 20;
  }
}
