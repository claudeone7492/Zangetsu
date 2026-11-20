import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/hikari/hikari_mapping.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/video_source.dart';

/// The wire keys asserted here are written by `HikariJson.kt`. These tests are
/// the other half of that contract: a rename on either side fails here rather
/// than silently dropping a field at runtime.
void main() {
  group('hikariMediaItem', () {
    test('maps a full media row', () {
      final item = hikariMediaItem(
        {
          'id': 'tt123',
          'title': '  Dune  ',
          'type': 'movie',
          'posterUrl': 'https://img/p.jpg',
          'backdropUrl': 'https://img/b.jpg',
          'year': 2021,
          'genres': ['Sci-Fi', 'Adventure'],
        },
        sourceId: 'hiki:yts',
        providerName: 'YTS',
      );

      expect(item.title, 'Dune', reason: 'surrounding whitespace is trimmed');
      expect(item.cover, 'https://img/p.jpg');
      expect(item.banner, 'https://img/b.jpg');
      expect(item.year, 2021);
      expect(item.genres, ['Sci-Fi', 'Adventure']);
      expect(item.sourceId, 'hiki:yts');
      expect(item.type, ProviderType.movie);
    });

    test('treats a blank title as Untitled rather than an empty card', () {
      final item = hikariMediaItem(
        {'id': 'x', 'title': '   '},
        sourceId: 'hiki:a',
        providerName: 'A',
      );
      expect(item.title, 'Untitled');
    });

    test('series and anime map to the anime provider type', () {
      for (final type in ['series', 'tv', 'anime', 'SERIES']) {
        final item = hikariMediaItem(
          {'id': 'x', 'title': 'T', 'type': type},
          sourceId: 'hiki:a',
          providerName: 'A',
        );
        expect(item.type, ProviderType.anime, reason: 'type=$type');
      }
    });

    test('an unknown or missing type falls back to movie', () {
      for (final type in ['unknown', '', 'banana']) {
        final item = hikariMediaItem(
          {'id': 'x', 'title': 'T', 'type': type},
          sourceId: 'hiki:a',
          providerName: 'A',
        );
        expect(item.type, ProviderType.movie, reason: 'type=$type');
      }
      final missing = hikariMediaItem(
        {'id': 'x', 'title': 'T'},
        sourceId: 'hiki:a',
        providerName: 'A',
      );
      expect(missing.type, ProviderType.movie);
    });

    test('blank artwork and year of the wrong type become null', () {
      final item = hikariMediaItem(
        {
          'id': 'x',
          'title': 'T',
          'posterUrl': '   ',
          'backdropUrl': '',
          'year': '2021',
        },
        sourceId: 'hiki:a',
        providerName: 'A',
      );
      expect(item.cover, isNull);
      expect(item.banner, isNull);
      expect(item.year, isNull, reason: 'a String year is not coerced');
    });

    test('non-string genre entries are dropped, not rendered as null', () {
      final item = hikariMediaItem(
        {
          'id': 'x',
          'title': 'T',
          'genres': ['Action', 42, null, '  ', 'Drama'],
        },
        sourceId: 'hiki:a',
        providerName: 'A',
      );
      expect(item.genres, ['Action', 'Drama']);
    });

    test('ids from different extensions never collide', () {
      final a = hikariMediaItem(
        {'id': 'same', 'title': 'T'},
        sourceId: 'hiki:one',
        providerName: 'One',
      );
      final b = hikariMediaItem(
        {'id': 'same', 'title': 'T'},
        sourceId: 'hiki:two',
        providerName: 'Two',
      );
      expect(a.id, isNot(b.id));
    });
  });

  group('detail url round-trip', () {
    test('carries the whole media object, not just the id', () {
      final media = <String, dynamic>{
        'id': 'tt1',
        'title': 'Dune',
        'type': 'movie',
        'posterUrl': 'https://img/p.jpg',
      };
      final url = hikariDetailUrl(media);
      final back = hikariMediaFromDetailUrl(url);

      expect(back, isNotNull);
      expect(back!['id'], 'tt1');
      expect(back['title'], 'Dune');
      expect(back['posterUrl'], 'https://img/p.jpg');
    });

    test('produces a url with no padding or unsafe characters', () {
      final url = hikariDetailUrl({'id': 'a b/c+d?e', 'title': 'x'});
      expect(url, startsWith(hikariIdPrefix));
      final payload = url.substring(hikariIdPrefix.length);
      expect(payload, isNot(contains('=')));
      expect(payload, isNot(contains('/')));
      expect(payload, isNot(contains('+')));
      expect(payload, isNot(contains('?')));
    });

    test('rejects a url that is not ours', () {
      expect(hikariMediaFromDetailUrl('https://example.com/x'), isNull);
      expect(hikariMediaFromDetailUrl('hiki:!!!not-base64!!!'), isNull);
    });
  });

  group('episode url round-trip', () {
    test('preserves both media and episode', () {
      final media = <String, dynamic>{'id': 'm1', 'title': 'Show'};
      final episode = <String, dynamic>{'id': 'e1', 'number': 3};
      final packed = hikariEpisodeFromUrl(hikariEpisodeUrl(media, episode));

      expect(packed, isNotNull);
      expect(packed!.media['id'], 'm1');
      expect(packed.episode!['id'], 'e1');
      expect(packed.episode!['number'], 3);
    });

    test('a movie packs a null episode and reads back as null', () {
      final packed = hikariEpisodeFromUrl(
        hikariEpisodeUrl({'id': 'm1', 'title': 'Film'}, null),
      );
      expect(packed, isNotNull);
      expect(packed!.episode, isNull);
      expect(packed.media['id'], 'm1');
    });
  });

  group('hikariEpisode', () {
    test('maps a named episode', () {
      final ep = hikariEpisode(
        {'id': 'm1', 'title': 'Show'},
        {'id': 'e2', 'number': 2, 'name': 'The Door', 'season': 2},
        sourceId: 'hiki:a',
      );
      expect(ep.title, 'The Door');
      expect(ep.number, 2.0);
      expect(ep.season, 2);
    });

    test('falls back to a numbered title when the name is blank', () {
      final ep = hikariEpisode(
        {'id': 'm1', 'title': 'Show'},
        {'id': 'e4', 'number': 4, 'name': '  '},
        sourceId: 'hiki:a',
      );
      expect(ep.title, 'Episode 4');
    });

    test('a movie with no episode gets one tappable Full entry', () {
      final ep = hikariEpisode(
        {'id': 'm1', 'title': 'Film'},
        null,
        sourceId: 'hiki:a',
      );
      expect(ep.title, 'Full');
      expect(ep.number, 1.0);
      expect(ep.url, startsWith(hikariIdPrefix));
    });

    test('episode urls differ per episode', () {
      final media = {'id': 'm1', 'title': 'Show'};
      final one = hikariEpisode(media, {'id': 'e1', 'number': 1}, sourceId: 'a');
      final two = hikariEpisode(media, {'id': 'e2', 'number': 2}, sourceId: 'a');
      expect(one.url, isNot(two.url));
      expect(one.id, isNot(two.id));
    });
  });

  group('hikariVideoSource', () {
    test('an m3u8 stream becomes an HLS source with headers', () {
      final src = hikariVideoSource({
        'name': 'Server 1',
        'url': 'https://cdn/x.m3u8',
        'isM3u8': true,
        'headers': {'Referer': 'https://site/', 'User-Agent': 'UA'},
      });

      expect(src, isNotNull);
      expect(src!.url, 'https://cdn/x.m3u8');
      expect(src.label, 'Server 1');
      expect(src.container, SourceContainer.hls);
      expect(src.headers, {'Referer': 'https://site/', 'User-Agent': 'UA'});
    });

    test('a plain url becomes mp4 and omits empty headers', () {
      final src = hikariVideoSource({
        'name': 'Direct',
        'url': 'https://cdn/x.mp4',
        'headers': {'Referer': ''},
      });
      expect(src!.container, SourceContainer.mp4);
      expect(src.headers, isNull, reason: 'empty header map is not carried');
    });

    test('a torrent becomes a magnet carrying its trackers', () {
      final src = hikariVideoSource({
        'name': 'Torrent 1080p',
        'isTorrent': true,
        'infoHash': 'abc123',
        'fileIdx': 2,
        'trackers': ['udp://t1:80/announce', 'udp://t2:80/announce'],
      });

      expect(src, isNotNull);
      expect(src!.container, SourceContainer.torrent);
      expect(src.url, contains('xt=urn:btih:abc123'));
      expect(src.url, contains('tr=udp%3A%2F%2Ft1%3A80%2Fannounce'));
      expect(src.url, contains('tr=udp%3A%2F%2Ft2%3A80%2Fannounce'));
      expect(src.torrentFileIndex, 2);
    });

    test('a torrent with no info hash is unusable and dropped', () {
      expect(
        hikariVideoSource({'name': 'x', 'isTorrent': true}),
        isNull,
      );
    });

    test('a stream with neither url nor hash is dropped', () {
      expect(hikariVideoSource({'name': 'external', 'externalUrl': true}), isNull);
    });

    test('subtitles are carried and .vtt is marked', () {
      final src = hikariVideoSource({
        'name': 's',
        'url': 'https://cdn/x.mp4',
        'subtitles': [
          {'lang': 'en', 'url': 'https://cdn/en.vtt'},
          {'lang': '', 'url': 'https://cdn/und.srt'},
          {'lang': 'nourl'},
        ],
      });

      expect(src!.subtitles.length, 2, reason: 'the entry with no url is dropped');
      expect(src.subtitles[0].format, 'vtt');
      expect(src.subtitles[1].lang, 'und', reason: 'blank lang becomes und');
    });

    test('isMpd is not treated as HLS', () {
      final src = hikariVideoSource({
        'name': 'dash',
        'url': 'https://cdn/x.mpd',
        'isMpd': true,
      });
      expect(src!.container, isNot(SourceContainer.hls));
    });
  });

  group('hikariMediaDetail', () {
    test('carries description, year as a String, and episodes', () {
      final detail = hikariMediaDetail(
        {
          'id': 'tt1',
          'title': 'Dune',
          'type': 'movie',
          'overview': 'Spice.',
          'year': 2021,
          'genres': ['Sci-Fi'],
        },
        sourceId: 'hiki:a',
        episodes: [hikariEpisode({'id': 'tt1'}, null, sourceId: 'hiki:a')],
      );

      expect(detail.description, 'Spice.');
      expect(detail.year, '2021', reason: 'MediaDetail.year is a String');
      expect(detail.episodes, hasLength(1));
      expect(detail.sourceId, 'hiki:a');
    });
  });
}
