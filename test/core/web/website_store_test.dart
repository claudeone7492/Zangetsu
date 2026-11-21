import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/web/website_store.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('website_store_test');
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('adds, dedupes and removes sites', () async {
    final box = await Hive.openBox('website_store_unit_test');
    await box.clear();
    final store = WebsiteStore.forTesting(box);

    expect(store.sites, isEmpty);
    final first = await store.add('Films', 'example.com');
    expect(first, isNotNull);
    expect(store.sites.single.name, 'Films');
    expect(store.sites.single.url, 'https://example.com');

    // The same site under another scheme, a trailing slash and a new name is
    // one row, and the newest name wins.
    await store.add('Films 2', 'http://example.com/');
    expect(store.sites, hasLength(1));
    expect(store.sites.single.name, 'Films 2');

    expect(await store.add('', 'not a url'), isNull);
    expect(store.sites, hasLength(1));

    await store.remove(store.sites.single.id);
    expect(store.sites, isEmpty);
  });

  test('a malformed stored entry is skipped, not fatal', () async {
    final box = await Hive.openBox('website_store_bad_test');
    await box.put('sites', [
      {'url': 42},
      {'url': 'https://ok.example'},
      'nope',
    ]);
    final store = WebsiteStore.forTesting(box);
    expect(store.sites.map((s) => s.url), ['https://ok.example']);
  });
}
