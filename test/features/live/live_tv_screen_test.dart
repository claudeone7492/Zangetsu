// Live TV is the phone/TV screen over the bundled IPTV source. It reads the
// catalogue through [SourceRepository] directly (never the router), so these
// tests fake that repository and assert the three states the screen can be in
// — browse, search, and failure — plus the debounce that keeps a large IPTV
// index from being swept once per keystroke.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/features/live/live_tv_screen.dart';

MediaItem _channel(String id, String title) => MediaItem(
  id: id,
  title: title,
  url: 'https://iptv.test/$id',
  type: ProviderType.movie,
  sourceId: kLiveTvSourceId,
);

MediaItem _match(String id, String title) => MediaItem(
  id: id,
  title: title,
  url: 'live:$id|https://sports.test/$id.m3u8',
  type: ProviderType.movie,
  sourceId: kLiveSportsSourceId,
);

class _FakeSourceRepository implements SourceRepository {
  _FakeSourceRepository({
    this.sections,
    this.searchHits,
    this.fail = false,
    this.liveMatches,
    this.hasSportsSource = true,
  });

  final List<HomeSection>? sections;
  final List<MediaItem>? searchHits;
  final bool fail;
  final List<MediaItem>? liveMatches;

  /// Whether the MovieBox (sports) source is installed. False exercises the
  /// "no sports rail" path without an extra failure mode.
  final bool hasSportsSource;

  int homeCalls = 0;
  int searchCalls = 0;
  int liveCalls = 0;
  String? lastSearchQuery;
  String? lastSourceId;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  Future<bool> ensureSourceLoaded(String sourceId) async => true;

  @override
  List<({String id, String name})> get pickableSources => const [];

  @override
  String get sourceId => kLiveTvSourceId;

  @override
  bool hasSource(String sourceId) =>
      sourceId == kLiveTvSourceId ||
      (sourceId == kLiveSportsSourceId && hasSportsSource);

  @override
  String displayName(String sourceId) => 'IPTV';

  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async {
    homeCalls++;
    lastSourceId = sourceId;
    if (fail) throw StateError('iptv down');
    return sections ?? const [];
  }

  @override
  Future<List<MediaItem>> live({String? sourceId}) async {
    liveCalls++;
    if (fail) throw StateError('sports down');
    return liveMatches ?? const [];
  }

  @override
  Future<List<MediaItem>> search(
    String query, {
    String category = 'sub',
    String? sourceId,
  }) async {
    searchCalls++;
    lastSearchQuery = query;
    if (fail) throw StateError('iptv search down');
    return searchHits ?? const [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final hiveDir = Directory('/tmp/zangetsu_live_tv_test_hive');

  Future<void> pumpLive(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1100, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: LiveTvScreen(showBack: true)),
    );
  }

  setUp(() async {
    if (hiveDir.existsSync()) hiveDir.deleteSync(recursive: true);
    Hive.init(hiveDir.path);
    await Hive.openBox('app_flags');
    // PosterCard reads its geometry from PlaybackPrefs, which reads a Hive box.
    await PlaybackPrefs.init();
    sl.registerSingleton<AppMode>(const AppMode(isTv: false));
    sl.registerSingleton<PlaybackPrefs>(PlaybackPrefs());
  });

  tearDown(() async {
    await GetIt.instance.reset();
    await Hive.deleteFromDisk();
    if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
  });

