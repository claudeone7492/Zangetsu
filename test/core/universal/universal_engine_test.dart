import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/universal/universal_config.dart';
import 'package:watch_app/core/universal/universal_manager.dart';
import 'package:watch_app/core/universal/universal_provider.dart';

/// A tiny HTTP server the provider talks to for real — no mocks. Every test
/// path (fetch, parse, resolve) runs exactly as it does in the app.
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

Future<String> _http(String url, {Map<String, String>? headers}) async {
  final client = HttpClient();
  final req = await client.getUrl(Uri.parse(url));
  headers?.forEach(req.headers.set);
  final res = await req.close();
  final body = await res.transform(utf8.decoder).join();
  client.close();
  return body;
}

UniversalConfig apiConfig(String base) => UniversalConfig.fromJson({
  'id': 'probe',
  'name': 'Probe API',
  'baseUrl': base,
  'type': 'movie',
  'api': {
    'base': base,
    'homePath': '/home',
    'catalogs': [
      {'id': 'items', 'name': 'Featured'},
    ],
    'searchPath': '/search?q={query}',
    'searchResults': 'hits',
    'detailPath': '/meta/{id}',
    'detailData': 'meta',
    'episodesPath': '/meta/{id}',
    'episodesItems': '__single__',
    'streamsLangs': '',
    'streamsUrlTemplate': '$base/dl/{id}/<ext>',
    'streamsExtensions': 'mp4',
    'streamsMetaPath': '/meta/{id}',
    'posterTemplate': '$base/img/{id}',
    'idField': 'id',
    'titleField': 'title',
    'posterField': 'image',
  },
});

UniversalConfig htmlConfig(String base) => UniversalConfig.fromJson({
  'id': 'htmlprobe',
  'name': 'Probe HTML',
  'baseUrl': base,
  'type': 'anime',
  'catalogs': [
    {
      'id': 'home',
      'name': 'Latest',
      'path': '/',
      'item': '.card',
      'title': '.title',
      'href': 'a@href',
      'poster': 'img@src',
    },
  ],
  'search': {
    'path': '/search?q={query}',
    'item': '.card',
    'title': '.title',
    'href': 'a@href',
    'poster': 'img@src',
  },
  'detail': {
    'title': 'h1.name',
    'poster': 'meta[property=og:image]@content',
    'overview': '.synopsis',
    'genres': 'a[href*=genre]',
    'type': 'anime',
  },
  'episodes': {
    'item': '.ep',
    'href': 'a@href',
    'title': 'a',
  },
  'streams': {'iframe': 'iframe@src'},
});

