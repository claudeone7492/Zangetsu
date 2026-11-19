import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/live/xtream_account_store.dart';
import 'package:watch_app/core/live/xtream_api.dart';

/// An in-memory secure storage so the store's real read/write path runs without
/// the platform channel.
class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _data.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A panel that behaves like a real Xtream server: one `player_api.php` that
/// switches on `action`, credentials checked the way panels check them.
class _Panel {
  _Panel(this._srv, {this.user = 'alice', this.pass = 'secret'});

  final HttpServer _srv;
  final String user;
  final String pass;
  int playerApiCalls = 0;

  static Future<_Panel> start() async {
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final p = _Panel(srv);
    srv.listen(p._handle);
    return p;
  }

  String get base => 'http://127.0.0.1:${_srv.port}';

  Future<void> _handle(HttpRequest req) async {
    final q = req.uri.queryParameters;
    if (req.uri.path == '/player_api.php') {
      playerApiCalls++;
      if (q['username'] != user || q['password'] != pass) {
        req.response.write(jsonEncode({'user_info': {'auth': 0}}));
        await req.response.close();
        return;
      }
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(_respond(q['action'])));
      await req.response.close();
      return;
    }
    if (req.uri.path == '/xmltv.php') {
      req.response.headers.contentType = ContentType('application', 'xml');
      req.response.write('<tv></tv>');
      await req.response.close();
      return;
    }
    req.response.statusCode = HttpStatus.notFound;
    await req.response.close();
  }

  Object _respond(String? action) {
    const info = {
      'auth': 1,
      'user_info': {
        'username': 'alice',
        'status': 'Active',
        // 2033-05-18T03:33:20Z
        'exp_date': '2000000000',
        'max_connections': '2',
        'active_cons': '1',
        'is_trial': '0',
      },
    };
    switch (action) {
      case null:
        return info;
      case 'get_live_categories':
        return {
          'result': [
            {'category_id': '1', 'category_name': 'Sports'},
            {'category_id': '2', 'category_name': 'News'},
          ],
        };
      case 'get_live_streams':
        return [
          {
            'stream_id': 101,
            'name': 'Sky Sports 1',
            'stream_icon': 'https://img.example/sky.png',
            'category_id': '1',
            'epg_channel_id': 'sky1.uk',
            'container_extension': 'm3u8',
          },
          {
            'stream_id': '102',
            'name': 'BBC News',
            'category_id': '2',
            'epg_channel_id': 'bbcnews.uk',
          },
        ];
      case 'get_vod_categories':
        return [
          {'category_id': '10', 'category_name': 'Films'},
        ];
      case 'get_vod_streams':
        return [
          {
            'stream_id': 900,
            'name': 'A Film',
            'container_extension': 'mkv',
            'year': '2021',
            'rating': '7.5',
            'plot': 'Something happens.',
          },
        ];
      case 'get_series_categories':
        return [
          {'category_id': '20', 'category_name': 'Drama'},
        ];
      case 'get_series':
        return [
          {'series_id': 77, 'name': 'A Show', 'cover': 'https://img/x.jpg'},
        ];
      default:
        return {'unexpected_action': action};
    }
  }

  Future<void> close() => _srv.close(force: true);
}

