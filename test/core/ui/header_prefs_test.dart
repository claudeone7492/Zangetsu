import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/ui/header_prefs.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('header_prefs_test');
    Hive.init(dir.path);
    HeaderPrefs.resetForTest();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('clamps to 50..150 %', () async {
    await HeaderPrefs.setPercent(400);
    expect(HeaderPrefs.percent, HeaderPrefs.maxPercent);
    await HeaderPrefs.setPercent(10);
    expect(HeaderPrefs.percent, HeaderPrefs.minPercent);
    await HeaderPrefs.reset();
    expect(HeaderPrefs.percent, HeaderPrefs.defaultPercent);
  });

  test('persists the height and reloads it', () async {
    await HeaderPrefs.setPercent(130);
    HeaderPrefs.resetForTest();
    await HeaderPrefs.load();
    expect(HeaderPrefs.percent, 130);
    expect(HeaderPrefs.factor, closeTo(1.3, 1e-9));
  });

  test('factorFor folds the interface scale in and never goes under 0.4', () {
    HeaderPrefs.resetForTest();
    expect(HeaderPrefs.factorFor(1), closeTo(1, 1e-9));
    expect(HeaderPrefs.factorFor(0.5), closeTo(1, 1e-9));
  });

  test('a change bumps the revision', () async {
    final before = HeaderPrefs.revision.value;
    await HeaderPrefs.setPercent(120);
    expect(HeaderPrefs.revision.value, before + 1);
  });
}
