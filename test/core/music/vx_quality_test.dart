import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/music/vx_quality.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vx_quality_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('attemptOrder starts at the preferred tier, then above, then below', () {
    expect(VxQuality.attemptOrder(VxQuality.maxHiRes), [
      VxQuality.maxHiRes,
      VxQuality.hiRes96,
      VxQuality.cdLossless,
      VxQuality.mp3_320,
    ]);
    expect(VxQuality.attemptOrder(VxQuality.cdLossless), [
      VxQuality.cdLossless,
      VxQuality.hiRes96,
      VxQuality.maxHiRes,
      VxQuality.mp3_320,
    ]);
    expect(VxQuality.attemptOrder(VxQuality.youtube), isEmpty);
  });

  test('an unknown tier falls back to the best', () async {
    await VxQuality.setStreamQuality(99);
    expect(VxQuality.streamQuality, VxQuality.maxHiRes);
  });

  test('persists the chosen tiers and switches', () async {
    await VxQuality.setPreferLossless(false);
    await VxQuality.setStreamQuality(VxQuality.hiRes96);
    await VxQuality.setDownloadQuality(VxQuality.mp3_320);
    await VxQuality.setBitPerfect(true);
    await VxQuality.setStudioClarity(false);

    await VxQuality.load();
    expect(VxQuality.preferLossless, isFalse);
    expect(VxQuality.streamQuality, VxQuality.hiRes96);
    expect(VxQuality.downloadQuality, VxQuality.mp3_320);
    expect(VxQuality.bitPerfect, isTrue);
    expect(VxQuality.studioClarity, isFalse);
  });

  test('every offered tier has a label', () {
    for (final tier in VxQuality.streamOptions) {
      expect(VxQuality.labelFor(tier), isNotEmpty);
      expect(VxQuality.shortLabelFor(tier), isNotEmpty);
    }
  });
}
