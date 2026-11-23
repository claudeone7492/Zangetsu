import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/app_config.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/live/sports_feed.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/features/live/sports_screen.dart';

MediaItem _match(
  String id,
  String title, {
  required DateTime start,
  String? badge,
  String? info,
  List<String> genres = const ['Premier League'],
}) => MediaItem(
  id: id,
  title: title,
  url: 'live:$id|https://sports.test/$id.m3u8',
  type: ProviderType.movie,
  sourceId: kLiveSportsSourceIds.first,
  liveBadge: badge,
  liveInfo: info,
  liveSport: 'soccer',
  liveStartMs: start.millisecondsSinceEpoch,
  genres: genres,
);

class _FakeSportsRepository implements SourceRepository {
  _FakeSportsRepository(this.items);

  final List<MediaItem> items;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  bool hasSource(String sourceId) => kLiveSportsSourceIds.contains(sourceId);

  @override
  Future<List<MediaItem>> live({String? sourceId}) async =>
      sourceId == kLiveSportsSourceIds.first ? items : const [];
}

class _MultiSportsRepository implements SourceRepository {
  _MultiSportsRepository(this.bySource);

  final Map<String, List<MediaItem>> bySource;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  bool hasSource(String sourceId) => bySource.containsKey(sourceId);

  @override
  Future<List<MediaItem>> live({String? sourceId}) async =>
      bySource[sourceId] ?? const [];
}

DateTime _todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

DateTime _tomorrowAt(int hour) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    hour,
  ).add(const Duration(days: 1));
}

