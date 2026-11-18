import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:watch_app/core/privacy/app_lock.dart';

class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage() : super();
  final map = <String, String>{};
  bool failRead = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead) throw StateError('Secure storage unavailable');
    return map[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => map.remove(key);
}

class _NoBiometrics extends LocalAuthentication {
  @override
  Future<bool> get canCheckBiometrics async => false;

  @override
  Future<bool> isDeviceSupported() async => false;
}

AppLock _lock(_MemoryStorage storage) =>
    AppLock(storage: storage, biometrics: _NoBiometrics());

void main() {
  test('a fresh install is unlocked and enabled stays false', () async {
    final lock = _lock(_MemoryStorage());
    await lock.ensureLoaded();
    expect(lock.enabled, isFalse);
    // With no lock set, verifyPin accepts anything — nothing is gated.
    expect(await lock.verifyPin('0000'), isTrue);
  });

  test('setPin rejects a PIN below the format floor', () async {
    final lock = _lock(_MemoryStorage());
    await lock.ensureLoaded();
    expect(await lock.setPin('12'), isFalse);
    expect(await lock.setPin('12345'), isFalse); // 5 digits is neither 4 nor 6
    expect(await lock.setPin('abcd'), isFalse);
    expect(lock.enabled, isFalse);
  });

  test('setPin turns the lock on and verifyPin accepts only the real PIN',
      () async {
    final lock = _lock(_MemoryStorage());
    await lock.ensureLoaded();
    expect(await lock.setPin('4821'), isTrue);
    expect(lock.enabled, isTrue);
    expect(await lock.verifyPin('4821'), isTrue);
    expect(await lock.verifyPin('1111'), isFalse);
  });

  test('the PIN is stored salted and hashed, never in the clear', () async {
    final storage = _MemoryStorage();
    final lock = _lock(storage);
    await lock.ensureLoaded();
    await lock.setPin('1379');
    final raw = storage.map.values.single;
    expect(raw, isNot(contains('1379')));
    expect(raw, matches(RegExp(r'^[0-9a-f]{32}:[0-9a-f]{64}$')));
  });

  test('a restart keeps the lock and the same PIN', () async {
    final storage = _MemoryStorage();
    final first = _lock(storage);
    await first.ensureLoaded();
    await first.setPin('2046');

    final second = _lock(storage);
    await second.ensureLoaded();
    expect(second.enabled, isTrue);
    expect(await second.verifyPin('2046'), isTrue);
    expect(await second.verifyPin('9999'), isFalse);
  });

  test('a storage read error does not trap the user behind a gate', () async {
    final storage = _MemoryStorage()..failRead = true;
    final lock = _lock(storage);
    // Must not throw, and must leave the app reachable.
    await lock.ensureLoaded();
    expect(lock.enabled, isFalse);
  });

  test('verifyPin is false (never throws) when storage fails mid-session',
      () async {
    final storage = _MemoryStorage();
    final lock = _lock(storage);
    await lock.ensureLoaded();
    await lock.setPin('1234');
    storage.failRead = true;
    expect(await lock.verifyPin('1234'), isFalse);
  });

  test('disable requires the correct PIN and then unlocks the app', () async {
    final lock = _lock(_MemoryStorage());
    await lock.ensureLoaded();
    await lock.setPin('4321');
    expect(await lock.disable('0000'), isFalse);
    expect(lock.enabled, isTrue);
    expect(await lock.disable('4321'), isTrue);
    expect(lock.enabled, isFalse);
  });

  test('biometricEnabled only reports true once a lock is set', () async {
    final lock = _lock(_MemoryStorage());
    await lock.ensureLoaded();
    await lock.setBiometricEnabled(true);
    expect(lock.biometricEnabled, isFalse); // no lock yet
    await lock.setPin('1212');
    await lock.setBiometricEnabled(true);
    expect(lock.biometricEnabled, isTrue);
  });

  test('relock delay only accepts an offered value', () async {
    final lock = _lock(_MemoryStorage());
    await lock.ensureLoaded();
    expect(lock.relockSeconds, 60); // default
    await lock.setRelockSeconds(300);
    expect(lock.relockSeconds, 300);
    await lock.setRelockSeconds(42);
    expect(lock.relockSeconds, 300); // rejected, unchanged
  });
}
