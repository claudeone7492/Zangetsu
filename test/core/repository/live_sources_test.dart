// A live-sports fixture is a provider-extension handle, not a title: its
// provider mints a signed, short-lived URL for it, and the same fixture is
// indexed by several sports providers. These tests pin the cross-provider
// resolution that keeps the rail from dead-ending on "no source to play this
// video": resolve through the fixture's own provider first, and when that
// yields nothing, find the same match (by title) on the other installed sports
// providers and resolve THAT provider's handle.
//
// `SourceRepository` is subclassed rather than driven through the JS runtime:
// the fallback routes through the public `hasSource`, `live` and `sources`, so
// overriding those three exercises the real matching + resolution with no
// QuickJS host.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';

MediaItem _fixture(String source, String id, String title) => MediaItem(
  id: id,
  title: title,
  url: 'live:$id|https://$source.test/$id.m3u8',
  type: ProviderType.movie,
  sourceId: source,
  liveSport: 'soccer',
);

VideoSource _src(String url) => VideoSource(url: url, quality: 'Live');

/// A [SourceRepository] whose provider calls are answered from maps. [live] and
/// [sources] are overridden; [liveSources] (the logic under test) is inherited.
class _StubRepo extends SourceRepository {
  _StubRepo({
    required this.installed,
    this.fixturesBySource = const {},
    this.sourcesByKey = const {},
  }) : super(
         manager: ProviderManager(dio: Dio()),
         csManager: CloudStreamManager(),
         aniManager: AniyomiManager(),
         activeSource: ActiveSourceCubit(),
         prefs: PlaybackPrefs(),
       );

  final List<String> installed;
  final Map<String, List<MediaItem>> fixturesBySource;

  /// `sourceId|url` → the sources that provider resolves for that handle.
  final Map<String, List<VideoSource>> sourcesByKey;

  final List<String> askedSources = [];

  @override
  bool hasSource(String sourceId) => installed.contains(sourceId);

  @override
  Future<List<MediaItem>> live({String? sourceId}) async =>
      fixturesBySource[sourceId] ?? const [];

  @override
  Future<List<VideoSource>> sources(
    String episodeUrl, {
    String? sourceId,
    bool fast = false,
  }) async {
    askedSources.add('$sourceId|$episodeUrl');
    return sourcesByKey['$sourceId|$episodeUrl'] ?? const [];
  }
}

void main() {
  group('liveSources cross-provider fallback', () {
    test('resolves through the fixture\'s own provider first', () async {
      final repo = _StubRepo(
        installed: const ['moviebox', 'streamfree'],
        sourcesByKey: {
          'moviebox|live:mb1|https://moviebox.test/mb1.m3u8': [
            _src('https://cdn.test/mb1.m3u8'),
          ],
        },
      );

      final out = await repo.liveSources(
        'live:mb1|https://moviebox.test/mb1.m3u8',
        sourceId: 'moviebox',
        title: 'France vs Germany',
      );

      expect(out.single.url, 'https://cdn.test/mb1.m3u8');
      // Only the owning provider was asked — no fallback work when it answers.
      expect(repo.askedSources, [
        'moviebox|live:mb1|https://moviebox.test/mb1.m3u8',
      ]);
    });

    test('falls back to another provider that still carries the match', () async {
      final repo = _StubRepo(
        installed: const ['moviebox', 'streamfree'],
        // The owning provider no longer resolves the handle (the CDN dropped
        // it); the other provider still lists the same fixture.
        fixturesBySource: {
          'streamfree': [_fixture('streamfree', 'sf1', 'France vs Germany')],
        },
        sourcesByKey: {
          'streamfree|live:sf1|https://streamfree.test/sf1.m3u8': [
            _src('https://cdn.test/sf1.m3u8'),
          ],
        },
      );

      final out = await repo.liveSources(
        'live:mb1|https://moviebox.test/mb1.m3u8',
        sourceId: 'moviebox',
        title: 'France vs Germany',
      );

      expect(out.single.url, 'https://cdn.test/sf1.m3u8');
      // The fallback resolved the OTHER provider's own handle, not the stale one.
      expect(
        repo.askedSources,
        contains('streamfree|live:sf1|https://streamfree.test/sf1.m3u8'),
      );
    });

    test(
      'matches a fixture the two providers title slightly differently',
      () async {
        final repo = _StubRepo(
          installed: const ['moviebox', 'streamfree'],
          fixturesBySource: {
            'streamfree': [_fixture('streamfree', 'sf9', 'France v Germany')],
          },
          sourcesByKey: {
            'streamfree|live:sf9|https://streamfree.test/sf9.m3u8': [
              _src('https://cdn.test/sf9.m3u8'),
            ],
          },
        );

        final out = await repo.liveSources(
          'live:mb9|',
          sourceId: 'moviebox',
          title: 'France vs Germany',
        );

        expect(out.single.url, 'https://cdn.test/sf9.m3u8');
      },
    );

    test('does not match a different fixture', () async {
      final repo = _StubRepo(
        installed: const ['moviebox', 'streamfree'],
        fixturesBySource: {
          'streamfree': [_fixture('streamfree', 'sf2', 'France vs Spain')],
        },
        sourcesByKey: {
          'streamfree|live:sf2|https://streamfree.test/sf2.m3u8': [
            _src('https://cdn.test/sf2.m3u8'),
          ],
        },
      );

      final out = await repo.liveSources(
        'live:mb2|',
        sourceId: 'moviebox',
        title: 'France vs Germany',
      );

      expect(out, isEmpty);
    });

    test('an uninstalled provider is never asked', () async {
      final repo = _StubRepo(
        installed: const ['moviebox'],
        fixturesBySource: {
          'streamfree': [_fixture('streamfree', 'sf3', 'France vs Germany')],
        },
        sourcesByKey: {
          'streamfree|live:sf3|https://streamfree.test/sf3.m3u8': [
            _src('https://cdn.test/sf3.m3u8'),
          ],
        },
      );

      final out = await repo.liveSources(
        'live:mb3|',
        sourceId: 'moviebox',
        title: 'France vs Germany',
      );

      expect(out, isEmpty);
      expect(
        repo.askedSources.where((k) => k.startsWith('streamfree|')),
        isEmpty,
      );
    });

    test('a Nuvio handle resolves through its own provider', () async {
      final repo = _StubRepo(
        installed: const ['nuviotv', 'moviebox'],
        sourcesByKey: {
          'nuviotv|nuviotv:nuvio_sport_1': [
            _src('https://cdn.test/nuvio.m3u8'),
          ],
        },
      );

      final out = await repo.liveSources(
        'nuviotv:nuvio_sport_1',
        sourceId: 'nuviotv',
        title: 'Arsenal vs Chelsea',
      );

      expect(out.single.url, 'https://cdn.test/nuvio.m3u8');
      // If `nuviotv:` were not a live handle, liveSources would delegate to
      // sources with the same key and the fallback would never be reached.
      expect(repo.askedSources, ['nuviotv|nuviotv:nuvio_sport_1']);
    });

    test('an ordinary title delegates to sources unchanged', () async {
      final repo = _StubRepo(
        installed: const ['moviebox'],
        sourcesByKey: {
          'moviebox|https://moviebox.test/show/1': [
            _src('https://cdn.test/show.m3u8'),
          ],
        },
      );

      final out = await repo.liveSources(
        'https://moviebox.test/show/1',
        sourceId: 'moviebox',
      );

      expect(out.single.url, 'https://cdn.test/show.m3u8');
    });
  });
}
