import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/framex_subtitle_source.dart';
import 'package:watch_app/core/playback/online_subtitle_search.dart';
import 'package:watch_app/core/playback/subtitle_search_service.dart';

/// Stands in for OpenSubtitles: returns whatever it was given and records that
/// it was asked, so a test can assert a keyless install never calls it.
class _FakeOpenSubtitles extends SubtitleSearchService {
  _FakeOpenSubtitles({this.keyed = true, this.results = const [], this.throws});

  bool keyed;
  List<SubtitleSearchResult> results;
  SubtitleSearchException? throws;
  int searchCalls = 0;

  @override
  bool get hasApiKey => keyed;

  @override
  Future<List<SubtitleSearchResult>> search(
    String query, {
    String language = 'en',
    String? imdbId,
    int? tmdbId,
  }) async {
    searchCalls++;
    if (throws != null) throw throws!;
    return results;
  }

  @override
  Future<String> download(SubtitleSearchResult result) async =>
      '/tmp/${result.id}.srt';
}

/// Stands in for FrameX: answers with a fixed list regardless of id.
class _FakeFrameX extends FrameXSubtitleSource {
  _FakeFrameX({this.subs = const []});

  List<FrameXSubtitle> subs;
  int lookups = 0;

  @override
  Future<List<FrameXSubtitle>> subtitlesFor(
    String id, {
    String type = 'movie',
    int? season,
    int? episode,
  }) async {
    lookups++;
    return subs;
  }

  @override
  Future<String?> downloadToFile(String url, {String? name}) async =>
      '/tmp/framex.vtt';
}

SubtitleSearchResult _openSubResult(String id, String name, String lang) =>
    SubtitleSearchResult(id: id, name: name, language: lang, fileId: 1);

void main() {
  group('OnlineSubtitleSearch.search', () {
    test('merges FrameX and OpenSubtitles rows, FrameX first', () async {
      final openSub = _FakeOpenSubtitles(
        results: [_openSubResult('1', 'OpenSub release', 'en')],
      );
      final framex = _FakeFrameX(
        subs: const [
          FrameXSubtitle(
            url: 'https://x/a.vtt',
            label: 'WEB-DL',
            language: 'English',
          ),
        ],
      );
      final search = OnlineSubtitleSearch(
        openSubtitles: openSub,
        framex: framex,
      );

      final hits = await search.search(
        'The Matrix',
        tmdbId: 603,
        imdbId: 'tt0133093',
      );

      expect(hits.length, 2);
      expect(hits.first.source, 'FrameX');
      expect(hits.first.label, 'WEB-DL');
      expect(hits.last.source, 'OpenSubtitles');
      expect(hits.last.label, 'OpenSub release');
    });

    test('skips OpenSubtitles when no key is set', () async {
      final openSub = _FakeOpenSubtitles(keyed: false);
      final search = OnlineSubtitleSearch(
        openSubtitles: openSub,
        framex: _FakeFrameX(
          subs: const [FrameXSubtitle(url: 'https://x/a.vtt', language: 'en')],
        ),
      );

      final hits = await search.search('Dune', tmdbId: 438631);
      expect(hits, hasLength(1));
      expect(openSub.searchCalls, 0);
    });

    test('skips FrameX when there is no TMDB id', () async {
      final framex = _FakeFrameX();
      final search = OnlineSubtitleSearch(
        openSubtitles: _FakeOpenSubtitles(
          results: [_openSubResult('1', 'Only source', 'en')],
        ),
        framex: framex,
      );

      final hits = await search.search('Some Anime');
      expect(hits, hasLength(1));
      expect(hits.single.source, 'OpenSubtitles');
      expect(framex.lookups, 0);
    });

    test('one provider failing does not sink the other', () async {
      final search = OnlineSubtitleSearch(
        openSubtitles: _FakeOpenSubtitles(
          throws: const SubtitleSearchException('quota reached'),
        ),
        framex: _FakeFrameX(
          subs: const [FrameXSubtitle(url: 'https://x/a.vtt', language: 'en')],
        ),
      );

      String? error;
      final hits = await search.search(
        'Dune',
        tmdbId: 438631,
        onError: (m) => error = m,
      );

      expect(hits, hasLength(1));
      expect(hits.single.source, 'FrameX');
      // FrameX answered, so OpenSubtitles' failure is not worth surfacing.
      expect(error, isNull);
    });

    test('reports the failure when the only keyed provider fails', () async {
      final search = OnlineSubtitleSearch(
        openSubtitles: _FakeOpenSubtitles(
          throws: const SubtitleSearchException('quota reached'),
        ),
        framex: _FakeFrameX(),
      );

      String? error;
      final hits = await search.search('Dune', onError: (m) => error = m);

      expect(hits, isEmpty);
      expect(error, 'quota reached');
    });

    test('an empty query does no work', () async {
      final openSub = _FakeOpenSubtitles();
      final framex = _FakeFrameX();
      final search = OnlineSubtitleSearch(
        openSubtitles: openSub,
        framex: framex,
      );
      expect(await search.search('   ', tmdbId: 1), isEmpty);
      expect(openSub.searchCalls, 0);
      expect(framex.lookups, 0);
    });
  });

  group('OnlineSubtitleSearch.canUseFrameX', () {
    test('needs a TMDB id', () {
      expect(OnlineSubtitleSearch.canUseFrameX(603), isTrue);
      expect(OnlineSubtitleSearch.canUseFrameX(null), isFalse);
    });
  });
}
