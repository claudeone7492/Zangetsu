import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/provider/js_pack_bootstrap.dart';
import 'package:watch_app/core/provider/js_pack_engine.dart';
import 'package:watch_app/core/provider/js_pack_manager.dart';
import 'package:watch_app/core/provider/js_pack_module.dart';
import 'package:watch_app/core/provider/js_pack_provisioner.dart';
import 'package:watch_app/core/provider/provider_manager.dart';

/// A real HTTP server the manager fetches repos and modules from — no mocks, so
/// the fetch/parse/install path runs exactly as it does in the app.
class _Server {
  _Server(this._srv);

  final HttpServer _srv;
  final Map<String, String Function(Uri)> _routes = {};

  static Future<_Server> start() async {
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = _Server(srv);
    srv.listen((req) async {
      final handler = s._routes[req.uri.path];
      if (handler == null) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(handler(req.uri));
      await req.response.close();
    });
    return s;
  }

  String get base => 'http://127.0.0.1:${_srv.port}';

  void on(String path, String Function(Uri) body) => _routes[path] = body;

  Future<void> close() => _srv.close(force: true);
}

/// A minimal module in the shape the families publish: a CommonJS export with
/// the canonical method names.
const String _moduleJs = '''
module.exports = {
  name: 'Probe Pack',
  lang: 'en',
  type: 'movie',
  baseUrl: 'https://probe.example',
  getInfo: function() {
    return { name: 'Probe Pack', lang: 'en', baseUrl: 'https://probe.example', type: 'movie' };
  },
  getHome: function(opts) {
    return [{ title: 'Trending', items: [
      { id: 'one', title: 'One', url: '/one', type: 'movie', cover: 'https://probe.example/1.jpg' }
    ]}];
  },
  search: function(q, page, opts) {
    return [{ id: 'one', title: 'One', url: '/one', type: 'movie' }];
  },
  getDetail: function(url, opts) {
    return { id: 'one', title: 'One', url: url, type: 'movie', description: 'desc' };
  },
  getEpisodes: function(url, opts) {
    return [{ id: 'e1', title: 'Episode 1', number: 1, url: '/e1' }];
  },
  getStreams: function(url, opts) {
    return [{ url: 'https://probe.example/stream.m3u8', quality: '1080p', container: 'hls' }];
  }
};
''';

