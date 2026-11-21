import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/device/device_fingerprint.dart';

/// The fingerprint is the app's account: subscriptions, promos and trials are
/// keyed on it server-side. These tests pin the property that makes a
/// reinstall keep its subscription — the same device must produce the same
/// fingerprint with no app data on disk.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('device_fingerprint_test');
    Hive.init(tempDir.path);
    DeviceFingerprint.debugReset();
    DeviceFingerprint.debugSignals = () async => const DeviceSignals(
      'Android 15',
      'Google Pixel 8',
      stableId: 'android-id-123',
    );
  });

  tearDown(() async {
    DeviceFingerprint.debugSignals = null;
    DeviceFingerprint.debugReset();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Uninstall: every box file goes, so the salt and the cached fingerprint
  /// with it.
  Future<void> reinstall() async {
    await Hive.deleteBoxFromDisk('device_identity');
    DeviceFingerprint.debugReset();
  }

  test('a reinstall on the same device keeps its fingerprint', () async {
    final first = await DeviceFingerprint.value();

    await reinstall();

    expect(await DeviceFingerprint.value(), first);
  });

  test('an OS or model change does not move the identity', () async {
    final first = await DeviceFingerprint.value();

    await reinstall();
    DeviceFingerprint.debugSignals = () async => const DeviceSignals(
      'Android 16',
      'Google Pixel 8 Pro',
      stableId: 'android-id-123',
    );

    // A device that updates and then reinstalls must still land on its
    // subscription row.
    expect(await DeviceFingerprint.value(), first);
  });

  test('two devices never share an identity', () async {
    final first = await DeviceFingerprint.value();

    await reinstall();
    DeviceFingerprint.debugSignals = () async => const DeviceSignals(
      'Android 15',
      'Google Pixel 8',
      stableId: 'android-id-999',
    );

    expect(await DeviceFingerprint.value(), isNot(first));
  });

  test('a stored fingerprint outranks the device signals', () async {
    final first = await DeviceFingerprint.value();

    // Same install, but the platform now reports a different id. Existing
    // installs must keep the identity their subscription is already keyed on.
    DeviceFingerprint.debugReset();
    DeviceFingerprint.debugSignals = () async => const DeviceSignals(
      'Android 15',
      'Google Pixel 8',
      stableId: 'android-id-999',
    );

    expect(await DeviceFingerprint.value(), first);
  });

  test('a platform with no stable id falls back to a per-install salt', () async {
    DeviceFingerprint.debugSignals = () async =>
        const DeviceSignals('Linux', 'PC');

    final first = await DeviceFingerprint.value();

    await reinstall();

    // Nothing survives the uninstall on such a platform, which is the old
    // behaviour rather than a regression.
    expect(await DeviceFingerprint.value(), isNot(first));
  });
}
