import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/web/website.dart';

void main() {
  group('normaliseUrl', () {
    test('adds https when the scheme is missing', () {
      expect(Website.normaliseUrl('example.com'), 'https://example.com');
    });

    test('keeps an explicit http(s) url and its query', () {
      expect(
        Website.normaliseUrl('https://example.com/a?b=1'),
        'https://example.com/a?b=1',
      );
      expect(Website.normaliseUrl('http://example.com'), 'http://example.com');
    });

    test('accepts localhost with a port', () {
      expect(Website.normaliseUrl('localhost:8080'), 'https://localhost:8080');
    });

    test('rejects non-web schemes and bare words', () {
      expect(Website.normaliseUrl('javascript:alert(1)'), isNull);
      expect(Website.normaliseUrl('ftp://example.com'), isNull);
      expect(Website.normaliseUrl('hello'), isNull);
      expect(Website.normaliseUrl('   '), isNull);
    });
  });

  group('identity', () {
    test('scheme and trailing slash do not create a second site', () {
      expect(
        Website.idFor('https://Example.com/'),
        Website.idFor('http://example.com'),
      );
    });

    test('path is part of the identity', () {
      expect(
        Website.idFor('https://example.com/a'),
        isNot(Website.idFor('https://example.com/b')),
      );
    });
  });

  test('nameFor strips www', () {
    expect(Website.nameFor('https://www.example.com'), 'example.com');
  });

  test('fromUrl falls back to the host when the name is blank', () {
    final site = Website.fromUrl('  ', 'example.com');
    expect(site.name, 'example.com');
    expect(site.url, 'https://example.com');
  });
}
