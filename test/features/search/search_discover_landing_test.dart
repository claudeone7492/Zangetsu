// The metadata Search landing (Z Mode / library scope) is a browse surface:
// region pills, Type/Genre/Year quick filters, an All/Movies/TV tab row with a
// sort menu, and the results as a swipe-paged poster grid. These tests pin the
// two things that broke on a 360dp phone: the tab row overflowing horizontally,
// and the pager staying on a page the new filter set no longer has.
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/di/injector.dart' show sl;
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/my_list.dart';
import 'package:watch_app/core/playback/search_history.dart';
import 'package:watch_app/core/playback/search_prefs.dart';
import 'package:watch_app/core/playback/search_source_prefs.dart';
import 'package:watch_app/core/playback/source_health_store.dart'
    show SourceOutcome;
import 'package:watch_app/core/repository/catalogue_repository.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/search/title_suggestion_service.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/core/zmode/metadata_filters.dart';
import 'package:watch_app/core/zmode/metadata_repository.dart';
import 'package:watch_app/core/zmode/zmode_prefs.dart';
import 'package:watch_app/features/home/search_screen.dart';

import '../../support/picker_deps.dart';

class _FakeSourceRepo implements SourceRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  List<({String id, String name})> get pickableSources => loadedSources;
  @override
  List<({String id, String name})> get loadedSources => const [];
  @override
  String get sourceId => 'fake-source';
  @override
  String displayName(String id) => id;
  @override
  bool hasSource(String id) => false;
  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async => const [];
}

/// Serves a full unfiltered grid and a short filtered one, tagged so the tests
/// can tell which fetch is on screen.
class _FakeMetadataRepo implements MetadataRepository {
  final discover = <MetaFilters>[];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  String get sourceId => 'zm';
  @override
  bool get supportsFilters => true;
  @override
  List<({String id, String name})> get loadedSources => const [];
  @override
  String displayName(String id) => id;
  @override
  bool hasSource(String id) => false;
  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async => const [];
  @override
  Future<List<MediaItem>> searchDiscoverFeed(
    MetaFilters filters, {
    bool? forcedTv,
  }) async {
    discover.add(filters);
    final filtered = filters.genres.isNotEmpty;
    final n = filtered ? 4 : 40;
    final tag = filtered ? 'F' : 'U';
    return [
      for (var i = 0; i < n; i++)
        MediaItem(
          id: '$tag$i',
          title: 'Disc $tag$i',
          url: 'https://x/$tag$i',
          type: ProviderType.movie,
          sourceId: 'zm',
        ),
    ];
  }

  @override
  Future<({List<MediaItem> items, SourceOutcome outcome})> searchStatus(
    String query, {
    String category = 'sub',
    String? sourceId,
    String? filtersJson,
    bool cache = false,
    int page = 1,
  }) async => (items: const <MediaItem>[], outcome: SourceOutcome.ok);
}

class _FakeMyListStore implements MyListStore {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
  @override
  List<MediaItem> all() => const [];
  @override
  bool contains(MediaItem m) => false;
  @override
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('discover_landing');
    Hive.init(dir.path);
    await SearchHistory.init();
    await SearchPrefs.init();
    await SearchSourcePrefs.init();
    await registerPickerDeps();
    final repo = _FakeSourceRepo();
    sl.registerSingleton<SearchHistory>(SearchHistory());
    sl.registerSingleton<SearchPrefs>(SearchPrefs());
    sl.registerSingleton<SearchSourcePrefs>(SearchSourcePrefs());
    sl.registerSingleton<SourceRepository>(repo);
    sl.registerSingleton<CatalogueRepository>(repo);
    sl.registerSingleton<MetadataRepository>(_FakeMetadataRepo());
    sl.registerSingleton<MyListStore>(_FakeMyListStore());
    sl.registerSingleton<TitleSuggestionService>(TitleSuggestionService(Dio()));
  });

  tearDown(() async {
    await disposePickerDeps();
    await sl.reset();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  /// Pumps the landing at a 360dp-wide phone — the narrowest width the tab
  /// row must survive.
  Future<void> pumpLanding(WidgetTester t) async {
    final v = t.view;
    v.physicalSize = const Size(1080, 2600);
    v.devicePixelRatio = 3.0;
    addTearDown(() {
      v.resetPhysicalSize();
      v.resetDevicePixelRatio();
    });
    await t.runAsync(() async {
      await ZModePrefs.init();
      await ZModePrefs.setEnabled(true);
    });
    await t.pumpWidget(
      MaterialApp(
        home: BlocProvider<ActiveSourceCubit>.value(
          value: sl<ActiveSourceCubit>(),
          child: const SearchScreen(),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the discover tab row does not overflow on a 360dp phone', (
    t,
  ) async {
    await pumpLanding(t);
    // A RenderFlex overflow reports through the framework's exception hook; a
    // clean pump means none fired.
    expect(t.takeException(), isNull);
    expect(find.text('All'), findsWidgets);
  });

  testWidgets('swipe the pager then filter — filtered page 1 must show', (
    t,
  ) async {
    await pumpLanding(t);
    // Scroll the outer list down to the pager, then swipe it to page 2.
    await t.drag(find.byType(ListView).first, const Offset(0, -400));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.drag(
      find.byType(PageView).first,
      const Offset(-330, 0),
      warnIfMissed: false,
    );
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    // Scroll back up so the genre pill row is tappable again.
    await t.drag(find.byType(ListView).first, const Offset(0, 400));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // Apply a genre filter (4 items -> a single page).
    await t.tap(find.text('Action').first);
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(
      find.text('Disc F0'),
      findsWidgets,
      reason: 'after filtering, the grid must show the new (single) page',
    );
  });
}