/// The same module under Hikari's dialect: `getItem` instead of `getDetail`,
/// `getStreams` for streams, and no `getInfo`.
const String _hikariModuleJs = '''
module.exports = {
  name: 'Hikari Probe',
  lang: 'en',
  type: 'anime',
  site: 'https://hikari.example',
  getHome: function() {
    return [{ title: 'Latest', items: [
      { id: 'a1', title: 'A1', url: '/a1', type: 'anime' }
    ]}];
  },
  getItem: function(url) {
    return { id: 'a1', title: 'A1', url: url, type: 'anime' };
  },
  getStreams: function(url) {
    return [{ url: 'https://hikari.example/s.m3u8' }];
  }
};
''';

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pack_test_');
    Hive.init(dir.path);
  });

  group('JsPackEngine', () {
    test('routes each family by prefix and strips it for the module id', () {
      expect(JsPackEngine.forSourceId('nuvio:tmdb'), JsPackEngine.nuvio);
      expect(JsPackEngine.forSourceId('vega:x'), JsPackEngine.vega);
      expect(JsPackEngine.forSourceId('sora:x'), JsPackEngine.sora);
      expect(JsPackEngine.forSourceId('sky:x'), JsPackEngine.skystream);
      expect(JsPackEngine.forSourceId('hiki:x'), JsPackEngine.hiki);
      expect(JsPackEngine.forSourceId('kot:x'), JsPackEngine.kotatsu);
      expect(JsPackEngine.forSourceId('anikoto'), isNull);
      expect(JsPackEngine.forSourceId('us:foo'), isNull);
      expect(JsPackEngine.nuvio.moduleIdOf('nuvio:tmdb'), 'tmdb');
      expect(JsPackEngine.nuvio.moduleIdOf('tmdb'), 'tmdb');
    });

    test('every family has a distinct prefix and Hive box', () {
      final prefixes = JsPackEngine.values.map((e) => e.prefix).toSet();
      final boxes = JsPackEngine.values.map((e) => e.box).toSet();
      expect(prefixes.length, JsPackEngine.values.length);
      expect(boxes.length, JsPackEngine.values.length);
    });
  });

  group('JsPackModule.parseRepo', () {
    test('parses the sources envelope and resolves relative module files', () {
      final mods = JsPackModule.parseRepo(
        jsonEncode({
          'sources': [
            {'id': 'tmdb', 'name': 'TMDB', 'file': 'tmdb.js', 'type': 'movie'},
          ],
        }),
        engine: JsPackEngine.nuvio,
        repoUrl: 'https://host.example/repo/index.json',
      );
      expect(mods, hasLength(1));
      expect(mods.single.id, 'tmdb');
      expect(mods.single.sourceId, 'nuvio:tmdb');
      expect(mods.single.file, 'https://host.example/repo/tmdb.js');
      expect(mods.single.providerType.name, 'movie');
    });

    test('parses a bare array (Vega shape) and an entries envelope', () {
      final bare = JsPackModule.parseRepo(
        jsonEncode([
          {'name': 'A', 'url': 'https://cdn.example/a.js'},
          {'name': 'B', 'url': 'https://cdn.example/b.js'},
        ]),
        engine: JsPackEngine.vega,
        repoUrl: 'https://host.example/manifest.json',
      );
      expect(bare.map((m) => m.id), ['A', 'B']);

      final entries = JsPackModule.parseRepo(
        jsonEncode({
          'entries': [
            {'id': 'c', 'js': 'module.exports={};'},
          ],
        }),
        engine: JsPackEngine.sora,
        repoUrl: 'https://host.example/index.json',
      );
      expect(entries.single.code, 'module.exports={};');
    });

    test('drops entries with no id or no way to fetch the code', () {
      final mods = JsPackModule.parseRepo(
        jsonEncode({
          'sources': [
            {'name': 'no id'},
            {'id': 'nofile'},
            {'id': 'ok', 'file': 'ok.js'},
          ],
        }),
        engine: JsPackEngine.nuvio,
        repoUrl: 'https://host.example/index.json',
      );
      expect(mods.map((m) => m.id), ['ok']);
    });

    test('deduplicates repeated ids, first definition winning', () {
      final mods = JsPackModule.parseRepo(
        jsonEncode({
          'sources': [
            {'id': 'dup', 'name': 'First', 'file': 'a.js'},
            {'id': 'dup', 'name': 'Second', 'file': 'b.js'},
          ],
        }),
        engine: JsPackEngine.nuvio,
        repoUrl: 'https://host.example/index.json',
      );
      expect(mods, hasLength(1));
      expect(mods.single.name, 'First');
    });

    test('malformed JSON yields no modules rather than throwing', () {
      expect(
        JsPackModule.parseRepo(
          'not json',
          engine: JsPackEngine.nuvio,
          repoUrl: 'https://host.example/index.json',
        ),
        isEmpty,
      );
    });

    test('round-trips through toJson/fromJson with the engine preserved', () {
      const mod = JsPackModule(
        engine: JsPackEngine.kotatsu,
        id: 'manga',
        name: 'Manga',
        type: 'manga',
        code: 'module.exports={};',
        repoUrl: 'https://host.example/index.json',
      );
      final back = JsPackModule.fromJson(mod.toJson());
      expect(back.engine, JsPackEngine.kotatsu);
      expect(back.id, 'manga');
      expect(back.providerType.name, 'manga');
      expect(back.isReading, isTrue);
      expect(back.code, 'module.exports={};');
    });
  });

  group('wrapJsPackModule', () {
    test('registers the canonical method names the runtime calls', () {
      final js = wrapJsPackModule('nuvio:tmdb', _moduleJs);
      for (final name in [
        'getInfo',
        'getHome',
        'popular',
        'search',
        'getDetail',
        'getEpisodes',
        'getVideoSources',
      ]) {
        expect(js.contains('$name:'), isTrue, reason: 'missing $name');
      }
    });

    test('maps Hikari dialect names onto the canonical slots', () {
      final js = wrapJsPackModule('hiki:probe', _hikariModuleJs);
      expect(js.contains("'getDetail', 'getItem'"), isTrue);
      expect(js.contains("'getVideoSources', 'getStreams'"), isTrue);
    });
  });

  group('JsPackManager (live server)', () {
    late _Server srv;
    late JsPackManager manager;
    late ProviderManager runtime;

    setUp(() async {
      // One Hive box per family is shared by every manager in this file, so
      // each test starts from an empty box rather than inheriting the last
      // test's installs (which is also what a fresh device looks like).
      final box = await Hive.openBox<dynamic>(JsPackEngine.nuvio.box);
      await box.clear();
      srv = await _Server.start();
      runtime = ProviderManager(dio: Dio());
      manager = JsPackManager(engine: JsPackEngine.nuvio, runtime: runtime);
      await manager.init();
    });

    tearDown(() async {
      runtime.disposeAll();
      await srv.close();
    });

    // The QuickJS bridge is an Android/iOS native plugin, so these tests assert
    // the fetch/parse/persist half of the install path — the half that is pure
    // Dart and identical on every platform. Loading the module into the runtime
    // is covered by `wrapJsPackModule` above (the JS it evaluates).
    test('installs a repo, persists the module code and its repo url', () async {
      srv.on('/index.json', (_) => jsonEncode({
            'sources': [
              {'id': 'probe', 'name': 'Probe Pack', 'file': 'probe.js'},
            ],
          }));
      srv.on('/probe.js', (_) => _moduleJs);

      final ids = await manager.addRepository('${srv.base}/index.json');

      expect(ids, ['probe']);
      expect(manager.all.single.sourceId, 'nuvio:probe');
      expect(manager.repositories, ['${srv.base}/index.json']);
      // Code is fetched at install time so a later boot needs no network.
      expect(manager.moduleFor('nuvio:probe')?.code, contains('getHome'));
      expect(manager.revision, greaterThan(0));
    });

    test('a fresh manager rehydrates installed modules from Hive', () async {
      srv.on('/index.json', (_) => jsonEncode({
            'sources': [
              {'id': 'probe', 'name': 'Probe Pack', 'file': 'probe.js'},
            ],
          }));
      srv.on('/probe.js', (_) => _moduleJs);
      await manager.addRepository('${srv.base}/index.json');

      final reopened = JsPackManager(
        engine: JsPackEngine.nuvio,
        runtime: runtime,
      );
      await reopened.init();

      expect(reopened.moduleFor('nuvio:probe')?.name, 'Probe Pack');
      expect(reopened.moduleFor('nuvio:probe')?.code, contains('getHome'));
      expect(reopened.repositories, ['${srv.base}/index.json']);
    });

    test('a repo whose module 404s installs its good modules only', () async {
      srv.on('/index.json', (_) => jsonEncode({
            'sources': [
              {'id': 'good', 'name': 'Good', 'file': 'good.js'},
              {'id': 'bad', 'name': 'Bad', 'file': 'missing.js'},
            ],
          }));
      srv.on('/good.js', (_) => _moduleJs);

      final ids = await manager.addRepository('${srv.base}/index.json');

      expect(ids, ['good']);
      expect(manager.moduleFor('nuvio:bad'), isNull);
    });

    test('uninstall drops the module from memory and from Hive', () async {
      srv.on('/index.json', (_) => jsonEncode({
            'sources': [
              {'id': 'probe', 'name': 'Probe Pack', 'file': 'probe.js'},
            ],
          }));
      srv.on('/probe.js', (_) => _moduleJs);
      await manager.addRepository('${srv.base}/index.json');
      expect(manager.moduleFor('nuvio:probe'), isNotNull);

      await manager.uninstall('nuvio:probe');

      expect(manager.moduleFor('nuvio:probe'), isNull);
      expect(manager.all, isEmpty);

      final reopened = JsPackManager(
        engine: JsPackEngine.nuvio,
        runtime: runtime,
      );
      await reopened.init();
      expect(reopened.moduleFor('nuvio:probe'), isNull);
    });

    test('restore is union-only and never clobbers an installed module', () async {
      srv.on('/index.json', (_) => jsonEncode({
            'sources': [
              {'id': 'probe', 'name': 'Local Name', 'file': 'probe.js'},
            ],
          }));
      srv.on('/probe.js', (_) => _moduleJs);
      await manager.addRepository('${srv.base}/index.json');

      await manager.restore([
        const JsPackModule(
          engine: JsPackEngine.nuvio,
          id: 'probe',
          name: 'Backup Name',
          code: 'module.exports={};',
        ),
        const JsPackModule(
          engine: JsPackEngine.nuvio,
          id: 'extra',
          name: 'Extra',
          code: 'module.exports={};',
        ),
      ], repoUrls: ['https://restored.example/index.json']);

      expect(manager.moduleFor('nuvio:probe')?.name, 'Local Name');
      expect(manager.moduleFor('nuvio:extra')?.name, 'Extra');
      expect(manager.repositories, contains('https://restored.example/index.json'));
    });

    test('provisionPackDefaults installs from the given repo list', () async {
      srv.on('/index.json', (_) => jsonEncode({
            'sources': [
              {'id': 'probe', 'name': 'Probe Pack', 'file': 'probe.js'},
            ],
          }));
      srv.on('/probe.js', (_) => _moduleJs);

      final result = await provisionPackDefaults(
        manager: manager,
        repoUrls: ['${srv.base}/index.json'],
      );

      expect(result.installedIds, ['probe']);
      expect(result.repoCount, 1);
      expect(result.isEmpty, isFalse);
    });

    test('provisionPackDefaults survives an unreachable repo', () async {
      final result = await provisionPackDefaults(
        manager: manager,
        repoUrls: ['http://127.0.0.1:1/index.json'],
      );
      expect(result.installedIds, isEmpty);
      expect(result.repoCount, 0);
    });
  });
}
