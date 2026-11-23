import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/live/live_playlist_store.dart';

void main() {
  late Directory dir;
  late LivePlaylistStore store;
  final dio = Dio();

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('live_playlists_test');
    Hive.init(dir.path);
    store = LivePlaylistStore();
    await store.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  tearDown(() async {
    for (final entry in store.entries) {
      await store.remove(entry.id);
    }
  });

  const m3u = '''
#EXTM3U
#EXTINF:-1 group-title="News",BBC One
https://stream.example/bbc.m3u8
#EXTINF:-1 group-title="News",BBC Two
https://stream.example/bbc2.m3u8
#EXTINF:-1 group-title="Sports",Sky Sports
https://stream.example/sky.m3u8
''';

  test('addText stores the playlist and groups its channels', () async {
    final entry = await store.addText(name: 'Test', text: m3u);
    expect(store.entries, hasLength(1));
    expect(entry.isInline, isTrue);

    final sections = await store.sections(dio);
    expect(sections.map((s) => s.title), ['News', 'Sports']);
    expect(sections.first.items, hasLength(2));
    expect(sections.first.items.first.title, 'BBC One');
    expect(sections.first.items.first.sourceId, LivePlaylistStore.sourceId);
    expect(sections.first.items.first.liveBadge, 'LIVE');
  });

  test('search matches channel names and groups', () async {
    await store.addText(name: 'Test', text: m3u);
    expect((await store.search('bbc', dio)), hasLength(2));
    final sports = (await store.search('sports', dio)).single;
    expect(sports.title, 'Sky Sports');
    // The group-title is carried on the hit, so Live TV can keep a search
    // scoped to the selected category pill.
    expect(sports.liveInfo, 'Sports');
    expect(await store.search('missing', dio), isEmpty);
  });

  test('remove drops the channels from the sections', () async {
    final entry = await store.addText(name: 'Test', text: m3u);
    await store.remove(entry.id);
    expect(store.entries, isEmpty);
    expect(await store.sections(dio), isEmpty);
  });

  test('an empty playlist is rejected', () async {
    await expectLater(
      store.addText(name: 'Empty', text: '#EXTM3U\n'),
      throwsA(isA<FormatException>()),
    );
  });

  test('a playlist with no name gets a fallback', () async {
    final entry = await store.addText(name: '   ', text: m3u);
    expect(entry.name, 'Playlist');
  });
}
