import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/music/music_prefs.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('music_prefs');
    Hive.init(dir.path);
    await MusicPrefs.init();
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(MusicPrefs.boxName);
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('defaults to high quality before anything is chosen', () {
    expect(MusicPrefs.quality, MusicQuality.high);
  });

  test('a chosen quality survives a fresh read', () async {
    await MusicPrefs.setQuality(MusicQuality.dataSaver);
    expect(MusicPrefs.quality, MusicQuality.dataSaver);
  });

  test('writing bumps revision so an open player notices', () async {
    final before = MusicPrefs.revision.value;
    await MusicPrefs.setQuality(MusicQuality.balanced);
    expect(MusicPrefs.revision.value, before + 1);
  });

  test('a stored value from a future build falls back to high', () async {
    await Hive.box(MusicPrefs.boxName).put('quality', 'ultraLossless');
    expect(
      MusicPrefs.quality,
      MusicQuality.high,
      reason: 'an unknown name must not break playback',
    );
  });

  test('a non-string stored value falls back to high', () async {
    await Hive.box(MusicPrefs.boxName).put('quality', 320);
    expect(MusicPrefs.quality, MusicQuality.high);
  });

  test('each quality carries the bitrate ceiling the source applies', () {
    expect(MusicQuality.dataSaver.kbps, lessThan(MusicQuality.balanced.kbps));
    expect(MusicQuality.balanced.kbps, lessThan(MusicQuality.high.kbps));
  });
}
