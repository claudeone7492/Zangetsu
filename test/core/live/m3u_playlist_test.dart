import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/live/m3u_playlist.dart';

void main() {
  group('M3uPlaylist.parse', () {
    test('reads EXTINF attributes and the following URL', () {
      const text = '''
#EXTM3U
#EXTINF:-1 tvg-id="bbc1" tvg-name="BBC One" tvg-logo="https://x/bbc.png" group-title="News",BBC One
https://stream.example/bbc.m3u8
#EXTINF:-1 group-title="Sports",Sky Sports
https://stream.example/sky.m3u8
''';
      final channels = M3uPlaylist.parse(text);
      expect(channels, hasLength(2));
      expect(channels[0].name, 'BBC One');
      expect(channels[0].url, 'https://stream.example/bbc.m3u8');
      expect(channels[0].tvgId, 'bbc1');
      expect(channels[0].tvgName, 'BBC One');
      expect(channels[0].logo, 'https://x/bbc.png');
      expect(channels[0].group, 'News');
      expect(channels[1].group, 'Sports');
    });

    test('a comma inside a quoted attribute does not truncate the name', () {
      const text =
          '#EXTINF:-1 group-title="News, World",BBC World\n'
          'https://stream.example/world.m3u8\n';
      final channels = M3uPlaylist.parse(text);
      expect(channels.single.name, 'BBC World');
      expect(channels.single.group, 'News, World');
    });

    test('EXTGRP applies to the next channel', () {
      const text = '''
#EXTM3U
#EXTGRP:Movies
#EXTINF:-1,Film One
https://stream.example/one.m3u8
''';
      expect(M3uPlaylist.parse(text).single.group, 'Movies');
    });

    test('dedupes by URL', () {
      const text = '''
#EXTINF:-1,One
https://stream.example/a.m3u8
#EXTINF:-1,One again
https://stream.example/a.m3u8
''';
      expect(M3uPlaylist.parse(text), hasLength(1));
    });

    test('skips comments, options and non-http URLs', () {
      const text = '''
#EXTM3U
#EXTVLCOPT:http-user-agent=foo
#EXTINF:-1,Local
file:///tmp/local.ts
#EXTINF:-1,Remote
https://stream.example/ok.m3u8
''';
      final channels = M3uPlaylist.parse(text);
      expect(channels.single.name, 'Remote');
    });

    test('handles CRLF and a missing name by using the URL', () {
      const text =
          '#EXTM3U\r\n#EXTINF:-1\r\nhttps://stream.example/no-name.m3u8\r\n';
      final channel = M3uPlaylist.parse(text).single;
      expect(channel.name, 'no-name');
    });
  });

  group('M3uPlaylist.parseJson', () {
    test('reads a list of channels', () {
      const text = '''
[
  {"name":"One","url":"https://stream.example/1.m3u8","logo":"https://x/1.png","group":"News"},
  {"title":"Two","link":"https://stream.example/2.m3u8","category":"Sports"}
]
''';
      final channels = M3uPlaylist.parseJson(text);
      expect(channels, hasLength(2));
      expect(channels[0].name, 'One');
      expect(channels[1].name, 'Two');
      expect(channels[1].group, 'Sports');
    });

    test('reads a channels wrapper', () {
      const text =
          '{"channels":[{"name":"One","url":"https://stream.example/1.m3u8"}]}';
      expect(M3uPlaylist.parseJson(text), hasLength(1));
    });

    test('malformed JSON yields no channels', () {
      expect(M3uPlaylist.parseJson('{oops'), isEmpty);
    });
  });

  test('parseAuto picks JSON by its first character', () {
    const json = '[{"name":"One","url":"https://stream.example/1.m3u8"}]';
    const m3u = '#EXTM3U\n#EXTINF:-1,Two\nhttps://stream.example/2.m3u8\n';
    expect(M3uPlaylist.parseAuto(json).single.name, 'One');
    expect(M3uPlaylist.parseAuto(m3u).single.name, 'Two');
  });
}