void main() {
  setUp(() {
    sl.registerSingleton<AppMode>(const AppMode(isTv: false));
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpSports(WidgetTester tester, List<MediaItem> items) async {
    tester.view.physicalSize = const Size(1100, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    sl.registerSingleton<SourceRepository>(_FakeSportsRepository(items));
    await tester.pumpWidget(
      const MaterialApp(home: SportsScreen(showBack: true)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  testWidgets('the match centre leads with live, then today, tomorrow and '
      'results, each grouped by league', (tester) async {
    final items = [
      _match(
        'l1',
        'Arsenal vs Chelsea',
        start: _todayAt(15, 0),
        badge: 'LIVE',
        info: 'Premier League · 63\'',
        genres: const ['Premier League'],
      ),
      _match(
        'l2',
        'Liverpool vs Everton',
        start: _todayAt(15, 0),
        badge: 'LIVE',
        info: 'Premier League · 12\'',
        genres: const ['Premier League'],
      ),
      _match(
        't1',
        'Barcelona vs Real Madrid',
        start: _todayAt(23, 0),
        badge: 'in 2h',
        info: 'La Liga',
        genres: const ['La Liga'],
      ),
      _match(
        'm1',
        'Bayern vs Dortmund',
        start: _tomorrowAt(20),
        badge: 'in 20h',
        info: 'Bundesliga',
        genres: const ['Bundesliga'],
      ),
      _match(
        'f1',
        'PSG vs Marseille',
        start: _todayAt(10, 0),
        badge: 'FT',
        info: 'Ligue 1',
        genres: const ['Ligue 1'],
      ),
    ];

    await pumpSports(tester, items);

    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('TOMORROW'), findsOneWidget);
    expect(find.text('RESULTS'), findsOneWidget);

    // League headers, one card per competition.
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('La Liga'), findsOneWidget);
    expect(find.text('Bundesliga'), findsOneWidget);
    expect(find.text('Ligue 1'), findsOneWidget);

    // Teams are split into the two lines a match centre uses.
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Chelsea'), findsOneWidget);

    // In-play leads the page.
    final liveY = tester.getTopLeft(find.text('LIVE NOW')).dy;
    final todayY = tester.getTopLeft(find.text('TODAY')).dy;
    final tomorrowY = tester.getTopLeft(find.text('TOMORROW')).dy;
    final resultsY = tester.getTopLeft(find.text('RESULTS')).dy;
    expect(liveY, lessThan(todayY));
    expect(todayY, lessThan(tomorrowY));
    expect(tomorrowY, lessThan(resultsY));

    await dispose(tester);
  });

  testWidgets('the Live filter keeps only in-play matches', (tester) async {
    final items = [
      _match(
        'l1',
        'Arsenal vs Chelsea',
        start: _todayAt(15, 0),
        badge: 'LIVE',
        info: 'Premier League · 63\'',
      ),
      _match(
        't1',
        'Barcelona vs Real Madrid',
        start: _todayAt(23, 0),
        badge: 'in 2h',
        info: 'La Liga',
        genres: const ['La Liga'],
      ),
    ];

    await pumpSports(tester, items);
    await tester.tap(find.byKey(const ValueKey('sports-filter-live')));
    await tester.pumpAndSettle();

    expect(find.text('LIVE NOW'), findsOneWidget);
    expect(find.text('Arsenal'), findsOneWidget);
    expect(find.text('Barcelona'), findsNothing);
    expect(find.text('TODAY'), findsNothing);

    await dispose(tester);
  });

  testWidgets('a filter with no matches shows the sport-specific empty state', (
    tester,
  ) async {
    await pumpSports(tester, [
      _match(
        'm1',
        'Bayern vs Dortmund',
        start: _tomorrowAt(20),
        badge: 'in 20h',
        info: 'Bundesliga',
        genres: const ['Bundesliga'],
      ),
    ]);

    await tester.tap(find.byKey(const ValueKey('sports-filter-live')));
    await tester.pumpAndSettle();

    expect(
      find.text('No football matches are in play right now.'),
      findsOneWidget,
    );

    await dispose(tester);
  });

  testWidgets('linear football channels never reach the match centre', (
    tester,
  ) async {
    final channel = MediaItem(
      id: 'ch1',
      title: 'BeIN Sports',
      url: 'sz:bein',
      type: ProviderType.movie,
      sourceId: 'scorezone',
      liveBadge: 'LIVE',
      liveSport: 'soccer',
      liveInfo: '24/7 · US',
      genres: const ['Football Channels'],
    );

    await pumpSports(tester, [
      channel,
      _match(
        'l1',
        'Arsenal vs Chelsea',
        start: _todayAt(15, 0),
        badge: 'LIVE',
        info: 'Premier League · 63\'',
      ),
    ]);

    expect(find.text('BeIN Sports'), findsNothing);
    expect(find.text('Arsenal'), findsOneWidget);

    await dispose(tester);
  });

  test('SportsFeed groups unmapped fixtures into Other Football instead of '
      'dropping them', () {
    final now = DateTime.now();
    final sections = SportsFeed.group([
      _match(
        'x1',
        'Unlisted United vs Unknown FC',
        start: now,
        badge: 'LIVE',
        genres: const [],
      ),
      _match(
        'p1',
        'Arsenal vs Chelsea',
        start: now,
        badge: 'LIVE',
        genres: const ['Premier League'],
      ),
    ]);

    expect(sections.map((s) => s.league.id), contains('other-football'));
    expect(sections.map((s) => s.league.id), contains('premier-league'));
  });

  test('SportsFeed keeps provider-only competitions as their own rows', () {
    final now = DateTime.now();
    final sections = SportsFeed.group([
      _match(
        'g1',
        'Panathinaikos vs OFI Crete',
        start: now,
        badge: 'LIVE',
        info: 'Greek Super League · Soccer',
        genres: const ['Greek Super League'],
      ),
      _match(
        'e1',
        'Leeds vs Norwich',
        start: now,
        badge: 'LIVE',
        info: 'English Football League · Soccer',
        genres: const ['English Football League'],
      ),
    ]);

    final names = sections.map((s) => s.league.name);
    expect(names, contains('Greek Super League'));
    expect(names, contains('English Football League'));
    expect(names, isNot(contains('Football')));
  });

  test('SportsFeed folds provider spellings onto the catalogue league', () {
    final now = DateTime.now();
    final sections = SportsFeed.group([
      _match(
        'l1',
        'Stade Rennais vs Lorient',
        start: now,
        badge: 'LIVE',
        info: 'Ligue One · Soccer',
        genres: const ['Ligue One'],
      ),
      _match(
        'n1',
        'Liverpool vs Manchester United',
        start: now,
        badge: 'LIVE',
        info: 'England - Premier League · Sky Sports Premier League',
        genres: const ['England - Premier League'],
      ),
    ]);

    final ids = sections.map((s) => s.league.id);
    expect(ids, contains('ligue-1'));
    expect(ids, contains('premier-league'));
  });

  test('SportsFeed merges the same fixture across providers even when the '
      'team order and scoreline differ', () async {
    final now = DateTime.now();
    final repo = _MultiSportsRepository({
      kLiveSportsSourceIds[0]: [
        _match(
          'n1',
          'Liverpool vs Manchester United',
          start: now,
          badge: 'LIVE',
          info: 'England - Premier League',
          genres: const ['England - Premier League'],
        ),
      ],
      kLiveSportsSourceIds[1]: [
        _match(
          'm1',
          'Manchester United 2 - 0 Liverpool',
          start: now,
          badge: 'LIVE',
          info: 'Premier League',
        ),
      ],
      kLiveSportsSourceIds[2]: [
        _match(
          't1',
          'Manchester United @ Liverpool',
          start: now,
          badge: 'LIVE',
          info: 'Premier League · Soccer',
        ),
      ],
    });

    final merged = await SportsFeed.fetch(repo);
    expect(merged, hasLength(1));
    expect(merged.single.title, 'Liverpool vs Manchester United');
  });
}
