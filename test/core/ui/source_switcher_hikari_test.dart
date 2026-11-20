import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/di/injector.dart' show sl;
import 'package:watch_app/core/hikari/hikari_manager.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_downloader.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/ui/source_switcher.dart';

import '../../support/picker_deps.dart';

/// A `hiki:` id must type from the extension's OWN media type, and must land in
/// the matching picker bucket — a film scraper in the anime tab is the failure
/// this pins.
class _FakeManager implements ProviderRuntimeLoader {
  @override
  JsProvider? get(String id) => null;
  @override
  Future<void> load({
    required String sourceId,
    required String jsSource,
    String originRepoUrl = '',
    String displayName = '',
  }) async {}
  @override
  void setSettings(String sourceId, Map<String, dynamic> settings) {}
  @override
  void remove(String id) {}
}

class _FakeFetcher implements ProviderJsFetcher {
  @override
  Future<CachedProvider> fetch({
    required String name,
    required String url,
    bool force = false,
  }) async =>
      CachedProvider(name: name, jsCode: '', url: url, fetchedAt: DateTime.now());
  @override
  Future<void> remove(String name) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sourceTypeOf — hiki: needs the loaded extension', () {
    late Directory tempDir;
    late HikariManager mgr;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('src_switch_hikari_test');
      Hive.init(tempDir.path);
      await ProviderRegistry.init();
      await PlaybackPrefs.init();
      await CloudStreamManager.init();

      sl.registerSingleton<ProviderRegistry>(
        ProviderRegistry(downloader: _FakeFetcher(), manager: _FakeManager()),
      );
      sl.registerSingleton<PlaybackPrefs>(PlaybackPrefs());
      sl.registerSingleton<CloudStreamManager>(CloudStreamManager());
      sl.registerSingleton<AniyomiManager>(AniyomiManager());
      mgr = HikariManager();
      sl.registerSingleton<HikariManager>(mgr);
    });

    tearDownAll(() async {
      await sl.reset();
      await Hive.close();
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('a series-scraper types as ANIME', () {
      mgr.register(
        hikariSource(providerId: 'series1', name: 'Series', tvTypes: ['series']),
      );
      expect(sourceTypeOf('hiki:series1'), ProviderType.anime);
    });

    test('a film-scraper types as MOVIE', () {
      mgr.register(
        hikariSource(providerId: 'film1', name: 'Film', tvTypes: ['movie']),
      );
      expect(sourceTypeOf('hiki:film1'), ProviderType.movie);
    });

    test('a provider declaring both types reads as ANIME', () {
      // Hikari's default tvTypes is {MOVIE, SERIES}; a source that serves both
      // belongs in the streaming (anime) bucket, not the film one.
      mgr.register(
        hikariSource(
          providerId: 'both1',
          name: 'Both',
          tvTypes: ['movie', 'series'],
        ),
      );
      expect(sourceTypeOf('hiki:both1'), ProviderType.anime);
    });

    test('an unknown hiki: id falls back to ANIME rather than throwing', () {
      expect(sourceTypeOf('hiki:never-installed'), ProviderType.anime);
    });

    test('a bare "hiki" with no colon is not a Hikari source', () {
      expect(sourceTypeOf('hikiesque'), ProviderType.anime);
    });

    test('a film source lands in the movies bucket, a series source in anime',
        () {
      mgr.register(
        hikariSource(providerId: 'bucketseries', name: 'BucketSeries'),
      );
      mgr.register(
        hikariSource(
          providerId: 'bucketfilm',
          name: 'BucketFilm',
          tvTypes: ['movie'],
        ),
      );

      final buckets = categorizedSources();
      final seriesRow =
          buckets.anime.where((r) => r.id == 'hiki:bucketseries').toList();
      final filmRow =
          buckets.movies.where((r) => r.id == 'hiki:bucketfilm').toList();

      expect(seriesRow, hasLength(1));
      expect(seriesRow.single.label, 'Hikari · BucketSeries');
      expect(seriesRow.single.repo, 'Hikari');

      expect(filmRow, hasLength(1));
      expect(filmRow.single.label, 'Hikari · BucketFilm');
    });

    test('a Hikari source never leaks into the manga or novel buckets', () {
      mgr.register(hikariSource(providerId: 'noleak', name: 'NoLeak'));
      final buckets = categorizedSources();
      expect(buckets.manga.where((r) => r.id == 'hiki:noleak'), isEmpty);
      expect(buckets.novel.where((r) => r.id == 'hiki:noleak'), isEmpty);
    });

    test('an icon is carried through when the extension declares one', () {
      mgr.register(
        hikariSource(
          providerId: 'withicon',
          name: 'WithIcon',
          iconUrl: 'https://example.test/i.png',
        ),
      );
      final row = categorizedSources()
          .anime
          .firstWhere((r) => r.id == 'hiki:withicon');
      expect(row.icon, 'https://example.test/i.png');
    });
  });
}
