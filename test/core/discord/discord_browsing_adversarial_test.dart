import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/discord/discord_gateway.dart';
import 'package:watch_app/core/discord/discord_presence.dart';
import 'package:watch_app/core/discord/discord_rpc.dart';
import 'package:watch_app/core/privacy/incognito_mode.dart';

/// Records every presence push the resolver would have sent over the gateway,
/// so the adversarial ordering rules can be checked without a live socket.
class _RecordingGateway extends DiscordGateway {
  _RecordingGateway(this.updates, this.clears, this.closes)
      : super('Bearer test');

  final List<DiscordActivity> updates;
  final List<void> clears;
  final List<void> closes;

  @override
  void connect() {}

  @override
  void setPresence(DiscordActivity? activity, {String status = 'online'}) {
    if (activity == null) {
      clears.add(null);
    } else {
      updates.add(activity);
    }
  }

  @override
  Future<void> clearThenClose() async {
    clears.add(null);
    closes.add(null);
  }

  @override
  Future<void> close() async => closes.add(null);

  @override
  void updateToken(String token) {}
}

/// Answers the external-assets endpoint so poster URLs map to a stable
/// `mp:...` key instead of hitting the network.
class _AssetAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '[{"external_asset_path": "ext/poster"}]',
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final updates = <DiscordActivity>[];
  final clears = <void>[];
  final closes = <void>[];
  late Directory directory;
  late DiscordRpc rpc;
  late Dio dio;

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 450));

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('discord_adversarial');
    Hive.init(directory.path);
    await Hive.openBox(DiscordRpc.boxName);
  });

  setUp(() async {
    updates.clear();
    clears.clear();
    closes.clear();
    dio = Dio()..httpClientAdapter = _AssetAdapter();
    rpc = DiscordRpc(dio)
      ..gatewayFactory = (token, {onAuthFailure}) =>
          _RecordingGateway(updates, clears, closes);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    IncognitoMode.notifier.value = false;
    await Hive.box(DiscordRpc.boxName).putAll({
      'accessToken': 'fake-test-token',
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 1))
          .millisecondsSinceEpoch,
      'browsingTitle': true,
      'largeImage': 'poster',
      'showPaused': true,
    });
    await rpc.getValidAccessToken();
    await rpc.setEnabled(true);
    await settle();
    updates.clear();
    clears.clear();
    closes.clear();
  });

  tearDown(() async {
    await rpc.setEnabled(false);
    await settle();
    updates.clear();
    clears.clear();
    closes.clear();
    IncognitoMode.notifier.value = false;
    debugDefaultTargetPlatformOverride = null;
    dio.close();
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('browsing sends title and artwork on ${platform.name}', () async {
      debugDefaultTargetPlatformOverride = platform;
      await rpc.setBrowsing(
        title: 'Title A',
        posterUrl: 'https://example.com/a.jpg',
      );
      await settle();
      final activity = updates.single;
      expect(activity.details, 'Looking at Title A');
      expect(activity.type, 0);
      expect(activity.largeImage, 'mp:ext/poster');
    });
  }

  test(
    'hidden browsing title and missing poster use generic activity',
    () async {
      await rpc.setPresencePref('browsingTitle', false);
      await rpc.setBrowsing(title: 'Private title');
      await settle();
      expect(updates.single.details, 'Browsing');
    },
  );

  test('rapid title changes publish only the latest title', () async {
    await Future.wait([
      rpc.setBrowsing(title: 'Old', posterUrl: 'https://example.com/a.jpg'),
      rpc.setBrowsing(title: 'Latest', posterUrl: 'https://example.com/b.jpg'),
    ]);
    await settle();
    expect(updates, hasLength(1));
    expect(updates.single.details, 'Looking at Latest');
  });

  test('watching replaces pending browsing', () async {
    await Future.wait([
      rpc.setBrowsing(
        title: 'Old detail',
        posterUrl: 'https://example.com/a.jpg',
      ),
      rpc.setWatching(
        title: 'Playing now',
        duration: const Duration(minutes: 20),
      ),
    ]);
    await settle();
    expect(updates.single.type, 3);
    expect(updates.single.name, 'Playing now');
  });

  test('clear cannot be undone by unfinished browsing work', () async {
    final pending = rpc.setBrowsing(title: 'Already left');
    rpc.clear();
    await pending;
    await settle();
    expect(updates, isEmpty);
  });

  test('clear cannot be undone by unfinished watching work', () async {
    final pending = rpc.setWatching(title: 'Already stopped');
    rpc.clear();
    await pending;
    await settle();
    expect(updates, isEmpty);
  });

  test('scheduled exit clear discards older unfinished browsing', () async {
    final pending = rpc.setBrowsing(title: 'Already left');
    rpc.clear(delay: const Duration(milliseconds: 50));
    await pending;
    await settle();
    expect(updates, isEmpty);
  });

  test('new playback still cancels a scheduled exit clear', () async {
    rpc.clear(delay: const Duration(milliseconds: 50));
    await rpc.setWatching(title: 'Next episode');
    await settle();
    expect(updates.single.name, 'Next episode');
    expect(clears, isEmpty);
  });

  test('older slow browsing cannot replace newer watching', () async {
    await Future.wait([
      rpc.setBrowsing(title: 'Old detail'),
      rpc.setWatching(
        title: 'Playing now',
        posterUrl: 'https://example.com/a.jpg',
      ),
    ]);
    await settle();
    expect(updates.single.type, 3);
    expect(updates.single.name, 'Playing now');
  });

  test('disabled and incognito browsing never publish', () async {
    IncognitoMode.notifier.value = true;
    await rpc.setBrowsing(title: 'Hidden');
    await settle();
    expect(updates, isEmpty);
    IncognitoMode.notifier.value = false;
    await rpc.setEnabled(false);
    await settle();
    updates.clear();
    await rpc.setBrowsing(title: 'Disabled');
    await settle();
    expect(updates, isEmpty);
  });

  test('disable during browsing does not replay it when re-enabled', () async {
    final pending = rpc.setBrowsing(title: 'Before disable');
    await rpc.setEnabled(false);
    await pending;
    await settle();
    updates.clear();
    await rpc.setEnabled(true);
    await settle();
    expect(updates, isEmpty);
  });

  test('native-player lifecycle pause keeps watching activity', () async {
    await rpc.setWatching(title: 'Still playing');
    await settle();
    updates.clear();
    clears.clear();
    rpc.onPaused();
    await settle();
    expect(clears, isEmpty);
    expect(closes, isEmpty);
  });
}
