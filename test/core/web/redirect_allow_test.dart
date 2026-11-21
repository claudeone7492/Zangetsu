import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/web/redirect_allow.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('redirect_allow_test');
    Hive.init(dir.path);
    await RedirectAllow.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  tearDown(() => RedirectAllow.instance.set(const []));

  test('normalise strips scheme, path, query and port', () {
    expect(RedirectAllow.normalise('https://Example.com:443/a?b=1'), 'example.com');
    expect(RedirectAllow.normalise('cdn'), 'cdn');
  });

  test('a dotted entry allows the host and its subdomains', () async {
    await RedirectAllow.instance.set(['example.com']);
    expect(RedirectAllow.instance.allows(Uri.parse('https://example.com/x')), isTrue);
    expect(
      RedirectAllow.instance.allows(Uri.parse('https://sub.example.com/x')),
      isTrue,
    );
    expect(
      RedirectAllow.instance.allows(Uri.parse('https://notexample.com/x')),
      isFalse,
    );
  });

  test('a dot-less entry is matched as a substring of the URL', () async {
    await RedirectAllow.instance.set(['cdn']);
    expect(
      RedirectAllow.instance.allows(Uri.parse('https://cdn.example.org/x')),
      isTrue,
    );
    expect(
      RedirectAllow.instance.allows(Uri.parse('https://example.org/x')),
      isFalse,
    );
  });

  test('empty list allows nothing', () {
    expect(
      RedirectAllow.instance.allows(Uri.parse('https://example.com/x')),
      isFalse,
    );
  });
}
