// Hikari (`.hiki` extensions) gets a hub row like CloudStream/Aniyomi/Mihon.
//
// Platform.isAndroid can't be faked in `flutter test` (it reports false on the
// host), so this file can't exercise the row's on-Android appearance. What it
// does prove is the part that breaks silently:
//  - the row and its count stay out of the header total off-Android;
//  - a `hiki:` active id is excluded from `activeIsZangetsu`, so it does not
//    badge the Zangetsu row as ACTIVE;
//  - `_activeSourceLabel` resolves a `hiki:` id to its display name;
//  - a minimal GetIt without HikariManager does not crash the hub.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/app_mode.dart';
import 'package:watch_app/core/hikari/hikari_manager.dart';
import 'package:watch_app/core/hikari/hikari_provider.dart';
import 'package:watch_app/core/mihon/mihon_manager.dart';
import 'package:watch_app/core/provider/cloudstream_provider.dart';
import 'package:watch_app/core/provider/provider_manager.dart';
import 'package:watch_app/core/provider/provider_registry.dart';
import 'package:watch_app/core/provider/provider_repo_registry.dart';
import 'package:watch_app/core/state/active_source_cubit.dart';
import 'package:watch_app/features/sources/providers_hub_screen.dart';

class _FakeProviderRegistry implements ProviderRegistry {
  _FakeProviderRegistry(this._entries);
  final List<ProviderRegistryEntry> _entries;

  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<ProviderRegistryEntry> getAll() => _entries;

  @override
  ProviderRegistryEntry? entryFor(String sourceId) {
    for (final e in _entries) {
      if (e.name == sourceId) return e;
    }
    return null;
  }

  @override
  Set<String> nsfwSourceIds() => const {};

  @override
  String? typeOf(String sourceId) => null;

  @override
  Stream<BoxEvent> watch() => const Stream<BoxEvent>.empty();
}

class _FakeReposRegistry implements ProviderReposRegistry {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);

  @override
  List<ProviderRepo> getAll() => const [];

  @override
  Stream<BoxEvent> watch() => const Stream<BoxEvent>.empty();
}

HikariProviderAdapter _hikariSrc({String id = 'yts', String name = 'YTS'}) =>
    HikariProviderAdapter(
      path: '/tmp/$id.hiki',
      info: HikariLoadedInfo(
        name: name,
        version: 1,
        mainClass: 'YtsPlugin',
        providerId: id,
        providerName: name,
        mainUrl: 'https://$id.example',
        description: '',
        iconUrl: null,
        tvTypes: const ['movie'],
      ),
      lang: '',
    );

void main() {
  final sl = GetIt.instance;

  setUp(() {
    final entries = [
      ProviderRegistryEntry(
        name: 'anime1',
        url: 'bundled://anime1',
        displayName: 'Anime One',
      ),
      ProviderRegistryEntry(
        name: 'anime2',
        url: 'bundled://anime2',
        displayName: 'Anime Two',
      ),
    ];
    sl
      ..registerSingleton<AppMode>(const AppMode(isTv: false))
      ..registerSingleton<ProviderRegistry>(_FakeProviderRegistry(entries))
      ..registerSingleton<ProviderReposRegistry>(_FakeReposRegistry())
      ..registerSingleton<CloudStreamManager>(CloudStreamManager())
      ..registerSingleton<AniyomiManager>(AniyomiManager())
      ..registerSingleton<MihonManager>(MihonManager())
      ..registerSingleton<HikariManager>(HikariManager())
      ..registerSingleton<ActiveSourceCubit>(ActiveSourceCubit(fallback: ''));
  });

  tearDown(() async {
    await sl.reset();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProvidersHubScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('the Hikari row stays absent off-Android', (tester) async {
    await pump(tester);
    expect(find.text('Hikari'), findsNothing);
  });

  testWidgets('a registered Hikari source does not leak into the header total',
      (tester) async {
    sl<HikariManager>().register(_hikariSrc());
    await pump(tester);
    // Only the two Zangetsu entries: the `showHikari ? x : 0` guard is what
    // keeps this true off-Android.
    expect(find.text('2 sources'), findsOneWidget);
  });

  testWidgets('a hiki: active id does not badge the Zangetsu row as ACTIVE',
      (tester) async {
    sl<HikariManager>().register(_hikariSrc());
    sl.unregister<ActiveSourceCubit>();
    sl.registerSingleton<ActiveSourceCubit>(
      ActiveSourceCubit(fallback: 'hiki:yts'),
    );

    await pump(tester);

    // The Hikari row is hidden off-Android, so nothing should read ACTIVE.
    // Without the activeIsHikari exclusion this would badge Zangetsu instead.
    expect(find.text('ACTIVE'), findsNothing);
  });

  testWidgets('_activeSourceLabel resolves a hiki: id to its display name',
      (tester) async {
    sl<HikariManager>().register(_hikariSrc(name: 'YTS Movies'));
    sl.unregister<ActiveSourceCubit>();
    sl.registerSingleton<ActiveSourceCubit>(
      ActiveSourceCubit(fallback: 'hiki:yts'),
    );

    await pump(tester);

    expect(find.textContaining('Active: YTS Movies'), findsOneWidget);
  });

  testWidgets('the hub renders with no HikariManager registered',
      (tester) async {
    sl.unregister<HikariManager>();
    await pump(tester);
    expect(find.text('Providers'), findsOneWidget);
  });
}
