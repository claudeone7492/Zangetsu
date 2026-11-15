// The Shorts content mode is a SHORT-DRAMA surface: "it should be only AI
// shorts fully for all sections". These tests pin the two rules that keep it
// that way — the source list is the drama catalogues ONLY, and a catalogue
// whose own home rows are movies (MovieBox) never contributes its home rows
// when its dedicated `getShorts` feed comes back empty.
//
// `SourceRepository` is subclassed rather than faked through the provider
// runtime: `shortsSourceIds`/`shortsHome` route through the public `hasSource`,
// `shorts` and `home`, so overriding just those three exercises the real
// selection + interleave + slicing logic with no QuickJS runtime.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';

MediaItem _drama(String id, {String source = 'goodshort'}) => MediaItem(
  id: id,
  title: 'Drama $id',
  url: 'https://src.test/$source/$id',
  type: ProviderType.movie,
  sourceId: source,
);

/// A [SourceRepository] whose provider calls are answered from maps, so the
/// Shorts Home logic can be driven without a native/JS provider. Everything
/// else is inherited untouched.
class _StubRepo extends SourceRepository {
  _StubRepo({
    required this.installed,
    this.shortsBySource = const {},
    this.homeBySource = const {},
  }) : super(
         manager: ProviderManager(dio: Dio()),
         csManager: CloudStreamManager(),
         aniManager: AniyomiManager(),
         activeSource: ActiveSourceCubit(),
         prefs: PlaybackPrefs(),
       );

  final List<String> installed;
  final Map<String, List<MediaItem>> shortsBySource;
  final Map<String, List<HomeSection>> homeBySource;

  /// Source ids the Shorts Home actually asked for a feed, in call order.
  final List<String> askedShorts = [];
  final List<String> askedHome = [];

  @override
  bool hasSource(String sourceId) => installed.contains(sourceId);

  @override
  Future<List<MediaItem>> shorts({String? sourceId}) async {
    if (sourceId != null) askedShorts.add(sourceId);
    return shortsBySource[sourceId] ?? const [];
  }

  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async {
    if (sourceId != null) askedHome.add(sourceId);
    return homeBySource[sourceId] ?? const [];
  }
}

void main() {
  group('shortsSourceIds', () {
    test('lists only the installed drama catalogues, in config order', () {
      final repo = _StubRepo(
        installed: const [
          'framextv', // generic movie source
          'reelshort',
          'moviebox',
          'goodshort',
          'netshort',
          'vidsrc', // generic movie source
        ],
      );
      expect(repo.shortsSourceIds(), [
        'moviebox',
        'goodshort',
        'reelshort',
        'netshort',
      ]);
    });

    test('a device with only generic movie sources yields an empty list', () {
      final repo = _StubRepo(installed: const ['framextv', 'vidsrc']);
      expect(repo.shortsSourceIds(), isEmpty);
    });
  });

  group('shortsHome', () {
    test('fills every standard section from the drama feeds only', () async {
      final repo = _StubRepo(
        installed: const ['framextv', 'goodshort', 'reelshort'],
        shortsBySource: {
          'goodshort': [_drama('g1'), _drama('g2')],
          'reelshort': [_drama('r1', source: 'reelshort')],
        },
      );

      final sections = await repo.shortsHome();

      // No generic movie source was ever asked for anything.
      expect(repo.askedShorts, ['goodshort', 'reelshort']);
      expect(repo.askedHome, isEmpty);
      // The standard section titles are reused, so the mode reads like every
      // other mode and never names a source.
      expect(sections.first.title, SourceRepository.kShortsHomeRowTitles.first);
      // The dramas lead the pool, interleaved round-robin (each catalogue's
      // first drama in turn), so no single source fills a whole row.
      final titles = sections.expand((s) => s.items).map((m) => m.title).toList();
      expect(titles, ['Drama g1', 'Drama r1', 'Drama g2']);
    });

    test('MovieBox never falls back to its movie home rows', () async {
      // MovieBox's `getShorts` is empty here. Its home is movies/TV, so the
      // Shorts Home must take NOTHING from it rather than a page of films.
      final repo = _StubRepo(
        installed: const ['moviebox'],
        homeBySource: {
          'moviebox': [
            HomeSection(title: 'Popular Movies', items: [_drama('film')]),
          ],
        },
      );

      final sections = await repo.shortsHome();

      expect(repo.askedShorts, ['moviebox']);
      // Its home was never even walked.
      expect(repo.askedHome, isEmpty);
      expect(sections, isEmpty);
    });

    test('a drama-only catalogue may fall back to its own home rows', () async {
      // goodshort has no `getShorts` answer, but its home IS short dramas end
      // to end, so it is a legitimate fallback.
      final repo = _StubRepo(
        installed: const ['goodshort'],
        homeBySource: {
          'goodshort': [
            HomeSection(title: 'Short Dramas', items: [_drama('h1')]),
          ],
        },
      );

      final sections = await repo.shortsHome();

      expect(repo.askedHome, ['goodshort']);
      expect(sections.expand((s) => s.items).map((m) => m.title), ['Drama h1']);
    });

    test('manga and novel rows never reach the Shorts Home', () async {
      final repo = _StubRepo(
        installed: const ['goodshort'],
        shortsBySource: {
          'goodshort': [
            _drama('ok'),
            MediaItem(
              id: 'm',
              title: 'A Manga',
              url: 'https://src.test/goodshort/m',
              type: ProviderType.manga,
              sourceId: 'goodshort',
            ),
          ],
        },
      );

      final sections = await repo.shortsHome();
      final titles = sections.expand((s) => s.items).map((m) => m.title).toList();
      expect(titles, ['Drama ok']);
    });

    test('a dead source does not sink the page', () async {
      final repo = _StubRepo(
        installed: const ['goodshort'],
        shortsBySource: {'goodshort': [_drama('ok')]},
      );
      final sections = await repo.shortsHome();
      expect(sections, isNotEmpty);
    });
  });
}
