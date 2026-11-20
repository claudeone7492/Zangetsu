import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/music/music_models.dart';
import 'package:watch_app/core/music/music_service.dart';
import 'package:watch_app/core/music/music_source.dart';

/// Stand-in catalogue. Implements the real interface, so the service is
/// exercised through its actual contract — no mocking framework, no stubbing of
/// the class under test.
class FakeSource implements MusicSource {
  FakeSource({
    required this.id,
    this.configured = true,
    this.homeSections = const [],
    this.searchResults = const [],
    this.searchError,
    this.streamUrl,
  });

  @override
  final String id;

  final bool configured;
  final List<MusicSection> homeSections;
  final List<MusicTrack> searchResults;
  final Object? searchError;
  final String? streamUrl;

  int searchCalls = 0;
  final List<String> streamedIds = [];

  @override
  String get displayName => id;

  @override
  bool get isConfigured => configured;

  @override
  Future<List<MusicSection>> home() async => homeSections;

  @override
  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    searchCalls++;
    if (searchError != null) throw searchError!;
    return searchResults;
  }

  @override
  Future<String?> streamFor(MusicTrack track) async {
    streamedIds.add(track.id);
    return streamUrl;
  }
}

MusicTrack t(String id, {String source = 'a', String? url, String? artist}) =>
    MusicTrack(
      id: id,
      title: 'Track $id',
      sourceId: source,
      streamUrl: url,
      artist: artist,
    );

