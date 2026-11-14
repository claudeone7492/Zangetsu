// Shorts is a vertical feed gathered from the app's installed video sources.
// It never asks the user to pick one — it walks CatalogueRepository.loadedSources
// and pulls each source's Home rows. These tests fake that repository and pin
// the behaviour that matters: the feed renders what the sources returned, a
// dead/empty catalogue degrades to the empty state (never a blank page), the
// vertical pager advances the position read-out, and every page carries the
// TikTok-style action rail.
//
// Inline video is deliberately NOT exercised here: these fakes register no
// MpvPlayerPool, so a page shows its poster and never touches media_kit. That
// is the same guard that keeps a headless build off the decoder — see
// _ShortPageState._activate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/repository/catalogue_repository.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/features/shorts/shorts_screen.dart';

MediaItem _item(String id, String title, {String source = 'src1'}) => MediaItem(
  id: id,
  title: title,
  url: 'https://src.test/$source/$id',
  type: ProviderType.movie,
  sourceId: source,
);

class _FakeCatalogueRepository implements CatalogueRepository, SourceRepository {
  _FakeCatalogueRepository({
    this.sections = const [],
    this.throwOnHome = false,
    this.sourceIds = const ['src1'],
    this.itemsBySource = const {},
  });

  final List<HomeSection> sections;
  final bool throwOnHome;
  final List<String> sourceIds;

  /// Per-source home rows, so a test can prove which sources the feed walked.
  final Map<String, List<HomeSection>> itemsBySource;

  /// Source ids the feed actually pulled home rows from, in order.
  final List<String> walked = [];

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<({String id, String name})> get loadedSources => [
    for (final id in sourceIds) (id: id, name: id),
  ];

  @override
  String get sourceId => sourceIds.first;

  @override
  String displayName(String sourceId) => sourceId;

  @override
  Future<List<MediaItem>> shorts({String? sourceId}) async => const [];

  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async {
    if (sourceId != null) walked.add(sourceId);
    if (throwOnHome) throw StateError('source down');
    if (sourceId != null && itemsBySource.containsKey(sourceId)) {
      return itemsBySource[sourceId]!;
    }
    return sections;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The feed reads the SOURCE repository directly (never the Z Mode router),
  // so every fake is registered under both interfaces.
  void register(_FakeCatalogueRepository repo) {
    sl.registerSingleton<CatalogueRepository>(repo);
    sl.registerSingleton<SourceRepository>(repo);
  }

  Future<void> pumpShorts(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ShortsScreen()));
  }

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('renders a feed gathered from the installed sources', (
    tester,
  ) async {
    register(
      _FakeCatalogueRepository(
        sections: [
          HomeSection(
            title: 'Trending',
            items: [_item('a', 'Alpha'), _item('b', 'Bravo')],
          ),
        ],
      ),
    );

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('the vertical pager advances the position read-out', (
    tester,
  ) async {
    register(
      _FakeCatalogueRepository(
        sections: [
          HomeSection(
            title: 'Trending',
            items: [_item('a', 'Alpha'), _item('b', 'Bravo')],
          ),
        ],
      ),
    );

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(PageView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Bravo'), findsOneWidget);
  });

  testWidgets('a source that returns nothing yields the empty state', (
    tester,
  ) async {
    register(_FakeCatalogueRepository());

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a source that throws does not sink the feed', (tester) async {
    register(
      _FakeCatalogueRepository(throwOnHome: true),
    );

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    // The dead source is swallowed: the screen lands on the empty state rather
    // than throwing out of the build.
    expect(tester.takeException(), isNull);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('manga/novel items are excluded from the video feed', (
    tester,
  ) async {
    register(
      _FakeCatalogueRepository(
        sections: [
          HomeSection(
            title: 'Mixed',
            items: [
              _item('a', 'Alpha'),
              MediaItem(
                id: 'm',
                title: 'A Manga',
                url: 'https://src.test/src1/m',
                type: ProviderType.manga,
                sourceId: 'src1',
              ),
            ],
          ),
        ],
      ),
    );

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('A Manga'), findsNothing);
    expect(find.text('1 / 1'), findsOneWidget);
  });

  testWidgets('every page carries the TikTok-style action rail', (
    tester,
  ) async {
    register(
      _FakeCatalogueRepository(
        sections: [
          HomeSection(title: 'Trending', items: [_item('a', 'Alpha')]),
        ],
      ),
    );

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    // Save / comments / share / details — the four actions down the right edge.
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Show details'), findsOneWidget);
  });

  testWidgets('prewarm gathers the feed while the tab is still off-screen', (
    tester,
  ) async {
    register(
      _FakeCatalogueRepository(
        sections: [
          HomeSection(title: 'Trending', items: [_item('a', 'Alpha')]),
        ],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ShortsScreen(active: false, prewarm: true)),
    );
    await tester.pumpAndSettle();

    // The rows are already there, so tapping the tab opens onto them — no
    // fetch, no spinner.
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('an off-screen tab without prewarm does no work', (tester) async {
    register(
      _FakeCatalogueRepository(
        sections: [
          HomeSection(title: 'Trending', items: [_item('a', 'Alpha')]),
        ],
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ShortsScreen(active: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PageView), findsNothing);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets('the short-drama sources lead the feed ahead of movie sources', (
    tester,
  ) async {
    // Install order deliberately puts the generic movie sources first — the
    // registry sorts by key, so that is what a real device hands the feed. The
    // feed caps how many sources it walks, so the drama catalogues must be
    // hoisted or the cap fills with frameXTV/NetWeb/VidSrc and no drama shows.
    final repo = _FakeCatalogueRepository(
      sourceIds: const [
        'framextv',
        'netweb',
        'vidsrc',
        'vidlink',
        'goodshort',
        'reelshort',
        'netshort',
        'moviebox',
      ],
      itemsBySource: {
        'moviebox': [
          HomeSection(
            title: 'Shorts',
            items: [_item('m', 'Drama M', source: 'moviebox')],
          ),
        ],
      },
    );
    register(repo);

    await pumpShorts(tester);
    await tester.pumpAndSettle();

    expect(repo.walked.first, 'moviebox');
    expect(repo.walked.take(4), [
      'moviebox',
      'goodshort',
      'reelshort',
      'netshort',
    ]);
    expect(find.text('Drama M'), findsOneWidget);
  });
}
