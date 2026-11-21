import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/web/userscript_store.dart';

void main() {
  group('Userscript.matchesPattern', () {
    test('wildcard scheme and host', () {
      expect(
        Userscript.matchesPattern(
          '*://*.example.com/*',
          Uri.parse('https://sub.example.com/page'),
        ),
        isTrue,
      );
      expect(
        Userscript.matchesPattern(
          '*://*.example.com/*',
          Uri.parse('https://example.com/page'),
        ),
        isTrue,
      );
      expect(
        Userscript.matchesPattern(
          '*://*.example.com/*',
          Uri.parse('https://other.com/page'),
        ),
        isFalse,
      );
    });

    test('exact host and scheme', () {
      expect(
        Userscript.matchesPattern(
          'https://example.com/*',
          Uri.parse('https://example.com/page'),
        ),
        isTrue,
      );
      expect(
        Userscript.matchesPattern(
          'http://example.com/*',
          Uri.parse('https://example.com/page'),
        ),
        isFalse,
      );
    });

    test('path glob and regex', () {
      expect(
        Userscript.matchesPattern(
          '*://example.com/watch/*',
          Uri.parse('https://example.com/watch/123'),
        ),
        isTrue,
      );
      expect(
        Userscript.matchesPattern(
          '*://example.com/watch/*',
          Uri.parse('https://example.com/browse'),
        ),
        isFalse,
      );
      expect(
        Userscript.matchesPattern(
          r'/watch\/\d+/',
          Uri.parse('https://example.com/watch/123'),
        ),
        isTrue,
      );
    });
  });

  group('UserscriptStore.parse', () {
    test('reads name, match and include headers', () {
      const text = '''
// ==UserScript==
// @name        Clean reader
// @match       *://example.com/*
// @include     https://other.com/*
// ==/UserScript==
console.log('hi');
''';
      final parsed = UserscriptStore.parse(text);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'Clean reader');
      expect(parsed.matches, ['*://example.com/*', 'https://other.com/*']);
    });

    test('rejects text without a metadata block', () {
      expect(UserscriptStore.parse('console.log(1)'), isNull);
    });
  });

  group('UserscriptStore', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('userscript_store_test');
      Hive.init(dir.path);
      await UserscriptStore.instance.init();
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    tearDown(() async {
      for (final script in UserscriptStore.instance.all) {
        await UserscriptStore.instance.remove(script.id);
      }
    });

    test('adds, matches and removes a script', () async {
      final script = await UserscriptStore.instance.add(
        name: 'Clean reader',
        matches: const ['*://example.com/*'],
        code: 'console.log(1)',
      );
      expect(UserscriptStore.instance.all, hasLength(1));
      expect(
        UserscriptStore.instance.scriptsFor(Uri.parse('https://example.com/a')),
        hasLength(1),
      );
      expect(
        UserscriptStore.instance.scriptsFor(Uri.parse('https://other.com/a')),
        isEmpty,
      );
      await UserscriptStore.instance.remove(script.id);
      expect(UserscriptStore.instance.all, isEmpty);
    });

    test('a disabled script does not match', () async {
      final script = await UserscriptStore.instance.add(
        name: 'Clean reader',
        matches: const ['*://example.com/*'],
        code: 'console.log(1)',
      );
      await UserscriptStore.instance.setEnabled(script.id, false);
      expect(
        UserscriptStore.instance.scriptsFor(Uri.parse('https://example.com/a')),
        isEmpty,
      );
    });

    test('a script without matches defaults to every site', () async {
      final script = await UserscriptStore.instance.add(
        name: 'Everywhere',
        matches: const [],
        code: 'console.log(1)',
      );
      expect(script.matches, ['*://*/*']);
      expect(
        UserscriptStore.instance.scriptsFor(Uri.parse('https://any.site/x')),
        hasLength(1),
      );
    });
  });
}
