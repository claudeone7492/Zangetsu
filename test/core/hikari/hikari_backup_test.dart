import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/backup/sources_backup.dart';
import 'package:watch_app/core/hikari/hikari_extension_service.dart';
import 'package:watch_app/core/hikari/hikari_repo.dart';
import 'package:watch_app/core/provider/provider_registry.dart'
    show ProviderRegistry, ProviderRegistryEntry;
import 'package:watch_app/core/provider/provider_repo_registry.dart'
    show ProviderRepo, ProviderReposRegistry;

/// Hikari's backup/restore half of the migration: what `build()` emits, and
/// whether `merge()` can actually re-install from it.
///
/// The restore path is the interesting one. A repo entry's `name` is the
/// catalogue's label while our source id carries the provider id the archive
/// declares, so matching on names silently restores nothing. These tests pin
/// URL matching instead.
class _FakeHikari implements HikariExtensionService {
  _FakeHikari({List<HikariInstalled> installed = const [], this.repo})
    : _installed = List.of(installed);

  final List<HikariInstalled> _installed;
  final HikariRepo? repo;

  /// Every entry `install()` was called with, in order.
  final List<HikariRepoEntry> installedEntries = [];

  /// URLs `fetchRepo` was asked for.
  final List<String> fetched = [];

  @override
  List<HikariInstalled> installed() => List.of(_installed);

  @override
  Future<HikariRepo?> fetchRepo(String url) async {
    fetched.add(url);
    return repo;
  }

