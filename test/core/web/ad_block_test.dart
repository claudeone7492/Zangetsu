import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/web/ad_block.dart';

void main() {
  group('AdBlock.parseHosts', () {
    test('reads hosts-file lines and drops the loopback prefix', () {
      const text = '''
# ad hosts
0.0.0.0 ads.example.com
127.0.0.1 tracker.example.com # inline
::1 v6.example.com
bare.example.com
localhost
0.0.0.0 localhost
0.0.0.0 broadcasthost
0.0.0.0 0.0.0.0
''';
      expect(AdBlock.parseHosts(text), {
        'ads.example.com',
        'tracker.example.com',
        'v6.example.com',
        'bare.example.com',
      });
    });

    test('ignores comments, blank lines and single-label names', () {
      expect(AdBlock.parseHosts('\n# only a comment\n\n'), isEmpty);
      expect(AdBlock.parseHosts('0.0.0.0 localhost\n'), isEmpty);
    });
  });

  group('AdBlock', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('ad_block_test');
      Hive.init(dir.path);
      await AdBlock.instance.init();
      await Hive.box<dynamic>(AdBlock.boxName).put('hosts', [
        'ads.example.com',
        'tracker.example.com',
      ]);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    tearDown(() async {
      await AdBlock.instance.setEnabled(false);
      await AdBlock.instance.setPromosEnabled(true);
    });

    test('blocks only while enabled', () async {
      expect(AdBlock.instance.blocks(Uri.parse('https://ads.example.com/x')),
          isFalse);
      await AdBlock.instance.setEnabled(true);
      expect(
        AdBlock.instance.blocks(Uri.parse('https://ads.example.com/x')),
        isTrue,
      );
      expect(
        AdBlock.instance.blocks(Uri.parse('https://tracker.example.com')),
        isTrue,
      );
      expect(
        AdBlock.instance.blocks(Uri.parse('https://example.com/x')),
        isFalse,
      );
    });

    test('never blocks a non-http scheme', () async {
      await AdBlock.instance.setEnabled(true);
      expect(AdBlock.instance.blocks(Uri.parse('file:///ads.example.com')), isFalse);
    });

    test('reports the stored host count', () {
      expect(AdBlock.instance.hostCount, 2);
    });
  });
}
