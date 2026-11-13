import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/provider/provider_downloader.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';

/// No-op runtime loader — the native QuickJS runtime can't spin up in a test.
class _FakeManager implements ProviderRuntimeLoader {
  final Set<String> loaded = {};

  @override
  JsProvider? get(String id) => null;

  @override
  Future<void> load({
    required String sourceId,
    required String jsSource,
    String originRepoUrl = '',
    String displayName = '',
  }) async {
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
  }) async =>
      CachedProvider(name: name, jsCode: '// $name', url: url, fetchedAt: DateTime.now());

  @override
  Future<void> remove(String name) async {}
}

/// The real bundled manifest, straight from the asset on disk — so this test
/// fails if the shipped pack ever drops its manga/novel sources or retypes them.
String _bundledManifest() =>
    File('assets/providers/manifest.json').readAsStringSync();

/// Minimal DummyDio-free [ProviderReposRegistry]: parseManifest is static, and
/// cacheManifest only needs the Hive box, so a real Dio is never used here.
Dio _unusedDio() => Dio(BaseOptions(connectTimeout: const Duration(seconds: 1)));

void main() {
  late Directory tempDir;
  late ProviderRegistry registry;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mode_manifest_test');
    Hive.init(tempDir.path);
    await ProviderRegistry.init();
    await ProviderReposRegistry.init();
    final repos = ProviderReposRegistry(dio: _unusedDio());
    await repos.cacheManifest(
      ProviderReposRegistry.parseManifest('bundled://official-pack', _bundledManifest()),
    );
    registry = ProviderRegistry(
      downloader: _FakeFetcher(),
      manager: _FakeManager(),
      repos: repos,
    );
    GetIt.I.reset();
    GetIt.I.registerSingleton<ProviderRegistry>(registry);
  });

  tearDown(() async {
    GetIt.I.reset();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  test('the bundled pack classifies manga and novel sources into their modes', () {
    final types = manifestSourceTypes();

    expect(types['mangakakalot'], ProviderType.manga);
    expect(types['mangapill'], ProviderType.manga);
    expect(types['gutenberg'], ProviderType.novel);

    // Every reading source the pack ships must classify into its mode, so a
    // newly-added manga/novel source that only carries a plain JS id still
    // shows up on the Manga/Novel tabs and in a scoped search.
    for (final id in ['weebcentral', 'mangabats', 'asurascans']) {
      expect(types[id], ProviderType.manga, reason: '$id should be manga');
      expect(sourceMatchesContentMode(id, ContentMode.manga), isTrue,
          reason: '$id should match manga mode');
      expect(sourceMatchesContentMode(id, ContentMode.anime), isFalse,
          reason: '$id should not match streaming mode');
    }
    for (final id in ['novelfire', 'wattpad', 'freewebnovel', 'novelbin', 'novelight', 'inkitt', 'tapas']) {
      expect(types[id], ProviderType.novel, reason: '$id should be novel');
      expect(sourceMatchesContentMode(id, ContentMode.novel), isTrue,
          reason: '$id should match novel mode');
      expect(sourceMatchesContentMode(id, ContentMode.anime), isFalse,
          reason: '$id should not match streaming mode');
    }
    // Tapas ships as two bundled sources off one JS file: the novel half and a
    // separate comic half, each typed into its own mode.
    expect(types['tapas-comics'], ProviderType.manga, reason: 'tapas-comics is manga');
    expect(sourceMatchesContentMode('tapas-comics', ContentMode.manga), isTrue);
    expect(sourceMatchesContentMode('tapas-comics', ContentMode.novel), isFalse);

    // The bug: these are plain JS ids, so without the manifest resolver they
    // resolved as anime and Manga/Novel mode showed the "no sources" guide.
    expect(sourceMatchesContentMode('mangakakalot', ContentMode.manga), isTrue);
    expect(sourceMatchesContentMode('mangakakalot', ContentMode.anime), isFalse);
    expect(sourceMatchesContentMode('gutenberg', ContentMode.novel), isTrue);
    expect(sourceMatchesContentMode('gutenberg', ContentMode.anime), isFalse);
  });

  test('video sources still resolve as anime', () {
    expect(sourceMatchesContentMode('framextv', ContentMode.anime), isTrue);
    expect(sourceMatchesContentMode('framextv', ContentMode.manga), isFalse);
    expect(sourceMatchesContentMode('iptv', ContentMode.novel), isFalse);
  });

  test('an unregistered registry falls back to video rather than throwing', () async {
    await GetIt.I.reset();
    expect(manifestSourceTypes(), isEmpty);
    expect(sourceMatchesContentMode('mangakakalot', ContentMode.manga), isFalse);
    expect(sourceMatchesContentMode('mangakakalot', ContentMode.anime), isTrue);
  });
}
