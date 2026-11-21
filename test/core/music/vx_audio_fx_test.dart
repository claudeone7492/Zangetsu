import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/music/vx_audio_fx.dart';
import 'package:watch_app/core/music/vx_quality.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vx_audio_fx_test');
    Hive.init(dir.path);
    VxAudioFx.resetForTest();
    await VxQuality.setBitPerfect(false);
    await VxQuality.setStudioClarity(true);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('bit-perfect wins: no filter at all', () async {
    await VxQuality.setBitPerfect(true);
    expect(VxAudioFx.filterFor(), isNull);
  });

  test('studio clarity is the default curve, with its loudness nudge', () {
    final filter = VxAudioFx.filterFor();
    expect(filter, isNotNull);
    expect(filter, startsWith('lavfi=['));
    expect(filter, contains('equalizer=f='));
    expect(filter, contains('volume=1.5dB'));
  });

  test('clarity off and EQ off leaves the stream alone', () async {
    await VxQuality.setStudioClarity(false);
    expect(VxAudioFx.filterFor(), isNull);
  });

  test('a flat custom curve is a no-op', () async {
    await VxQuality.setStudioClarity(false);
    await VxAudioFx.setEnabled(true);
    await VxAudioFx.setGains(List<double>.filled(VxAudioFx.eqFreqs.length, 0));
    expect(VxAudioFx.filterFor(), isNull);
  });

  test('custom gains become equalizer filters, clamped to +/-8 dB', () async {
    await VxQuality.setStudioClarity(false);
    await VxAudioFx.setEnabled(true);
    final gains = List<double>.filled(VxAudioFx.eqFreqs.length, 0)
      ..[0] = 20
      ..[1] = -3.5;
    await VxAudioFx.setGains(gains);
    final filter = VxAudioFx.filterFor()!;
    expect(filter, contains('equalizer=f=${VxAudioFx.eqFreqs[0]}'));
    expect(filter, contains('g=8.0'));
    expect(filter, contains('g=-3.5'));
    expect(filter, isNot(contains('volume=')));
  });

  test('the studio preset is the clarity curve', () {
    expect(VxAudioFx.studioMaster, hasLength(VxAudioFx.eqFreqs.length));
  });
}
