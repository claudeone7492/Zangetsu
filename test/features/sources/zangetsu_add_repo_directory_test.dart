import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_config.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/provider/provider_downloader.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';
import 'package:watch_app/features/sources/zangetsu_sources_screen.dart';

/// No-op runtime loader — no source is actually installed here.
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
  void setSettings(String sourceId, Map<String, dynamic> s) {}

  @override
  void remove(String id) {}
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

/// Serves the community directory for [kSourceDirectoryUrl] and a manifest for
/// any repo added from it, so the whole discover → fill → add path runs offline.
class _DirectoryAdapter implements HttpClientAdapter {
  _DirectoryAdapter({this.directory = true});

  final bool directory;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = options.uri.toString() == kSourceDirectoryUrl
        ? (directory ? _directoryJson : 'not json at all')
        : _manifestJson;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  String get _directoryJson => jsonEncode({
    'version': 1,
    'entries': [
      {
        'name': "Spyou's manga + novel sources",
        'author': 'Spyou',
        'repoUrl': 'https://example.test/sozo/index.json',
        'description': 'MangaDex, WeebCentral, MangaPill.',
        'tags': ['manga', 'novel'],
        'verified': true,
      },
      {
        'name': 'No repo url entry',
        'author': 'nobody',
        // No repoUrl — must be dropped, not rendered as a dead suggestion.
      },
    ],
  });

  String get _manifestJson => jsonEncode({
    'name': 'Community pack',
    'sources': [
      {
        'id': 'mangadex',
        'name': 'MangaDex',
        'version': '1.0.0',
        'type': 'manga',
        'lang': 'en',
        'file': 'mangadex.js',
      },
    ],
  });

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory tempDir;
  // Hive + temp-dir I/O must happen OUTSIDE the widget test body: inside
  // testWidgets the fake-async zone never completes a real disk future.
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('community_dir_test');
    Hive.init(tempDir.path);
    await ProviderRegistry.init();
    await ProviderReposRegistry.init();
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await Hive.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  void register({bool directory = true}) {
    final sl = GetIt.instance;
    sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    sl.registerSingleton<ProviderRegistry>(
      ProviderRegistry(downloader: _FakeFetcher(), manager: _FakeManager()),
    );
    sl.registerSingleton<ProviderReposRegistry>(
      ProviderReposRegistry(
        dio: Dio()..httpClientAdapter = _DirectoryAdapter(directory: directory),
      ),
    );
  }

  Future<void> openAddRepoDialog(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ZangetsuSourcesScreen()));
    await tester.pump();
    await tester.tap(find.text('Add Zangetsu repo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('lists community repos from the directory', (tester) async {
    register();
    await openAddRepoDialog(tester);
    // The fetch resolves after the dialog is on screen.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Community repos'), findsOneWidget);
    expect(find.text("Spyou's manga + novel sources"), findsOneWidget);
    // The entry without a repoUrl is filtered out.
    expect(find.text('No repo url entry'), findsNothing);
  });

  testWidgets('tapping a suggestion fills the manifest URL field', (
    tester,
  ) async {
    register();
    await openAddRepoDialog(tester);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text("Spyou's manga + novel sources"));
    await tester.pump();

    final urlField = tester.widget<TextField>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.controller?.text == 'https://example.test/sozo/index.json',
        ),
      ),
    );
    expect(urlField.controller!.text, 'https://example.test/sozo/index.json');
  });

  testWidgets('a broken directory just hides the section', (tester) async {
    register(directory: false);
    await openAddRepoDialog(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Community repos'), findsNothing);
    // The manual URL field is still there.
    expect(find.text('Add repo'), findsOneWidget);
  });
}
