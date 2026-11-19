import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/dub/dub_engine.dart';
import 'package:watch_app/core/dub/dub_narrator.dart';
import 'package:watch_app/core/dub/dub_prefs.dart';

import 'dart:io';

/// Records what it was asked to say, so the test asserts on the real calls the
/// narrator makes rather than on a stub's own bookkeeping.
class FakeDubEngine implements DubEngine {
  final List<String> spoken = [];
  final List<({String? voice, double rate, double pitch, double volume})>
  options = [];
  int stopCount = 0;
  bool disposed = false;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<DubVoice>> voices() async => const [
    DubVoice(name: 'Test', locale: 'en-GB'),
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
    options.add((voice: voice, rate: rate, pitch: pitch, volume: volume));
  }

  @override
  Future<void> stop() async => stopCount++;

  @override
  void dispose() => disposed = true;
}

const _srt =
    '1\n'
    '00:00:01,000 --> 00:00:03,000\n'
    'First line\n'
    '\n'
    '2\n'
    '00:00:05,000 --> 00:00:07,000\n'
    'Second line\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late DubPrefs prefs;
  late FakeDubEngine engine;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
    prefs = await DubPrefs.open();
    engine = FakeDubEngine();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  DubNarrator narrator({
    Future<String?> Function(String, String)? translate,
  }) => DubNarrator(prefs: prefs, engine: engine, translate: translate);

  test('loads cues from a subtitle file', () async {
    final n = narrator();
    await n.load('ep1', _srt);
    expect(n.isReady, isTrue);
    expect(n.cueCount, 2);
    expect(n.error, isNull);
  });

  test('says nothing while dub is switched off', () async {
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, isEmpty);
  });

  test('speaks the due cue once dub is on', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, ['First line']);
  });

  test('speaks each cue once across repeated ticks', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', _srt);
    for (var ms = 1000; ms < 4000; ms += 100) {
      await n.onPosition(Duration(milliseconds: ms));
    }
    expect(engine.spoken, ['First line']);
  });

  test('a second cue speaks when its time comes', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    await n.onPosition(const Duration(seconds: 6));
    expect(engine.spoken, ['First line', 'Second line']);
  });

  test('passes the saved voice, rate, pitch and volume to the engine', () async {
    await prefs.setEnabled(true);
    await prefs.setVoice('en-GB-x');
    await prefs.setRate(1.5);
    await prefs.setPitch(0.8);
    await prefs.setVolume(0.4);
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));

    expect(engine.options.single.voice, 'en-GB-x');
    expect(engine.options.single.rate, 1.5);
    expect(engine.options.single.pitch, 0.8);
    expect(engine.options.single.volume, 0.4);
  });

  test('a seek stops speech and re-anchors', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    n.onSeek(const Duration(seconds: 5));
    expect(engine.stopCount, 1);
    // The cue at 5s is due after the seek.
    await n.onPosition(const Duration(seconds: 5));
    expect(engine.spoken, ['First line', 'Second line']);
  });

  test('a pause cuts the current line', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    n.onPause();
    expect(engine.stopCount, 1);
    expect(n.speaking, isNull);
  });

  test('switching dub off mid-session stops speech', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    // Turning it off in the sheet is enough: the narrator follows the prefs,
    // so nothing has to remember to forward the change.
    await prefs.setEnabled(false);
    expect(engine.stopCount, 1);
  });

  test('a pure sound-effect cue is skipped by default', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load(
      'ep1',
      '1\n'
      '00:00:01,000 --> 00:00:03,000\n'
      '[CROWD CHEERING]\n',
    );
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, isEmpty);
  });

  test('sound-effect cues are spoken when skipping is turned off', () async {
    await prefs.setEnabled(true);
    await prefs.setSkipSoundEffects(false);
    final n = narrator();
    await n.load(
      'ep1',
      '1\n'
      '00:00:01,000 --> 00:00:03,000\n'
      '[CROWD CHEERING]\n',
    );
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, ['[CROWD CHEERING]']);
  });

  test('translates the cue first when a language is set', () async {
    await prefs.setEnabled(true);
    await prefs.setLanguage('fr');
    final asked = <String>[];
    final n = narrator(
      translate: (text, lang) async {
        asked.add('$text/$lang');
        return 'Bonjour';
      },
    );
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    expect(asked, ['First line/fr']);
    expect(engine.spoken, ['Bonjour']);
  });

  test('a failed translation speaks the original instead of nothing', () async {
    await prefs.setEnabled(true);
    await prefs.setLanguage('fr');
    final n = narrator(
      translate: (_, _) async => throw StateError('offline'),
    );
    await n.load('ep1', _srt);
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, ['First line']);
  });

  test('loading the same track twice does not reload', () async {
    final n = narrator();
    await n.load('ep1', _srt);
    await n.load('ep1', _srt);
    expect(n.cueCount, 2);
  });

  test('an unreadable track reports an error and stays inert', () async {
    await prefs.setEnabled(true);
    final n = narrator();
    await n.load('ep1', 'not subtitles');
    expect(n.isReady, isFalse);
    expect(n.error, isNotNull);
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, isEmpty);
  });

  test('clear drops the cues so a dead track is not narrated', () async {
    final n = narrator();
    await prefs.setEnabled(true);
    await n.load('ep1', '1\n00:00:01,000 --> 00:00:04,000\nHello\n');
    expect(n.cueCount, 1);

    n.clear();

    expect(n.cueCount, 0);
    expect(n.loadedKey, isNull);
    expect(n.speaking, isNull);
    await n.onPosition(const Duration(seconds: 2));
    expect(engine.spoken, isEmpty);
  });

  test('dispose stops speech but leaves the shared engine alive', () {
    final n = narrator();
    n.dispose();
    // The engine is a DI singleton: disposing it here would break the next
    // player session that narrates.
    expect(engine.disposed, isFalse);
    expect(engine.stopCount, greaterThan(0));
  });
}
