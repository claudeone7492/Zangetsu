import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/privacy/app_lock.dart';
import 'package:watch_app/features/privacy/app_lock_gate.dart';

class _MemoryStorage extends FlutterSecureStorage {
  _MemoryStorage() : super();
  final map = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => map[key];

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

Future<void> _pumpGate(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(home: AppLockGate(child: Text('SECRET HOME'))),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLock lock;

  setUp(() async {
    await sl.reset();
    lock = AppLock(storage: _MemoryStorage(), biometrics: _NoBiometrics());
    sl.registerSingleton<AppLock>(lock);
  });

  tearDown(() async => sl.reset());

  testWidgets('with no PIN set the app is reachable immediately', (
    tester,
  ) async {
    await _pumpGate(tester);
    expect(find.text('SECRET HOME'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-pin')), findsNothing);
  });

  testWidgets('a set PIN covers the app until the right PIN is entered', (
    tester,
  ) async {
    await lock.setPin('4821');
    await _pumpGate(tester);

    // The lock screen is up; the app content is behind it.
    expect(find.byKey(const ValueKey('app-lock-pin')), findsOneWidget);
    expect(find.text('SECRET HOME'), findsOneWidget); // still mounted under

    await tester.enterText(find.byKey(const ValueKey('app-lock-pin')), '0000');
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    // Wrong PIN: the field stays with an error.
    expect(find.byKey(const ValueKey('app-lock-pin')), findsOneWidget);
    expect(find.text('Wrong PIN, try again'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('app-lock-pin')), '4821');
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-lock-pin')), findsNothing);
    expect(find.text('SECRET HOME'), findsOneWidget);
  });
}
