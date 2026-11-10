import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_config.dart';
import 'package:watch_app/core/provider/default_repo_installer.dart';
import 'package:watch_app/core/provider/provider_downloader.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';

/// No-op runtime loader — no native QuickJS in a plain Dart test.
class _FakeManager implements ProviderRuntimeLoader {
  final Set<String> loaded = {};
  final Set<String> failOn = {};

  @override
  JsProvider? get(String id) => null;

  @override
  Future<void> load({
    required String sourceId,
    required String jsSource,
    String originRepoUrl = '',
    String displayName = '',
  }) async {
    if (failOn.contains(sourceId)) throw Exception('boom: $sourceId');
    loaded.add(sourceId);
  }

  @override
  void setSettings(String sourceId, Map<String, dynamic> s) {}

  @override
  void remove(String id) => loaded.remove(id);
}

class _FakeFetcher implements ProviderJsFetcher {
  @override
  Future<CachedProvider> fetch({
    required String name,
    required String url,
    bool force = false,
  }) async => CachedProvider(
    name: name,
    jsCode: '// $name',
    url: url,
    fetchedAt: DateTime.now(),
  );

  @override
  Future<void> remove(String name) async {}
}

/// Serves a canned manifest per host, so a test can make one default repo
/// answer and the others fail — proving a dead repo is skipped, not fatal.
class _ManifestAdapter implements HttpClientAdapter {
  _ManifestAdapter(this.byHost);
  final Map<String, String?> byHost;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final host = options.uri.host;
    final body = byHost[host];
    if (body == null) {
      return ResponseBody.fromString('nope', 500);
    }
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _manifest(String repoName, List<String> ids) => jsonEncode({
  'name': repoName,
  'description': '',
  'sources': [
    for (final id in ids)
      {
        'id': id,
        'name': id,
        'version': '1.0.0',
        'type': 'anime',
        'lang': 'en',
        'file': '$id.js',
      },
  ],
});

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('provision_test');
    Hive.init(tempDir.path);
    await ProviderRegistry.init();
    await ProviderReposRegistry.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  ProviderReposRegistry reposWith(Map<String, String?> byHost) =>
      ProviderReposRegistry(dio: Dio()..httpClientAdapter = _ManifestAdapter(byHost));

  ProviderRegistry registryWith(_FakeManager m) =>
      ProviderRegistry(downloader: _FakeFetcher(), manager: m);

  test('installs every source from every reachable default repo', () async {
    final manager = _FakeManager();
    final registry = registryWith(manager);
    // Every default repo host answers with a distinct source set.
    final repos = reposWith({
      'raw.githubusercontent.com': _manifest('pack', ['anikoto', 'hianime']),
    });

    final result = await provisionDefaultRepos(
      repos: repos,
      registry: registry,
      onStatus: (_, _, _) {},
    );

    expect(result.installedIds, containsAll(['anikoto', 'hianime']));
    expect(result.repoCount, greaterThan(0));
    expect(manager.loaded, containsAll(['anikoto', 'hianime']));
  });

  test('a single failing source is skipped, the rest still install', () async {
    final manager = _FakeManager()..failOn.add('hianime');
    final registry = registryWith(manager);
    final repos = reposWith({
      'raw.githubusercontent.com': _manifest('pack', ['anikoto', 'hianime']),
    });

    final result = await provisionDefaultRepos(
      repos: repos,
      registry: registry,
      onStatus: (_, _, _) {},
    );

    expect(result.installedIds, contains('anikoto'));
    expect(result.installedIds, isNot(contains('hianime')));
  });

  test('throws only when nothing at all could be installed', () async {
    final manager = _FakeManager();
    final registry = registryWith(manager);
    // No host answers → every repo fetch fails.
    final repos = reposWith({});

    expect(
      () => provisionDefaultRepos(
        repos: repos,
        registry: registry,
        onStatus: (_, _, _) {},
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('onStatus reports per-source progress', () async {
    final manager = _FakeManager();
    final registry = registryWith(manager);
    final repos = reposWith({
      'raw.githubusercontent.com': _manifest('pack', ['a', 'b']),
    });
    final seen = <String>[];

    await provisionDefaultRepos(
      repos: repos,
      registry: registry,
      onStatus: (name, done, total) => seen.add('$name:$done/$total'),
    );

    expect(seen, isNotEmpty);
    expect(seen.first, startsWith('a:1/'));
  });

  test('kDefaultRepoUrls includes the streaming + manga/novel packs', () {
    expect(kDefaultRepoUrls.length, greaterThanOrEqualTo(2));
    expect(
      kDefaultRepoUrls.any((u) => u.contains('zangetsu-providers')),
      isTrue,
    );
    expect(kDefaultRepoUrls.any((u) => u.contains('sozoread-providers')), isTrue);
  });
}
