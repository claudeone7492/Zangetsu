import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/playback/search_history.dart';
import 'package:watch_app/core/playback/search_prefs.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/core/search/title_suggestion_service.dart';
import 'package:watch_app/core/zmode/metadata_filters.dart';
import 'package:watch_app/features/search/bloc/search_bloc.dart';
import 'package:watch_app/features/search/bloc/search_event.dart';

class _FakeSearchPrefs extends SearchPrefs {
  @override
  String? get contentFilterName => null;
  @override
  String? get audioFilterName => null;
  @override
  String? get statusFilterName => null;
  @override
  String? get sortName => null;
  @override
  String? get genre => null;
  @override
  int? get decade => null;
  @override
  bool get currentSourceOnly => true;
}

class _FakeSearchHistory extends SearchHistory {
  @override
  List<String> recent() => [];
  @override
  Future<void> add(String query) async {}
  @override
  Future<void> remove(String query) async {}
  @override
  Future<void> clear() async {}
}

class _FakeSuggestions extends TitleSuggestionService {
  _FakeSuggestions() : super(Dio());
  @override
  Future<List<String>> suggest(String query, {int limit = 8}) async => [];
}

/// Minimal repo: only the discover feed and the home strip are exercised.
class _FakeRepo implements SourceRepository {
  int discoverCalls = 0;
  MetaFilters? lastFilters;

  @override
  Future<List<MediaItem>> searchDiscoverFeed(
    MetaFilters filters, {
    bool? forcedTv,
  }) async {
    discoverCalls++;
    lastFilters = filters;
    return [
      for (var i = 0; i < 6; i++)
        MediaItem(
          id: 'd$i',
          title: 'Discover $i',
          url: 'https://x/d$i',
          type: ProviderType.movie,
          sourceId: 'zm',
        ),
    ];
  }

  @override
  Future<List<HomeSection>> home({String category = 'sub', String? sourceId}) async =>
      const [];

  @override
  List<({String id, String name})> get loadedSources => const [];

  @override
  String get sourceId => 'zm';

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late _FakeRepo repo;
  late SearchBloc bloc;

  setUp(() {
    repo = _FakeRepo();
    bloc = SearchBloc(
      repo: repo,
      history: _FakeSearchHistory(),
      prefs: _FakeSearchPrefs(),
      suggestions: _FakeSuggestions(),
      metadataLanding: true,
    );
  });

  tearDown(() async => bloc.close());

  test('mode change refetches the discover grid that it dropped', () async {
    bloc.add(const SearchDiscoverRequested(MetaFilters(genres: ['Action'])));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.discoverCalls, 1);
    expect(bloc.state.discoverItems, hasLength(6));

    // A mode switch drops the grid; the bloc must re-issue the same fetch so
    // the landing does not stay blank (the bug this guards).
    bloc.add(const SearchModeChanged());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.discoverCalls, 2, reason: 'grid should be refetched');
    expect(bloc.state.discoverItems, hasLength(6));
    expect(repo.lastFilters?.genres, ['Action']);
  });

  test('mode change does not refetch when the landing never fetched', () async {
    bloc.add(const SearchModeChanged());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(repo.discoverCalls, 0);
    expect(bloc.state.discoverItems, isEmpty);
  });

  test('mode change does not refetch while the user is typing', () async {
    bloc.add(const SearchDiscoverRequested(MetaFilters()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(repo.discoverCalls, 1);

    bloc.add(const SearchQueryChanged('naruto'));
    await Future<void>.delayed(const Duration(milliseconds: 20));

    bloc.add(const SearchModeChanged());
    await Future<void>.delayed(const Duration(milliseconds: 20));

    // The discover handler short-circuits on a non-empty query, so no second
    // call lands even though one was queued.
    expect(repo.discoverCalls, 1);
  });
}
