import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/dub/dub_prefs.dart';

/// "Offline voices only" is a filter over the device's voice list, so what
/// matters here is that the choice survives a restart and defaults to off —
/// a viewer should not lose the better network voice without asking.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('offline-only is off until it is asked for', () async {
    final prefs = await DubPrefs.open();
    expect(prefs.offlineOnly, isFalse);
  });

  test('the choice is persisted and notified', () async {
    final prefs = await DubPrefs.open();
    var notified = 0;
    prefs.addListener(() => notified++);

    await prefs.setOfflineOnly(true);
    expect(prefs.offlineOnly, isTrue);
    expect(notified, 1);

    await prefs.setOfflineOnly(false);
    expect(prefs.offlineOnly, isFalse);
    expect(notified, 2);

    // A fresh read of the same box sees the stored value, not the default.
    await prefs.setOfflineOnly(true);
    final reopened = await DubPrefs.open();
    expect(reopened.offlineOnly, isTrue);
  });
}
