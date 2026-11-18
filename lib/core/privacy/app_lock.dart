import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Device-wide app lock: a PIN that gates the whole app on launch and again
/// after the screen has been off for a chosen delay, with an optional
/// biometric shortcut.
///
/// Deliberately separate from [ProfileLockStore]: that one gates a single
/// viewing profile from inside a running app, this one gates the app itself so
/// nothing is visible until the PIN is entered. The PIN hash and settings live
/// in secure storage; only the settings are cached in memory, so a cold start
/// can decide whether to show the gate without touching disk on the UI thread.
///
/// [ensureLoaded] is idempotent — the gate, the settings screen and any test
/// can all ask for the config and share the one read.
class AppLock extends ChangeNotifier {
  AppLock({FlutterSecureStorage? storage, LocalAuthentication? biometrics})
    : _storage = storage ?? const FlutterSecureStorage(),
      _biometrics = biometrics ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _biometrics;

  static const String _pinKey = 'app_lock_pin';
  static const String _bioKey = 'app_lock_biometric';
  static const String _relockKey = 'app_lock_relock_seconds';

  /// Offered re-lock delays, in seconds. 0 locks the moment the app leaves the
  /// foreground; the rest are a grace period so a quick app-switch (checking a
  /// code, say) doesn't force the PIN again.
  static const List<int> relockDelayChoices = <int>[0, 60, 300, 900];

  bool _enabled = false;
  bool _biometric = false;
  int _relockSeconds = 60;
  Future<void>? _loading;

  /// A PIN is set, so the gate applies. False means the app is unlocked and
  /// stays that way — the default for a fresh install.
  bool get enabled => _enabled;

  /// Whether a successful biometric prompt may stand in for the PIN.
  bool get biometricEnabled => _biometric && _enabled;

  int get relockSeconds => _relockSeconds;

  /// Valid only after [ensureLoaded]; 60 until then.
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final pin = await _storage.read(key: _pinKey);
      _enabled = pin != null && pin.isNotEmpty;
      _biometric = (await _storage.read(key: _bioKey)) == '1';
      final delay = int.tryParse(await _storage.read(key: _relockKey) ?? '');
      _relockSeconds = relockDelayChoices.contains(delay) ? delay! : 60;
    } catch (_) {
      // Secure storage unavailable (exotic platform, locked keystore): treat
      // the lock as off rather than trapping the user behind a gate that can
      // never verify them.
      _enabled = false;
      _biometric = false;
    }
    notifyListeners();
  }

  /// A PIN the gate accepts. Same floor as the profile lock (4–6 digits) so the
  /// two feel like one feature.
  static bool isValidPin(String pin) =>
      (pin.length == 4 || pin.length == 6) &&
      pin.codeUnits.every((digit) => digit >= 48 && digit <= 57);

  /// True when the device can prompt for biometrics right now. Anything
  /// (tvOS, no enrolled prints, permission denied) just reports false so the
  /// caller falls back to the PIN.
  Future<bool> get canUseBiometrics async {
    try {
      return await _biometrics.canCheckBiometrics &&
          await _biometrics.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Set (or replace) the PIN and turn the lock on. Returns false for a PIN
  /// that fails [isValidPin] — enforced here so every caller shares the floor.
  Future<bool> setPin(String pin) async {
    if (!isValidPin(pin)) return false;
    final salt = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
    try {
      await _storage.write(
        key: _pinKey,
        value: '${_hex(salt)}:${_hash(pin, salt)}',
      );
    } catch (_) {
      return false;
    }
    _enabled = true;
    notifyListeners();
    return true;
  }

  /// Check [pin] against the stored hash. A wrong PIN or an unreadable store
  /// returns false and never throws, so the gate shows its error line rather
  /// than crashing.
  Future<bool> verifyPin(String pin) async {
    if (!_enabled) return true;
    try {
      final raw = await _storage.read(key: _pinKey);
      if (raw == null) return false;
      final sep = raw.indexOf(':');
      if (sep <= 0) return false;
      final salt = _unhex(raw.substring(0, sep));
      if (salt == null) return false;
      return _constantTimeEqual(_hash(pin, salt), raw.substring(sep + 1));
    } catch (_) {
      return false;
    }
  }

  /// Turn the lock off, after [pin] is verified. Keeps nothing behind.
  Future<bool> disable(String pin) async {
    if (!await verifyPin(pin)) return false;
    try {
      await _storage.delete(key: _pinKey);
      await _storage.delete(key: _bioKey);
    } catch (_) {
      // Best-effort: even if the store is flaky the in-memory flag flips, so
      // the user isn't left staring at a gate for a lock they just removed.
    }
    _enabled = false;
    _biometric = false;
    notifyListeners();
    return true;
  }

  Future<void> setBiometricEnabled(bool value) async {
    _biometric = value && _enabled;
    notifyListeners();
    try {
      await _storage.write(key: _bioKey, value: _biometric ? '1' : '0');
    } catch (_) {}
  }

  Future<void> setRelockSeconds(int seconds) async {
    if (!relockDelayChoices.contains(seconds)) return;
    _relockSeconds = seconds;
    notifyListeners();
    try {
      await _storage.write(key: _relockKey, value: '$seconds');
    } catch (_) {}
  }

  /// One biometric attempt. False covers fail, cancel and unavailable — the
  /// caller always falls through to the PIN.
  Future<bool> authenticateBiometric(String reason) async {
    try {
      return await _biometrics.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }

  static final _secureRandom = Random.secure();

  /// SHA-256(salt + utf8(pin)), hex. Salt first so two identical PINs hash
  /// differently. Exposed for tests.
  static String hashForTest(String pin, List<int> salt) => _hash(pin, salt);

  static String _hash(String pin, List<int> salt) =>
      sha256.convert([...salt, ...utf8.encode(pin)]).toString();

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int>? _unhex(String hex) {
    if (hex.length % 2 != 0) return null;
    try {
      return [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
    } catch (_) {
      return null;
    }
  }

  /// Compare every character so a wrong PIN can't fail faster on an early
  /// byte.
  static bool _constantTimeEqual(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
