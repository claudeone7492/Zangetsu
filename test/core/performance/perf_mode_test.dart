import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/performance/perf_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('perf_mode_test');
    Hive.init(dir.path);
    await PerfMode.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  tearDown(() async {
    await PerfMode.set(false);
    PerfMode.setTvDevice(false);
  });

  test('off restores the default image cache', () {
    expect(PerfMode.active, isFalse);
    expect(PaintingBinding.instance.imageCache.maximumSize, 1000);
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 100 << 20);
  });

  test('on halves the cache', () async {
    await PerfMode.set(true);
    expect(PerfMode.active, isTrue);
    expect(PaintingBinding.instance.imageCache.maximumSize, 200);
    expect(PaintingBinding.instance.imageCache.maximumSizeBytes, 64 << 20);
  });

  test('a TV enables it without the user toggle', () {
    PerfMode.setTvDevice(true);
    expect(PerfMode.on, isFalse);
    expect(PerfMode.tvOn, isTrue);
    expect(PerfMode.active, isTrue);
  });
}
