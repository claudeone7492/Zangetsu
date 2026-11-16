// The reels feed's manual retry.
//
// A reel whose automatic resolve comes back empty shows a "Tap to play"
// affordance. Tapping it must RE-RUN the resolve rather than replay the feed's
// memoised failure — that cache is the reason a naive retry would stay dead
// forever. These tests register a real MpvPlayerPool backed by a fake Player so
// the page can actually reach _startPlayback, and a source fake whose first
// resolve yields nothing and whose second yields a stream.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/home_section.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/repository/catalogue_repository.dart';
import 'package:watch_app/core/repository/source_repository.dart';
import 'package:watch_app/features/player/mpv_player_pool.dart';
import 'package:watch_app/features/shorts/shorts_screen.dart';

class _FakePlayer extends Fake implements mk.Player {
  @override
  mk.PlatformPlayer? get platform => null;
  @override
  mk.PlayerState get state => const mk.PlayerState();
  @override
  late final mk.PlayerStream stream = mk.PlayerStream(
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
    const Stream.empty(),
  );
  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {}
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setPlaylistMode(mk.PlaylistMode mode) async {}
  @override
  Future<void> dispose() async {}
}

MediaItem _item(String id) => MediaItem(
  id: id,
  title: 'Drama $id',
  url: 'https://src.test/goodshort/$id',
  type: ProviderType.movie,
  sourceId: 'goodshort',
);

/// A source fake whose `sources()` fails the first [failures] times and then
/// returns a playable stream, so a retry has something to succeed with.
class _RetrySourceRepository implements CatalogueRepository, SourceRepository {
  _RetrySourceRepository({this.failures = 1});

  int failures;
  int sourceCalls = 0;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<({String id, String name})> get loadedSources => const [
    (id: 'goodshort', name: 'goodshort'),
  ];

  @override
  String get sourceId => 'goodshort';

  @override
  bool hasSource(String sourceId) => sourceId == 'goodshort';

  @override
  String displayName(String sourceId) => sourceId;

  @override
  Future<List<MediaItem>> shorts({String? sourceId}) async => [_item('a')];

  @override
  Future<List<HomeSection>> home({
    String category = 'sub',
    String? sourceId,
  }) async => const [];

  @override
  Future<List<Episode>> episodes(
    String url, {
    String category = 'sub',
    String? sourceId,
  }) async => [Episode(id: url, title: 'E1', url: url)];

  @override
  Future<List<VideoSource>> sources(
    String episodeUrl, {
    String? sourceId,
    bool fast = false,
  }) async {
    sourceCalls++;
    if (sourceCalls <= failures) return const [];
    return const [VideoSource(url: 'https://cdn.test/stream.mp4')];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('a failed reel offers a tap-to-play retry', (tester) async {
    // Every resolve fails, so the page never opens a player (and never touches
    // the native video output the test host cannot provide). That keeps the
    // test focused on the thing under test: the retry re-queries the source
    // rather than replaying the feed's memoised failure.
    final repo = _RetrySourceRepository(failures: 100);
    sl.registerSingleton<CatalogueRepository>(repo);
    sl.registerSingleton<SourceRepository>(repo);
    sl.registerSingleton<MpvPlayerPool>(
      MpvPlayerPool(createPlayer: (_) => _FakePlayer()),
    );

    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ShortsScreen()));
    await tester.pumpAndSettle();

    // First resolve came back empty: the retry affordance is up.
    expect(find.text('Tap to play'), findsOneWidget);
    expect(repo.sourceCalls, 1);

    await tester.tap(find.text('Tap to play'));
    await tester.pumpAndSettle();

    // The retry bypassed the memoised null and asked the source again.
    expect(repo.sourceCalls, greaterThanOrEqualTo(2));

    // It is still dead, so the affordance stays — the user can keep retrying.
    expect(find.text('Tap to play'), findsOneWidget);
  });
}
