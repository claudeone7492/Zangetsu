import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/hikari/hikari_repo.dart';

/// The index shape here is copied from the live `codegeasse1/hikari-extensions`
/// `builds/repo.json` (203 plugins), including the `sha256-` hash prefix and
/// the integer `version` — the two fields most likely to be parsed wrongly.
String _index({
  List<Map<String, dynamic>>? plugins,
  String name = 'Hikari Extensions',
}) => jsonEncode({
  'name': name,
  'description': 'Auto-built Hikari extensions from this repo.',
  'plugins':
      plugins ??
      [
        {
          'name': '51CG',
          'description': 'Auto-built.',
          'url':
              'https://github.com/codegeasse1/hikari-extensions/releases/download/continuous/51cg.hiki',
          'version': 7,
          'fileHash':
              'sha256-99f24367a416c9a76910a06eee600ca196714b7e93a751b9b1d1fa675458e4f2',
          'tvTypes': ['movie'],
        },
      ],
});

void main() {
  group('HikariRepo.parse', () {
    test('parses the real index shape', () {
      final repo = HikariRepo.parse(_index());
      expect(repo.name, 'Hikari Extensions');
      expect(repo.entries, hasLength(1));

      final e = repo.entries.single;
      expect(e.name, '51CG');
      expect(e.version, 7);
      expect(e.tvTypes, ['movie']);
      expect(e.url, endsWith('51cg.hiki'));
    });

    test('strips the sha256- prefix from fileHash', () {
      final e = HikariRepo.parse(_index()).entries.single;
      expect(
        e.sha256Hex,
        '99f24367a416c9a76910a06eee600ca196714b7e93a751b9b1d1fa675458e4f2',
      );
      expect(e.sha256Hex, isNot(contains('sha256')));
    });

    test('a bare hex digest is accepted unchanged', () {
      final repo = HikariRepo.parse(_index(plugins: [
        {
          'name': 'X',
          'url': 'https://example.com/x.hiki',
          'version': 1,
          'fileHash': 'ABCDEF0123',
        },
      ]));
      // Normalised to lowercase so the comparison in the install path is a
      // plain string equality.
      expect(repo.entries.single.sha256Hex, 'abcdef0123');
    });

    test('a null fileHash yields a null digest, not a crash', () {
      final repo = HikariRepo.parse(_index(plugins: [
        {'name': 'X', 'url': 'https://example.com/x.hiki', 'version': 1},
      ]));
      expect(repo.entries.single.sha256Hex, isNull);
    });

    test('parses the whole 203-entry index', () {
      final plugins = [
        for (var i = 0; i < 203; i++)
          {
            'name': 'P$i',
            'url': 'https://example.com/p$i.hiki',
            'version': i + 1,
            'tvTypes': ['movie'],
          },
      ];
      expect(HikariRepo.parse(_index(plugins: plugins)).entries, hasLength(203));
    });

    test('drops entries with no name or no url', () {
      final repo = HikariRepo.parse(_index(plugins: [
        {'name': 'Good', 'url': 'https://example.com/g.hiki', 'version': 1},
        {'name': '', 'url': 'https://example.com/n.hiki', 'version': 1},
        {'name': 'NoUrl', 'version': 1},
        {'name': 'BlankUrl', 'url': '   ', 'version': 1},
      ]));
      expect(repo.entries.map((e) => e.name), ['Good']);
    });

    test('string versions are coerced to int', () {
      final repo = HikariRepo.parse(_index(plugins: [
        {'name': 'X', 'url': 'https://example.com/x.hiki', 'version': '12'},
      ]));
      expect(repo.entries.single.version, 12);
    });

    test('a missing version defaults to 1', () {
      final repo = HikariRepo.parse(_index(plugins: [
        {'name': 'X', 'url': 'https://example.com/x.hiki'},
      ]));
      expect(repo.entries.single.version, 1);
    });

    test('resolves a relative plugin url against the index url', () {
      final repo = HikariRepo.parse(
        _index(plugins: [
          {'name': 'Rel', 'url': 'plugins/rel.hiki', 'version': 1},
        ]),
        baseUrl: 'https://example.com/repo/repo.json',
      );
      expect(repo.entries.single.url, 'https://example.com/repo/plugins/rel.hiki');
    });

    test('an absolute url is never rewritten', () {
      final repo = HikariRepo.parse(
        _index(),
        baseUrl: 'https://elsewhere.example.com/repo.json',
      );
      expect(repo.entries.single.url, startsWith('https://github.com/'));
    });

    test('a nameless index gets a placeholder name', () {
      final repo = HikariRepo.parse(jsonEncode({'plugins': []}));
      expect(repo.name, 'Hikari repository');
      expect(repo.entries, isEmpty);
    });

    test('rejects a body that is not an object', () {
      expect(() => HikariRepo.parse('[]'), throwsFormatException);
    });

    test('rejects an index with no plugins array', () {
      expect(
        () => HikariRepo.parse(jsonEncode({'name': 'x'})),
        throwsFormatException,
      );
    });

    test('rejects malformed json', () {
      expect(() => HikariRepo.parse('{nope'), throwsFormatException);
    });
  });

  group('HikariRepoEntry', () {
    test('round-trips through json', () {
      const entry = HikariRepoEntry(
        name: '51CG',
        url: 'https://example.com/51cg.hiki',
        version: 7,
        description: 'd',
        fileHash: 'sha256-aa',
        tvTypes: ['movie'],
      );
      final back = HikariRepoEntry.fromJson(
        Map<String, dynamic>.from(entry.toJson()),
      );
      expect(back.name, entry.name);
      expect(back.url, entry.url);
      expect(back.version, entry.version);
      expect(back.fileHash, entry.fileHash);
      expect(back.tvTypes, entry.tvTypes);
    });

    test('ignores non-string junk in tvTypes', () {
      final e = HikariRepoEntry.fromJson({
        'name': 'X',
        'url': 'https://example.com/x.hiki',
        'version': 1,
        'tvTypes': ['movie', '', null, 5],
      });
      expect(e.tvTypes, ['movie', '5']);
    });
  });
}
