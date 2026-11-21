import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/telegram/telegram_prefs.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('telegram_prefs_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('adds, dedupes and removes channels', () async {
    final box = await Hive.openBox('telegram_prefs_unit_test');
    await box.clear();
    final prefs = TelegramPrefs.forTesting(box);

    expect(prefs.allChannels, isEmpty);
    expect(await prefs.addChannel('@films'), '@films');
    expect(await prefs.addChannel('https://t.me/films'), '@films');
    expect(prefs.channels, ['@films']);
    expect(await prefs.addChannel('not a channel'), isNull);
    expect(prefs.channels, ['@films']);

    await prefs.removeChannel('@films');
    expect(prefs.channels, isEmpty);
  });
}