  @override
  Future<HikariInstalled?> install(
    HikariRepoEntry entry, {
    Directory? directory,
    dynamic manager,
  }) async {
    installedEntries.add(entry);
    return HikariInstalled(
      name: entry.name,
      path: '/tmp/${entry.name}.hiki',
      version: entry.version,
      providerId: entry.name.toLowerCase(),
      sourceId: 'hiki:${entry.name.toLowerCase()}',
      repoUrl: entry.url,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _EmptyRegistry implements ProviderRegistry {
  @override
  List<ProviderRegistryEntry> getAll() => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _EmptyRepos implements ProviderReposRegistry {
  @override
  List<ProviderRepo> getAll() => const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

HikariInstalled _record({
  required String id,
  String? repoUrl,
  String name = '',
}) => HikariInstalled(
  name: name.isEmpty ? id : name,
  path: '/tmp/$id.hiki',
  version: 1,
  providerId: id,
  sourceId: 'hiki:$id',
  repoUrl: repoUrl ?? '',
);

void main() {
  late Directory hiveDir;
  late Box<String> reposBox;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hikari_backup_test_');
    Hive.init(hiveDir.path);
    await HikariExtensionService.init();
    // Opened once, with its real type: re-opening the same name as a different
    // Box<T> throws, so the tests must share this handle.
    reposBox = await Hive.openBox<String>(kHikariReposBox);
  });

  setUp(() async {
    if (Hive.isBoxOpen(HikariExtensionService.installedBoxName)) {
      await Hive.box<dynamic>(HikariExtensionService.installedBoxName).clear();
    }
    await reposBox.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    try {
      await hiveDir.delete(recursive: true);
    } catch (_) {}
  });

  SourcesBackup backupWith(HikariExtensionService hikari) =>
      SourcesBackup(_EmptyRepos(), _EmptyRegistry(), null, hikari: hikari);

  group('build', () {
    test('emits the installed ids and the URL each came from', () {
      final hikari = _FakeHikari(
        installed: [
          _record(id: 'yts', repoUrl: 'https://cdn.example.com/yts.hiki'),
          _record(id: 'sideloaded'),
        ],
      );

      final data = backupWith(hikari).build();

      expect(data['hikariSources'], ['hiki:yts', 'hiki:sideloaded']);
      // Only the repo-installed one has a URL; a sideloaded `.hiki` has none,
      // and an empty string would be a lie the restore would act on.
      expect(data['hikariSourceUrls'], {
        'hiki:yts': 'https://cdn.example.com/yts.hiki',
      });
    });

    test('emits tracked repo urls from the box', () async {
      await reposBox.add('https://example.com/repo.json');

      final data = backupWith(_FakeHikari()).build();

      expect(data['hikariRepoUrls'], ['https://example.com/repo.json']);
    });

    test('a null service emits empty lists, not nulls', () {
      final backup = SourcesBackup(_EmptyRepos(), _EmptyRegistry(), null);
      final data = backup.build();
      expect(data['hikariSources'], isEmpty);
      expect(data['hikariRepoUrls'], isEmpty);
      expect(data['hikariSourceUrls'], isEmpty);
    });
  });

  group('merge', () {
    test('re-installs a missing extension by the URL the backup recorded',
        () async {
      // The catalogue no longer lists this plugin at all — the saved URL is the
      // only thing left that can restore it.
      final hikari = _FakeHikari(repo: null);
      final data = {
        'hikariSources': ['hiki:yts'],
        'hikariSourceUrls': {'hiki:yts': 'https://cdn.example.com/yts.hiki'},
        'hikariRepoUrls': const <String>[],
      };

      final failures = await backupWith(hikari).merge(data);

      expect(failures, isEmpty);
      expect(hikari.installedEntries, hasLength(1));
      expect(hikari.installedEntries.single.url,
          'https://cdn.example.com/yts.hiki');
    });

    test('prefers the catalogue entry, which carries version and hash',
        () async {
      final hikari = _FakeHikari(
        repo: HikariRepo(
          name: 'Repo',
          entries: const [
            HikariRepoEntry(
              name: 'YTS',
              url: 'https://cdn.example.com/yts.hiki',
              version: 9,
              fileHash: 'sha256-abc',
            ),
          ],
        ),
      );
      final data = {
        'hikariSources': ['hiki:yts'],
        'hikariSourceUrls': {'hiki:yts': 'https://cdn.example.com/yts.hiki'},
        'hikariRepoUrls': const <String>[],
      };

      await backupWith(hikari).merge(data);

      final entry = hikari.installedEntries.single;
      expect(entry.version, 9);
      expect(entry.fileHash, 'sha256-abc');
    });

    test('skips an extension already installed', () async {
      final hikari = _FakeHikari(
        installed: [_record(id: 'yts', repoUrl: 'https://x/yts.hiki')],
      );
      final data = {
        'hikariSources': ['hiki:yts'],
        'hikariSourceUrls': {'hiki:yts': 'https://x/yts.hiki'},
        'hikariRepoUrls': const <String>[],
      };

      final failures = await backupWith(hikari).merge(data);

      expect(failures, isEmpty);
      expect(hikari.installedEntries, isEmpty, reason: 'already present');
    });

    test('reports an extension it has no URL for instead of guessing', () async {
      // A sideloaded `.hiki` with no recorded URL cannot be re-fetched, and
      // inventing a name match is exactly the bug this replaced.
      final hikari = _FakeHikari();
      final data = {
        'hikariSources': ['hiki:sideloaded'],
        'hikariSourceUrls': const <String, String>{},
        'hikariRepoUrls': const <String>[],
      };

      final failures = await backupWith(hikari).merge(data);

      expect(hikari.installedEntries, isEmpty);
      expect(failures, contains('Hikari extension: hiki:sideloaded'));
    });

    test('reports a failed install by name', () async {
      final hikari = _FailingInstall();
      final data = {
        'hikariSources': ['hiki:yts'],
        'hikariSourceUrls': {'hiki:yts': 'https://x/yts.hiki'},
        'hikariRepoUrls': const <String>[],
      };

      final failures = await backupWith(hikari).merge(data);

      expect(failures, contains('Hikari extension: YTS'));
    });

    test('unions repo urls into the tracked list without duplicating', () async {
      await reposBox.add('https://example.com/repo.json');

      await backupWith(_FakeHikari()).merge({
        'hikariRepoUrls': [
          'https://example.com/repo.json',
          'https://other.example.com/repo.json',
        ],
      });

      expect(reposBox.values, [
        'https://example.com/repo.json',
        'https://other.example.com/repo.json',
      ]);
    });
  });
}

class _FailingInstall extends _FakeHikari {
  _FailingInstall()
    : super(
        repo: HikariRepo(
          name: 'Repo',
          entries: const [
            HikariRepoEntry(
              name: 'YTS',
              url: 'https://x/yts.hiki',
              version: 1,
            ),
          ],
        ),
      );

  @override
  Future<HikariInstalled?> install(
    HikariRepoEntry entry, {
    Directory? directory,
    dynamic manager,
  }) async => null;
}
