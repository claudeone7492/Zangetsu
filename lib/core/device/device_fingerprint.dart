import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import '../hive/safe_box.dart';

/// Stable per-install device identity — the app's account.
///
/// There is no sign-in: on first launch a random salt is generated and kept in
/// a Hive box, mixed with coarse device signals, and hashed. The hash is the
/// fingerprint the backend keys everything on (subscription, promo redemption,
/// profiles, watch stats).
///
/// Only the hash ever leaves the device. The salt is never sent — it exists so
/// that two identical devices do not collapse onto one identity, and so the
/// fingerprint cannot be recomputed from device specs alone.
///
/// Reinstall: the salt box is removed with the app data, so a reinstall is a
/// new identity. That is deliberate — a reinstall is the only way a user can
/// reset a used trial, which is why the trial is also granted server-side.
class DeviceFingerprint {
  DeviceFingerprint._();

  static const String _boxName = 'device_identity';
  static const String _saltKey = 'salt';
  static const String _fpKey = 'fingerprint';

  static String? _cached;
  static String? _platform;
  static String? _model;

  /// The fingerprint, computing and persisting it on first call.
  static Future<String> value() async {
    if (_cached != null) return _cached!;

    final box = await openBoxSafely<dynamic>(_boxName);
    final existing = box.get(_fpKey);
    if (existing is String && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }

    var salt = box.get(_saltKey);
    if (salt is! String || salt.isEmpty) {
      salt = _randomSalt();
      await box.put(_saltKey, salt);
    }

    final info = await _deviceSignals();
    _platform = info.platform;
    _model = info.model;

    final fp = sha256
        .convert(utf8.encode('zangetsu|$salt|${info.platform}|${info.model}'))
        .toString();
    await box.put(_fpKey, fp);
    _cached = fp;
    return fp;
  }

  /// Platform label reported to the admin console (e.g. `Android 14`, `iOS 18`).
  static String? get platform => _platform;

  /// Human device model reported to the admin console.
  static String? get model => _model;

  /// Populates [platform]/[model] without forcing a fingerprint recompute, for
  /// callers that only need the labels (e.g. a launch-time register call).
  static Future<void> warmSignals() async {
    if (_platform != null && _model != null) return;
    final info = await _deviceSignals();
    _platform = info.platform;
    _model = info.model;
  }

  static String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  static Future<_Signals> _deviceSignals() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) return const _Signals('web', 'Web');
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        return _Signals(
          'Android ${a.version.release}',
          '${a.manufacturer} ${a.model}',
        );
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return _Signals('iOS ${i.systemVersion}', i.utsname.machine);
      }
      if (Platform.isMacOS) return const _Signals('macOS', 'Mac');
      if (Platform.isWindows) return const _Signals('Windows', 'PC');
      if (Platform.isLinux) return const _Signals('Linux', 'PC');
    } catch (_) {
      // No native handler (tests, unsupported platform) — coarse fallback so a
      // fingerprint is still produced.
    }
    return const _Signals('unknown', 'unknown');
  }
}

class _Signals {
  const _Signals(this.platform, this.model);
  final String platform;
  final String model;
}
