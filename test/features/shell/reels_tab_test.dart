// The docked Reels tab must show the autoplaying vertical feed. It is mounted
// by the shell's IndexedStack from boot, so it warms its rows before the user
// ever taps it — but providers finish loading on their own schedule, so a
// warm that ran too early must not leave the tab permanently empty.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/repository/catalogue_repository.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/features/shorts/shorts_screen.dart';

MediaItem _item(String id, String title, {String source = 'reelshort'}) =>
    MediaItem(
      id: id,
      title: title,
      url: 'https://src.test/$source/$id',
      type: ProviderType.movie,
      sourceId: source,
    );

/// A repository whose sources are installed only after [ready] flips — the
/// boot race where the docked tab warms before provider load finishes.
class _LateRepo implements CatalogueRepository, SourceRepository {
  bool ready = false;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<({String id, String name})> get loadedSources =>
      ready ? [(id: 'reelshort', name: 'ReelShort')] : const [];

  @override
  String get sourceId => 'reelshort';

  @override
  String displayName(String s) => s;

  @override
  Future<List<MediaItem>> shorts({String? sourceId}) async =>
      ready ? [_item('a', 'Alpha Drama')] : const [];

  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> mount(WidgetTester tester, {required bool active}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: ShortsScreen(active: active, prewarm: true)),
    );
  }

  testWidgets('the docked Reels tab retries once sources are installed', (
    tester,
  ) async {
    final repo = _LateRepo();
    final sl = GetIt.instance;
    sl.registerSingleton<CatalogueRepository>(repo);
    sl.registerSingleton<SourceRepository>(repo);

    // Boot: docked, warming, but the providers have not loaded yet.
    await mount(tester, active: false);
    await tester.pumpAndSettle();
    expect(find.text('Alpha Drama'), findsNothing);

    // Provider load finishes in the background.
    repo.ready = true;

    // The user taps the Reels tab.
    await mount(tester, active: true);
    await tester.pumpAndSettle();

    expect(
      find.text('Alpha Drama'),
      findsOneWidget,
      reason: 'the feed must gather once its sources are actually installed',
    );
  });
}