  testWidgets('browse renders the IPTV rails from the bundled source', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(
          title: 'News',
          items: [_channel('n1', 'World News'), _channel('n2', 'Local News')],
        ),
        HomeSection(title: 'Sports', items: [_channel('s1', 'Football')]),
      ],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    expect(repo.homeCalls, 1);
    // The screen pins the IPTV source by id rather than taking the active one.
    expect(repo.lastSourceId, kLiveTvSourceId);
    expect(find.text('News'), findsWidgets);
    expect(find.text('Sports'), findsWidgets);
    expect(find.text('World News'), findsOneWidget);
    expect(find.text('Football'), findsOneWidget);
  });

  testWidgets('the sub-header lists All plus every non-empty category', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
        HomeSection(title: 'Sports', items: [_channel('s1', 'Football')]),
        HomeSection(title: 'Empty', items: const []),
      ],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    // All + the two categories that actually have channels; the empty one is
    // dropped so a filter can never land on a blank rail.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('News'), findsWidgets);
    expect(find.text('Sports'), findsWidgets);
    expect(find.text('Empty'), findsNothing);
  });

  testWidgets('picking a category narrows the rails to that category', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
        HomeSection(title: 'Sports', items: [_channel('s1', 'Football')]),
      ],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    // Tap the "Sports" chip (index 2: All=0, News=1, Sports=2) rather than the
    // rail header that also reads "Sports".
    await tester.tap(find.byKey(const ValueKey('live-category-2')));
    await tester.pumpAndSettle();

    expect(find.text('Football'), findsOneWidget);
    expect(find.text('World News'), findsNothing);

    // Back to All restores both.
    await tester.tap(find.byKey(const ValueKey('live-category-0')));
    await tester.pumpAndSettle();
    expect(find.text('World News'), findsOneWidget);
    expect(find.text('Football'), findsOneWidget);
  });

  testWidgets('the sort control reorders the channels', (tester) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(
          title: 'News',
          items: [_channel('n1', 'Zebra TV'), _channel('n2', 'Alpha TV')],
        ),
      ],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    // Default keeps catalogue order (Zebra first).
    expect(
      tester.getTopLeft(find.text('Zebra TV')).dx,
      lessThan(tester.getTopLeft(find.text('Alpha TV')).dx),
    );

    await tester.tap(find.byKey(const ValueKey('live-sort-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A–Z').last);
    await tester.pumpAndSettle();

    // A–Z puts Alpha first.
    expect(
      tester.getTopLeft(find.text('Alpha TV')).dx,
      lessThan(tester.getTopLeft(find.text('Zebra TV')).dx),
    );
  });

  testWidgets('a failed browse shows the retry state, and retry re-fetches', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(fail: true);
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    expect(repo.homeCalls, 1);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(repo.homeCalls, 2);
  });

  testWidgets('an empty catalogue shows the empty state, not a blank page', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(sections: const []);
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('search debounces and renders the hits', (tester) async {
    final repo = _FakeSourceRepository(
      sections: const [],
      searchHits: [_channel('n1', 'World News')],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'news');
    // Before the debounce elapses nothing has been fetched.
    await tester.pump(const Duration(milliseconds: 100));
    expect(repo.searchCalls, 0);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repo.searchCalls, 1);
    expect(repo.lastSearchQuery, 'news');
    expect(find.text('World News'), findsOneWidget);
  });

  testWidgets('clearing the search returns to the browse rails', (tester) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
      ],
      searchHits: [_channel('x', 'Hit')],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'news');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Hit'), findsOneWidget);
    expect(find.text('World News'), findsNothing);

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('World News'), findsOneWidget);
    expect(find.text('Hit'), findsNothing);
  });

  testWidgets('a failed search shows its own retry state', (tester) async {
    final repo = _FakeSourceRepository(fail: true);
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'news');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(repo.searchCalls, 1);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('live sports matches lead the All view as their own rail', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
      ],
      liveMatches: [
        _match('m1', 'England vs Croatia'),
        _match('m2', 'Italy vs France'),
      ],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    // The sports feed is fetched from the MovieBox source, not IPTV.
    expect(repo.liveCalls, 1);
    expect(find.text('Live Sports'), findsWidgets);
    expect(find.text('England vs Croatia'), findsOneWidget);
    // The IPTV channels are still there, below the matches.
    expect(find.text('World News'), findsOneWidget);
  });

  testWidgets('a missing sports source simply drops the rail', (tester) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
      ],
      hasSportsSource: false,
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    expect(repo.liveCalls, 0);
    expect(find.text('Live Sports'), findsNothing);
    expect(find.text('World News'), findsOneWidget);
  });

  testWidgets('picking a channel category focuses on channels, dropping sports', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
      ],
      liveMatches: [_match('m1', 'England vs Croatia')],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();
    expect(find.text('England vs Croatia'), findsOneWidget);

    // Category index 1 is the first real IPTV category ("News").
    await tester.tap(find.byKey(const ValueKey('live-category-1')));
    await tester.pumpAndSettle();

    expect(find.text('England vs Croatia'), findsNothing);
    expect(find.text('World News'), findsOneWidget);

    // Back to All brings the sports rail back.
    await tester.tap(find.byKey(const ValueKey('live-category-0')));
    await tester.pumpAndSettle();
    expect(find.text('England vs Croatia'), findsOneWidget);
  });

  testWidgets('a dead sports endpoint does not sink the channels page', (
    tester,
  ) async {
    final repo = _FakeSourceRepository(
      sections: [
        HomeSection(title: 'News', items: [_channel('n1', 'World News')]),
      ],
      liveMatches: const [],
    );
    sl.registerSingleton<SourceRepository>(repo);

    await pumpLive(tester);
    await tester.pumpAndSettle();

    expect(find.text('World News'), findsOneWidget);
    expect(find.text('Live Sports'), findsNothing);
    // No "failed" screen — the page is up, just without sports.
    expect(find.text('Try again'), findsNothing);
  });
}