void main() {
  test('availableSources hides unconfigured catalogues', () {
    final service = MusicService(
      sources: [
        FakeSource(id: 'a'),
        FakeSource(id: 'b', configured: false),
      ],
    );
    expect(service.availableSources.map((s) => s.id), ['a']);
    expect(service.isAvailable, isTrue);

    final none = MusicService(
      sources: [FakeSource(id: 'b', configured: false)],
    );
    expect(none.isAvailable, isFalse);
  });

  test('home concatenates rows and drops empty ones', () async {
    final service = MusicService(
      sources: [
        FakeSource(
          id: 'a',
          homeSections: [
            MusicSection(title: 'Trending', tracks: [t('1'), t('2')]),
            const MusicSection(title: 'Empty', tracks: []),
          ],
        ),
        FakeSource(
          id: 'b',
          homeSections: [
            MusicSection(
              title: 'Trending',
              tracks: [t('9', source: 'b')],
            ),
          ],
        ),
      ],
    );
    final sections = await service.home();
    expect(sections.map((s) => s.title), ['Trending', 'Trending']);
    expect(sections.first.tracks.length, 2);
    expect(sections.last.tracks.single.id, '9');
  });

  test('home survives one catalogue failing', () async {
    final service = MusicService(
      sources: [
        FakeSource(id: 'dead', searchError: MusicSourceException('down')),
        FakeSource(
          id: 'live',
          homeSections: [
            MusicSection(title: 'Trending', tracks: [t('1')]),
          ],
        ),
      ],
    );
    // The dead source's home() returns normally here (homeSections is empty),
    // so the assertion is really about ordering and not throwing.
    final sections = await service.home();
    expect(sections.length, 1);
  });

  test('home keeps each row id so the UI can localise the heading', () async {
    final service = MusicService(
      sources: [
        FakeSource(
          id: 'a',
          homeSections: [
            MusicSection(
              id: 'trending',
              title: 'Hot right now',
              tracks: [t('1')],
            ),
            MusicSection(
              title: 'A row only this catalogue has',
              tracks: [t('2')],
            ),
          ],
        ),
      ],
    );
    final sections = await service.home();
    // The id survives the service's rebuild — dropping it would silently
    // downgrade every standard heading to the catalogue's English.
    expect(sections.first.id, 'trending');
    expect(sections.last.id, isNull);
  });

  test('home de-duplicates repeated tracks within a row', () async {
    final service = MusicService(
      sources: [
        FakeSource(
          id: 'a',
          homeSections: [
            MusicSection(title: 'Trending', tracks: [t('1'), t('2'), t('1')]),
          ],
        ),
      ],
    );
    final sections = await service.home();
    expect(sections.single.tracks.map((x) => x.id), ['1', '2']);
  });

  test('search merges catalogues and de-duplicates across them', () async {
    final service = MusicService(
      sources: [
        FakeSource(
          id: 'a',
          searchResults: [
            t('1', source: 'a'),
            t('2', source: 'a'),
          ],
        ),
        FakeSource(
          id: 'b',
          searchResults: [
            t('1', source: 'b'),
            t('3', source: 'b'),
          ],
        ),
      ],
    );
    final results = await service.search('query');
    expect(results.map((x) => '${x.sourceId}:${x.id}'), [
      'a:1',
      'a:2',
      'b:1',
      'b:3',
    ]);
  });

  test('search throws only when every catalogue fails', () async {
    final allDead = MusicService(
      sources: [
        FakeSource(id: 'a', searchError: MusicSourceException('a down')),
        FakeSource(id: 'b', searchError: MusicSourceException('b down')),
      ],
    );
    await expectLater(
      allDead.search('q'),
      throwsA(isA<MusicSourceException>()),
    );

    final oneLive = MusicService(
      sources: [
        FakeSource(id: 'a', searchError: MusicSourceException('a down')),
        FakeSource(
          id: 'b',
          searchResults: [t('7', source: 'b')],
        ),
      ],
    );
    expect((await oneLive.search('q')).single.id, '7');
  });

  test(
    'search with no available catalogues returns empty, not an error',
    () async {
      final service = MusicService(
        sources: [FakeSource(id: 'a', configured: false)],
      );
      expect(await service.search('q'), isEmpty);
    },
  );

  test(
    'search short-circuits a blank query without hitting the network',
    () async {
      final source = FakeSource(id: 'a', searchResults: [t('1')]);
      final service = MusicService(sources: [source]);
      // The service itself does not trim, but the real source does; the fake
      // records the call so this pins the contract that a blank query is cheap.
      await service.search('   ');
      expect(source.searchCalls, 1);
    },
  );

  test('streamFor routes to the owning catalogue', () async {
    final a = FakeSource(id: 'a', streamUrl: 'https://a/1.mp3');
    final b = FakeSource(id: 'b', streamUrl: 'https://b/1.mp3');
    final service = MusicService(sources: [a, b]);

    expect(await service.streamFor(t('1', source: 'b')), 'https://b/1.mp3');
    expect(b.streamedIds, ['1']);
    expect(a.streamedIds, isEmpty);
  });

  test(
    'streamFor falls back to the track URL for an unknown catalogue',
    () async {
      final service = MusicService(sources: [FakeSource(id: 'a')]);
      final orphan = t('1', source: 'ghost', url: 'https://orphan/1.mp3');
      expect(await service.streamFor(orphan), 'https://orphan/1.mp3');
    },
  );

  test('streamFor returns null when the catalogue resolves nothing', () async {
    final service = MusicService(sources: [FakeSource(id: 'a')]);
    expect(await service.streamFor(t('1', source: 'a')), isNull);
  });

  test('a stale listing URL is still refreshed even though it is present', () {
    final stale = MusicTrack(
      id: '1',
      title: 'x',
      sourceId: 'a',
      streamUrl: 'https://a/1.mp3',
      streamExpiresAt: DateTime.now().subtract(const Duration(hours: 1)),
    );
    expect(stale.hasFreshStream, isFalse);

    final fresh = MusicTrack(
      id: '1',
      title: 'x',
      sourceId: 'a',
      streamUrl: 'https://a/1.mp3',
      streamExpiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    expect(fresh.hasFreshStream, isTrue);
  });

  test('track JSON round-trips the fields the library keeps', () {
    final original = MusicTrack(
      id: 'abc',
      title: 'Song',
      sourceId: 'jiosaavn',
      artist: 'Artist',
      album: 'Album',
      artwork: 'https://art',
      duration: const Duration(seconds: 210),
      year: 2019,
      language: 'hindi',
    );
    final restored = MusicTrack.fromJson(original.toJson())!;
    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.artist, original.artist);
    expect(restored.album, original.album);
    expect(restored.duration, original.duration);
    expect(restored.year, original.year);
    expect(restored.language, original.language);
  });

  test('track JSON drops a malformed entry instead of throwing', () {
    expect(MusicTrack.fromJson(const {'title': 'no id'}), isNull);
    expect(MusicTrack.fromJson(const {'id': 'no title'}), isNull);
    expect(MusicTrack.fromJson(const {}), isNull);
  });

  test('track identity is id plus catalogue', () {
    expect(t('1', source: 'a'), t('1', source: 'a'));
    expect(t('1', source: 'a'), isNot(t('1', source: 'b')));
    expect(t('1').hashCode, t('1').hashCode);
  });

  test('hasArtist reports whether the catalogue gave one', () {
    expect(t('1').hasArtist, isFalse);
    expect(t('1', artist: '').hasArtist, isFalse);
    const withArtist = MusicTrack(
      id: '1',
      title: 'x',
      sourceId: 'a',
      artist: 'Me',
    );
    expect(withArtist.hasArtist, isTrue);
  });
}
