import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../hive/safe_box.dart';
import 'vx_quality.dart';

/// Music equaliser, ported from Hikari's `music/VxAudioFx.kt`.
///
/// Hikari attaches an Android `Equalizer` to the audio session and maps a
/// 15-band target curve onto the device's bands by nearest centre frequency.
/// mpv takes the curve directly, so the same 15 ISO bands become 15
/// `equalizer` filters in the `af` chain — one per band, same gains, same
/// clamp, same "bit-perfect releases everything" rule.
class VxAudioFx {
  const VxAudioFx._();

  /// 15 ISO bands, exactly Hikari's list.
  static const List<int> eqFreqs = [
    25, 40, 63, 100, 160, 250, 400, 630, 1000, 1600, 2500, 4000, 6300,
    10000, 16000,
  ];

  /// Hikari's `STUDIO_MASTER` curve, applied when "studio clarity" is on and
  /// no custom curve has been set.
  static const List<double> studioMaster = [
    2.6, 2.8, 2.2, 0.6, -1.8, -2.6, -1.2, 0.0, 1.2, 2.4, 3.6, 4.0, 4.2, 4.5,
    4.8,
  ];

  /// Hikari clamps every band to ±8 dB.
  static const double maxGain = 8;

  static const String boxName = 'music_eq';
  static const String _enabledKey = 'eqEnabled';
  static const String _gainsKey = 'eqGains';

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _enabled = false;
  static List<double> _gains = List<double>.filled(15, 0);

  static bool get eqEnabled => _enabled;
  static List<double> get gains => List<double>.unmodifiable(_gains);

  static String eqLabel(int hz) => hz >= 1000 ? '${hz ~/ 1000}K' : '$hz';

  static Future<void> load() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final box = Hive.box<dynamic>(boxName);
    _enabled = box.get(_enabledKey, defaultValue: false) as bool? ?? false;
    _gains = _parse(box.get(_gainsKey));
  }

  static List<double> _parse(dynamic raw) {
    if (raw is String) {
      final parts = raw
          .split(',')
          .map((p) => double.tryParse(p.trim()))
          .whereType<double>()
          .toList();
      if (parts.length == eqFreqs.length) {
        return parts.map((g) => g.clamp(-maxGain, maxGain)).toList();
      }
    }
    return List<double>.filled(eqFreqs.length, 0);
  }

  static Future<void> _persist() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final box = Hive.box<dynamic>(boxName);
    await box.put(_enabledKey, _enabled);
    await box.put(_gainsKey, _gains.join(','));
    revision.value++;
  }

  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _persist();
  }

  static Future<void> setGains(List<double> values) async {
    if (values.length != eqFreqs.length) return;
    _gains = values.map((g) => g.clamp(-maxGain, maxGain)).toList();
    await _persist();
  }

  /// Sets a curve and switches the equaliser on, as Hikari's `setEqPreset`.
  static Future<void> setPreset(List<double> values) async {
    if (values.length != eqFreqs.length) return;
    _gains = values.map((g) => g.clamp(-maxGain, maxGain)).toList();
    _enabled = true;
    await _persist();
  }

  /// The curve actually in force: the custom one, else the studio master when
  /// clarity is on, else flat.
  static List<double> get effectiveGains {
    if (_enabled) return _gains;
    if (VxQuality.studioClarity) return studioMaster;
    return List<double>.filled(eqFreqs.length, 0);
  }

  /// The `af` value for the music player, or null for "leave the audio alone".
  ///
  /// Bit-perfect wins over everything, exactly as in Hikari: no EQ, no
  /// enhancer, unity gain.
  static String? filterFor() {
    if (VxQuality.bitPerfect) return null;
    if (!_enabled && !VxQuality.studioClarity) return null;
    final curve = effectiveGains;
    final filters = <String>[];
    for (var i = 0; i < eqFreqs.length; i++) {
      final gain = curve[i].clamp(-maxGain, maxGain);
      if (gain.abs() < 0.05) continue;
      filters.add(
        'equalizer=f=${eqFreqs[i]}:t=q:w=1:g=${gain.toStringAsFixed(1)}',
      );
    }
    // Hikari's gentle loudness for the clarity curve only (+1.5 dB).
    if (VxQuality.studioClarity && !_enabled) filters.add('volume=1.5dB');
    if (filters.isEmpty) return null;
    return 'lavfi=[${filters.join(',')}]';
  }

  @visibleForTesting
  static void resetForTest() {
    _enabled = false;
    _gains = List<double>.filled(eqFreqs.length, 0);
  }
}