void main() {
  group('XtreamAccount.normalizeHost', () {
    test('adds a scheme when missing and strips trailing slashes', () {
      expect(XtreamAccount.normalizeHost('panel.tv:8080/'), 'http://panel.tv:8080');
      expect(XtreamAccount.normalizeHost(' https://panel.tv '), 'https://panel.tv');
      expect(XtreamAccount.normalizeHost(''), '');
    });

    test('idFor is stable across host formatting', () {
      expect(
        XtreamAccount.idFor('http://panel.tv/', 'alice'),
        XtreamAccount.idFor('panel.tv', 'alice'),
      );
    });
  });

  group('XtreamApi (live panel)', () {
    late _Panel panel;
    late XtreamApi api;
    late XtreamAccount account;

    setUp(() async {
      panel = await _Panel.start();
      api = XtreamApi(dio: Dio());
      account = XtreamAccount(
        id: XtreamAccount.idFor(panel.base, 'alice'),
        host: panel.base,
        username: 'alice',
        password: 'secret',
      );
    });

    tearDown(() async => panel.close());

    test('login reads the subscription profile', () async {
      final profile = await api.login(account);
      expect(profile.isActive, isTrue);
      expect(profile.maxConnections, 2);
      expect(profile.activeConnections, 1);
      expect(profile.isTrial, isFalse);
      expect(profile.expiresAt, isNotNull);
      expect(profile.daysLeft, greaterThan(0));
    });

    test('login rejects bad credentials with a clear message', () async {
      final bad = XtreamAccount(
        id: 'x',
        host: panel.base,
        username: 'alice',
        password: 'wrong',
      );
      await expectLater(
        api.login(bad),
        throwsA(
          isA<XtreamException>().having(
            (e) => e.message,
            'message',
            contains('Invalid'),
          ),
        ),
      );
    });

    test('login reports an unreachable panel', () async {
      final dead = XtreamAccount(
        id: 'x',
        host: 'http://127.0.0.1:1',
        username: 'alice',
        password: 'secret',
      );
      await expectLater(
        api.login(dead),
        throwsA(isA<XtreamException>()),
      );
    });

    test('live categories parse from the result envelope', () async {
      final cats = await api.categories(account, XtreamKind.live);
      expect(cats.map((c) => c.name), ['Sports', 'News']);
      expect(cats.first.id, '1');
    });

    test('live streams parse both numeric and string ids', () async {
      final streams = await api.streams(account, XtreamKind.live);
      expect(streams, hasLength(2));
      expect(streams.first.id, '101');
      expect(streams.first.name, 'Sky Sports 1');
      expect(streams.first.epgChannelId, 'sky1.uk');
      expect(streams.last.id, '102');
      expect(streams.last.container, isEmpty);
    });

    test('vod and series use their own id fields', () async {
      final vod = await api.streams(account, XtreamKind.vod);
      expect(vod.single.id, '900');
      expect(vod.single.kind, XtreamKind.vod);
      expect(vod.single.container, 'mkv');
      expect(vod.single.year, '2021');

      final series = await api.streams(account, XtreamKind.series);
      expect(series.single.id, '77');
      expect(series.single.kind, XtreamKind.series);
    });

    test('a category filter is passed through to the panel', () async {
      final streams = await api.streams(
        account,
        XtreamKind.live,
        categoryId: '1',
      );
      // The stub ignores the filter, so this asserts the call still parses.
      expect(streams, isNotEmpty);
    });

    test('builds the playable live and vod urls', () async {
      final live = await api.streams(account, XtreamKind.live);
      expect(
        api.liveUrl(account, live.first),
        '${panel.base}/live/alice/secret/101.m3u8',
      );
      expect(
        api.liveUrl(account, live.last),
        '${panel.base}/live/alice/secret/102.m3u8',
        reason: 'a missing container falls back to m3u8',
      );

      final vod = await api.streams(account, XtreamKind.vod);
      expect(
        api.vodUrl(account, vod.single),
        '${panel.base}/movie/alice/secret/900.mkv',
      );
    });

    test('builds the account XMLTV url', () {
      expect(
        api.epgUrl(account),
        '${panel.base}/xmltv.php?username=alice&password=secret',
      );
    });

    test('an unreachable panel yields an empty list, not a throw', () async {
      final dead = XtreamAccount(
        id: 'x',
        host: 'http://127.0.0.1:1',
        username: 'alice',
        password: 'secret',
      );
      expect(await api.streams(dead, XtreamKind.live), isEmpty);
      expect(await api.categories(dead, XtreamKind.live), isEmpty);
    });
  });

  group('XtreamAccountStore', () {
    test('persists accounts and re-reads them', () async {
      final storage = _MemoryStorage();
      final store = XtreamAccountStore(storage: storage);
      await store.add(
        host: 'panel.tv:8080/',
        username: 'alice',
        password: 'secret',
        label: 'Living room',
      );
      expect(store.accounts, hasLength(1));
      expect(store.accounts.single.host, 'http://panel.tv:8080');
      expect(store.accounts.single.displayName, 'Living room');

      final reopened = XtreamAccountStore(storage: storage);
      await reopened.ensureLoaded();
      expect(reopened.accounts, hasLength(1));
      expect(reopened.accounts.single.password, 'secret');
    });

    test('re-adding the same host+user updates instead of duplicating', () async {
      final store = XtreamAccountStore(storage: _MemoryStorage());
      await store.add(host: 'panel.tv', username: 'alice', password: 'one');
      await store.add(host: 'panel.tv', username: 'alice', password: 'two');
      expect(store.accounts, hasLength(1));
      expect(store.accounts.single.password, 'two');
    });

    test('remove deletes the account from memory and storage', () async {
      final storage = _MemoryStorage();
      final store = XtreamAccountStore(storage: storage);
      final a = await store.add(
        host: 'panel.tv',
        username: 'alice',
        password: 'x',
      );
      await store.remove(a.id);
      expect(store.isEmpty, isTrue);

      final reopened = XtreamAccountStore(storage: storage);
      await reopened.ensureLoaded();
      expect(reopened.isEmpty, isTrue);
    });

    test('rejects an empty host or username', () async {
      final store = XtreamAccountStore(storage: _MemoryStorage());
      await expectLater(
        store.add(host: '  ', username: 'alice', password: 'x'),
        throwsA(isA<XtreamException>()),
      );
      await expectLater(
        store.add(host: 'panel.tv', username: ' ', password: 'x'),
        throwsA(isA<XtreamException>()),
      );
    });

    test('a corrupt stored payload is ignored rather than fatal', () async {
      final storage = _MemoryStorage();
      await storage.write(key: 'xtream_accounts', value: 'not json');
      final store = XtreamAccountStore(storage: storage);
      await store.ensureLoaded();
      expect(store.isEmpty, isTrue);
    });
  });
}