void main() {
  group('API mode', () {
    late _Server srv;
    late UniversalProvider p;

    setUp(() async {
      srv = await _Server.start();
      srv.on('/home', (_) => jsonEncode({
        'items': [
          {'id': 'a1', 'title': 'Alpha', 'image': '/i/a1.jpg'},
          {'id': 'a2', 'title': 'Beta'},
        ],
      }));
      srv.on('/search', (uri) => jsonEncode({
        'hits': [
          {'id': 's1', 'title': 'Found ${uri.queryParameters['q']}'},
        ],
      }));
      srv.on('/meta/a1', (_) => jsonEncode({
        'meta': {
          'id': 'a1',
          'title': 'Alpha',
          'description': 'An alpha thing',
          'genres': ['Drama'],
          'year': '2020',
          'image': '/i/a1.jpg',
        },
        'files': [
          {'name': 'Alpha.ia.mp4'},
          {'name': 'Alpha film.mp4'},
        ],
      }));
      p = UniversalProvider(config: apiConfig(srv.base), fetch: _http);
    });

    tearDown(() => srv.close());

    test('home reads the catalog path and builds absolute posters', () async {
      final home = await p.getHome();
      expect(home, isNotNull);
      expect(home!.single.title, 'Featured');
      final items = home.single.items;
      expect(items.map((i) => i.title), ['Alpha', 'Beta']);
      expect(items.first.cover, '${srv.base}/i/a1.jpg');
      // No image field → posterTemplate fills in.
      expect(items[1].cover, '${srv.base}/img/a2');
    });

    test('search substitutes and encodes the query', () async {
      final hits = await p.search('a b&c', 1);
      expect(hits.single.title, 'Found a b&c');
    });

    test('detail maps fields through detailData', () async {
      final d = await p.getDetail('${srv.base}/meta/a1');
      expect(d.title, 'Alpha');
      expect(d.description, 'An alpha thing');
      expect(d.genres, ['Drama']);
      expect(d.year, '2020');
      expect(d.cover, '${srv.base}/i/a1.jpg');
    });

    test('single-item source exposes one playable episode', () async {
      final eps = await p.getEpisodes('${srv.base}/meta/a1');
      expect(eps.single.number, 1);
    });

    test('stream template picks the non-derivative mp4 and encodes it',
        () async {
      final srcs = await p.getVideoSources('a1|1');
      expect(srcs.single.url, '${srv.base}/dl/a1/Alpha%20film.mp4');
      expect(srcs.single.url, isNot(contains('.ia.mp4')));
    });
  });

  group('HTML mode', () {
    late _Server srv;
    late UniversalProvider p;

    setUp(() async {
      srv = await _Server.start();
      const home = '''
<html><body>
  <div class="card"><a href="/watch/one"><img src="/p/one.jpg"></a>
    <span class="title">One</span></div>
  <div class="card"><a href="/watch/two"><img src="/p/two.jpg"></a>
    <span class="title">Two</span></div>
</body></html>''';
      srv.on('/', (_) => home);
      srv.on('/search', (_) => home);
      const watch = '''
<html><head>
  <meta property="og:image" content="/p/one.jpg">
</head><body>
  <h1 class="name">One Show</h1>
  <div class="synopsis">A show.</div>
  <a href="/genre/action">Action</a>
  <div class="ep"><a href="/watch/one/ep-1">Episode 1</a></div>
  <div class="ep"><a href="/watch/one/ep-2">Episode 2</a></div>
  <iframe src="/e/one"></iframe>
</body></html>''';
      srv.on('/watch/one', (_) => watch);
      srv.on('/watch/one/ep-1', (_) => watch);
      // The iframe is followed one level — its own page must carry the file.
      srv.on('/e/one', (_) =>
          '<html><body><video src="/v/one.mp4"></video></body></html>');
      p = UniversalProvider(config: htmlConfig(srv.base), fetch: _http);
    });

    tearDown(() => srv.close());

    test('catalog rows resolve relative hrefs and posters', () async {
      final home = await p.getHome();
      final items = home!.single.items;
      expect(items.map((i) => i.title), ['One', 'Two']);
      expect(items.first.url, '${srv.base}/watch/one');
      expect(items.first.cover, '${srv.base}/p/one.jpg');
    });

    test('detail reads text and attribute selectors', () async {
      final d = await p.getDetail('${srv.base}/watch/one');
      expect(d.title, 'One Show');
      expect(d.description, 'A show.');
      expect(d.genres, ['Action']);
      expect(d.cover, '${srv.base}/p/one.jpg');
    });

    test('episodes list maps anchors', () async {
      final eps = await p.getEpisodes('${srv.base}/watch/one');
      expect(eps.length, 2);
      expect(eps.first.url, '${srv.base}/watch/one/ep-1');
    });

    test('stream rule follows the iframe one level to the file', () async {
      final srcs = await p.getVideoSources('${srv.base}/watch/one/ep-1');
      expect(srcs.map((s) => s.url), contains('${srv.base}/v/one.mp4'));
    });
  });

  group('bundled pack', () {
    test('parses, and every entry builds a provider', () {
      final body = File('assets/universal/manifest.json').readAsStringSync();
      final configs = UniversalManager.parseRepoBody(body);
      expect(configs, isNotEmpty);
      for (final c in configs) {
        final p = UniversalProvider(config: c, fetch: _http);
        expect(p.sourceId, 'us:${c.id}');
        expect(p.displayName, isNotEmpty);
      }
    });

    test('archive.org config declares the fields the engine resolves on', () {
      final body = File('assets/universal/manifest.json').readAsStringSync();
      final c = UniversalManager.parseRepoBody(body)
          .firstWhere((c) => c.id == 'archiveorg');
      expect(c.api, isNotNull);
      expect(c.api!.streamsUrlTemplate, contains('<ext>'));
      expect(c.api!.streamsExtensions, 'mp4');
      expect(c.api!.posterTemplate, contains('{id}'));
    });
  });
}
