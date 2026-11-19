import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/dub/dub_engine.dart';
import 'package:watch_app/core/dub/dub_prefs.dart';
import 'package:watch_app/core/dub/switching_dub_engine.dart';

/// Records what it was asked to do, so the test asserts on real delegation
/// rather than on the switcher's own bookkeeping.
class _FakeEngine implements DubEngine {
  _FakeEngine({this.available = true});

  final bool available;
  final List<String> spoken = [];
  int stops = 0;
  bool disposed = false;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<DubVoice>> voices() async => const [
    DubVoice(name: 'Fake', locale: 'en-GB'),
  ];

  @override
  Future<void> speak(
    String text, {
    String? voice,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    spoken.add(text);
  }

  @override
  Future<void> stop() async => stops++;

  @override
  void dispose() => disposed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DubPrefs prefs;
  late _FakeEngine device;
  late _FakeEngine neural;
  late SwitchingDubEngine engine;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
    prefs = await DubPrefs.open();
    device = _FakeEngine();
    neural = _FakeEngine();
    engine = SwitchingDubEngine(prefs: prefs, device: device, neural: neural);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  test('uses the device engine by default', () async {
    expect(prefs.voiceEngine, kDubEngineDevice);
    expect(engine.active, same(device));

    await engine.speak('hello');
    expect(device.spoken, ['hello']);
    expect(neural.spoken, isEmpty);
  });

  test('uses the neural engine once selected', () async {
    await prefs.setVoiceEngine(kDubEngineNeural);
    expect(engine.active, same(neural));

    await engine.speak('hello');
    expect(neural.spoken, ['hello']);
    expect(device.spoken, isEmpty);
  });

  test('an unknown engine id falls back to the device', () async {
    await prefs.setVoiceEngine('nonsense');
    expect(prefs.voiceEngine, kDubEngineDevice);
  });

  test('a device with no voice still reports available when neural is picked',
      () async {
    final noVoiceDevice = _FakeEngine(available: false);
    final switcher = SwitchingDubEngine(
      prefs: prefs,
      device: noVoiceDevice,
      neural: neural,
    );

    expect(await switcher.isAvailable(), isFalse);
    await prefs.setVoiceEngine(kDubEngineNeural);
    expect(await switcher.isAvailable(), isTrue);
  });

  test('voices come from whichever engine is active', () async {
    expect((await engine.voices()).single.name, 'Fake');
    await prefs.setVoiceEngine(kDubEngineNeural);
    expect((await engine.voices()).single.name, 'Fake');
  });

  test('speaking cuts the other engine so both never talk at once', () async {
    await engine.speak('hello');
    expect(neural.stops, 1);

    await prefs.setVoiceEngine(kDubEngineNeural);
    await engine.speak('again');
    expect(device.stops, greaterThanOrEqualTo(1));
  });

  test('stop silences both engines', () async {
    await engine.stop();
    expect(device.stops, 1);
    expect(neural.stops, 1);
  });

  test('dispose disposes both engines', () {
    engine.dispose();
    expect(device.disposed, isTrue);
    expect(neural.disposed, isTrue);
  });

  test('the neural language follows the narration language', () async {
    expect(prefs.effectiveNeuralLanguage, 'en');

    await prefs.setLanguage('es');
    expect(prefs.effectiveNeuralLanguage, 'es');

    await prefs.setNeuralLanguage('ja');
    expect(prefs.effectiveNeuralLanguage, 'ja');

    await prefs.setNeuralLanguage(null);
    expect(prefs.effectiveNeuralLanguage, 'es');
  });
}
