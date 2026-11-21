import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/playback/net_tuning.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('net_tuning_test');
    Hive.init(dir.path);
    await NetTuning.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  tearDown(() => NetTuning.setSlow(false));

  test('is off by default and leaves the base timeout alone', () {
    expect(NetTuning.slow, isFalse);
    expect(
      NetTuning.timeout(const Duration(seconds: 8)),
      const Duration(seconds: 8),
    );
  });

  test('doubles the timeout while slow mode is on', () async {
    await NetTuning.setSlow(true);
    expect(NetTuning.slow, isTrue);
    expect(
      NetTuning.timeout(const Duration(seconds: 8)),
      const Duration(seconds: 16),
    );
  });
}
