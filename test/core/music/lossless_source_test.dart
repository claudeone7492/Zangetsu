import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/music/lossless_source.dart';

/// The endpoint lives in Parity tools, so it has to survive a restart: the
/// singleton the injector builds is read at startup, before any screen opens.
void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('lossless_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(LosslessSource.boxName);
    LosslessSource.configureStatic(baseUrl: '');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('ships unconfigured', () {
    expect(LosslessSource.baseUrl, isEmpty);
    final source = LosslessSource(Dio());
    expect(source.isConfigured, isFalse);
    expect(source.displayName, 'Lossless');
  });

  test('save persists the endpoint and applies it at once', () async {
    await LosslessSource.save(
      baseUrl: ' https://music.test ',
      apiKey: ' secret ',
    );
    expect(LosslessSource.baseUrl, 'https://music.test');
    expect(LosslessSource.apiKey, 'secret');

    final box = await Hive.openBox<String>(LosslessSource.boxName);
    expect(box.get('baseUrl'), 'https://music.test');
    expect(box.get('apiKey'), 'secret');
  });

  test('load reads the saved endpoint back', () async {
    await LosslessSource.save(baseUrl: 'https://music.test', apiKey: 'k');
    LosslessSource.configureStatic(baseUrl: '');
    expect(LosslessSource.baseUrl, isEmpty);

    await LosslessSource.load();
    expect(LosslessSource.baseUrl, 'https://music.test');
    expect(LosslessSource.apiKey, 'k');
    expect(LosslessSource(Dio()).isConfigured, isTrue);
  });

  test('an empty base clears both keys', () async {
    await LosslessSource.save(baseUrl: 'https://music.test', apiKey: 'k');
    await LosslessSource.save(baseUrl: '   ');

    expect(LosslessSource.baseUrl, isEmpty);
    final box = await Hive.openBox<String>(LosslessSource.boxName);
    expect(box.get('baseUrl'), isNull);
    expect(box.get('apiKey'), isNull);
  });

  test('home is empty while unconfigured instead of throwing', () async {
    final sections = await LosslessSource(Dio()).home();
    expect(sections, isEmpty);
  });
}
