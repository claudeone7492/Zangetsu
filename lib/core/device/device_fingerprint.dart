import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../hive/safe_box.dart';

/// Coarse device signals plus the id that survives an uninstall.
@visibleForTesting
class DeviceSignals {
  const DeviceSignals(this.platform, this.model, {this.stableId});

  final String platform;
  final String model;

  /// A value that outlives the install: Android's `ANDROID_ID` (scoped to this
  /// app's signing key, so it survives uninstall, reinstall and "clear data")
  /// or iOS's `identifierForVendor`. Null when the platform exposes nothing
  /// usable.
  final String? stableId;
}

/// Stable per-device identity — the app's account.
///
/// There is no sign-in: the backend keys subscriptions, promo redemptions,
/// profiles and watch stats on this fingerprint, and only the hash ever leaves
/// the device.
///
/// The hash is derived from the platform's stable id ([DeviceSignals.stableId])
/// so that it survives a reinstall: a subscriber who uninstalls keeps their
/// subscription (and its remaining days), and a used trial stays used. That is
/// the point of binding an entitlement to a device rather than an install — the
/// previous per-install salt let an uninstall reset both.
///
/// Two fallbacks keep existing installs intact:
///
/// * An install that already has a stored fingerprint keeps it, so this change
///   never moves a current subscriber onto a new row.
/// * A platform with no stable id (web, desktop) still gets a random salt in a
///   Hive box, which is per-install by definition.
class DeviceFingerprint {
  DeviceFingerprint._();

  static const String _boxName = 'device_identity';
  static const String _saltKey = 'salt';
  static const String _fpKey = 'fingerprint';
  static const String _keychainKey = 'zangetsu_device_id';

  /// Bumped only when the derivation changes in a way that must NOT reuse the
  /// previous value. Part of the hash input, never part of the box key.
  static const String _version = 'v2';

  static String? _cached;
  static String? _platform;
  static String? _model;

  /// Test seam: replaces the plugin-backed signal lookup.
  @visibleForTesting
  static Future<DeviceSignals> Function()? debugSignals;

  /// Test seam: forgets the memoised value so a fresh derivation can be forced.
  @visibleForTesting
  static void debugReset() {
    _cached = null;
    _platform = null;
    _model = null;
  }

  /// The fingerprint, computing and persisting it on first call.
  static Future<String> value() async {
    if (_cached != null) return _cached!;

    final box = await openBoxSafely<dynamic>(_boxName);
    final existing = box.get(_fpKey);
    if (existing is String && existing.isNotEmpty) {
      _cached = existing;
      return existing;
    }

    final info = await (debugSignals ?? _deviceSignals)();
    _platform = info.platform;
    _model = info.model;

    final stable = info.stableId;
    final String fp;
    if (stable != null && stable.isNotEmpty) {
      // Only the stable id goes into the hash. Adding the OS version or model
      // would move the identity when the device updates, and a reinstall after
      // an upgrade has to land back on the same subscription row.
      fp = sha256.convert(utf8.encode('zangetsu|$_version|$stable')).toString();
    } else {
      var salt = box.get(_saltKey);
      if (salt is! String || salt.isEmpty) {
        salt = _randomSalt();
        await box.put(_saltKey, salt);
      }
      fp = sha256
          .convert(utf8.encode('zangetsu|$salt|${info.platform}|${info.model}'))
          .toString();
    }

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
    final info = await (debugSignals ?? _deviceSignals)();
    _platform = info.platform;
    _model = info.model;
  }

  static String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// iOS keeps Keychain items across an uninstall, unlike Hive. That makes this
  /// id the iOS equivalent of Android's ANDROID_ID: clear-data and reinstall
  /// land on the same subscription row, so a used trial stays used.
  static Future<String?> _keychainStableId() async {
    try {
      const storage = FlutterSecureStorage(
        iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
      );
      final existing = await storage.read(key: _keychainKey);
      if (existing != null && existing.length >= 16) return existing;

      final fresh = _randomSalt();
      await storage.write(key: _keychainKey, value: fresh);
      return fresh;
    } catch (_) {
      // No Keychain (tests, unsupported platform) — fall back to IDFV.
      return null;
    }
  }

  /// `unknown`, `null` and `0` are what some OEMs return instead of an id;
  /// taking them at face value would collapse every such device onto one row.
  static String? _usableId(String? id) {
    final value = id?.trim();
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower == 'unknown' || lower == 'null' || lower == '0') return null;
    return value;
  }

  static Future<DeviceSignals> _deviceSignals() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) return const DeviceSignals('web', 'Web');
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        return DeviceSignals(
          'Android ${a.version.release}',
          '${a.manufacturer} ${a.model}',
          stableId: _usableId(a.id),
        );
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        final keychain = await _keychainStableId();
        return DeviceSignals(
          'iOS ${i.systemVersion}',
          i.utsname.machine,
          stableId: keychain ?? _usableId(i.identifierForVendor),
        );
      }
      if (Platform.isMacOS) {
        return DeviceSignals(
          'macOS',
          'Mac',
          stableId: await _keychainStableId(),
        );
      }
      if (Platform.isWindows) return const DeviceSignals('Windows', 'PC');
      if (Platform.isLinux) return const DeviceSignals('Linux', 'PC');
    } catch (_) {
      // No native handler (tests, unsupported platform) — coarse fallback so a
      // fingerprint is still produced.
    }
    return const DeviceSignals('unknown', 'unknown');
  }
}
