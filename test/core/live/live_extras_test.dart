import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/live/catchup_url.dart';
import 'package:watch_app/core/live/live_parental.dart';
import 'package:watch_app/core/live/sports_catalog.dart';

/// In-memory secure storage so the parental store's real read/write path runs
/// without a platform channel.
class _MemoryStorage implements FlutterSecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => data.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('sports catalog', () {
    test('normalise folds case and punctuation', () {
      expect(normalise('  Man-United!! '), 'man united');
    });

    test('a named competition beats the generic sport', () {
      expect(leagueFor('Premier League: Arsenal v Chelsea')?.id, 'premier-league');
      expect(leagueFor('Champions League Highlights')?.id, 'champions-league');
      expect(leagueFor('NBA: Lakers v Celtics')?.id, 'nba');
      expect(leagueFor('Formula 1: Monaco GP')?.id, 'f1');
    });

    test('aliases match the league they belong to', () {
      expect(leagueFor('EPL live')?.id, 'premier-league');
      expect(leagueFor('UCL tonight')?.id, 'champions-league');
      expect(leagueFor('UFC Fight Night')?.id, 'boxing');
    });

    test('a non-sport title belongs to no league', () {
      expect(leagueFor('The Evening News'), isNull);
      expect(leagueFor(''), isNull);
    });

    test('groupFixtures infers the league from the channel as a fallback', () {
      final groups = groupFixtures([
        (
          title: 'Arsenal v Chelsea',
          channelName: 'Premier League TV',
          channelId: 'pl.tv',
          start: DateTime.utc(2026, 1, 1, 20),
          isLive: true,
        ),
      ]);
      expect(groups.single.league.id, 'premier-league');
    });

    test('live groups sort first, then by league priority', () {
      final groups = groupFixtures([
        (
          title: 'NBA: Lakers v Celtics',
          channelName: 'NBA TV',
          channelId: 'nba.tv',
          start: DateTime.utc(2026, 1, 2, 20),
          isLive: false,
        ),
        (
          title: 'Premier League: Spurs v Everton',
          channelName: 'PL TV',
          channelId: 'pl.tv',
          start: DateTime.utc(2026, 1, 1, 20),
          isLive: true,
        ),
      ]);
      expect(groups.first.league.id, 'premier-league');
      expect(groups.first.hasLive, isTrue);
    });

    test('fixtures within a group put live first then soonest', () {
      final groups = groupFixtures([
        (
          title: 'Premier League: later',
          channelName: '',
          channelId: 'a',
          start: DateTime.utc(2026, 1, 1, 22),
          isLive: false,
        ),
        (
          title: 'Premier League: live now',
          channelName: '',
          channelId: 'b',
          start: DateTime.utc(2026, 1, 1, 19),
          isLive: true,
        ),
      ]);
      expect(groups.single.fixtures.first.isLive, isTrue);
    });

    test('non-sport items are dropped', () {
      expect(
        groupFixtures([
          (
            title: 'Cooking Show',
            channelName: 'Food TV',
            channelId: 'food',
            start: null,
            isLive: false,
          ),
        ]),
        isEmpty,
      );
    });
  });

  group('catch-up', () {
    test('no spec means no URL', () {
      expect(
        buildCatchupUrl(
          liveUrl: 'https://cdn/live.m3u8',
          spec: CatchupSpec.none,
          when: DateTime.utc(2026, 1, 1, 20),
        ),
        isNull,
      );
    });

    test('appendQuery adds utc and lutc', () {
      final url = buildCatchupUrl(
        liveUrl: 'https://cdn/live.m3u8',
        spec: const CatchupSpec(mode: CatchupMode.appendQuery, days: 7),
        when: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 2, 20),
      );
      final start = DateTime.utc(2026, 1, 1, 20).millisecondsSinceEpoch ~/ 1000;
      final ref = DateTime.utc(2026, 1, 2, 20).millisecondsSinceEpoch ~/ 1000;
      expect(url, 'https://cdn/live.m3u8?utc=$start&lutc=$ref');
    });

    test('appendQuery uses & when the live URL already has a query', () {
      final url = buildCatchupUrl(
        liveUrl: 'https://cdn/live.m3u8?token=abc',
        spec: const CatchupSpec(mode: CatchupMode.appendQuery, days: 7),
        when: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 2, 20),
      );
      expect(url, contains('token=abc&utc='));
    });

    test('outside the retention window yields no URL', () {
      expect(
        buildCatchupUrl(
          liveUrl: 'https://cdn/live.m3u8',
          spec: const CatchupSpec(mode: CatchupMode.appendQuery, days: 3),
          when: DateTime.utc(2026, 1, 1, 20),
          now: DateTime.utc(2026, 1, 10, 20),
        ),
        isNull,
      );
    });

    test('an unknown window is still attempted', () {
      expect(
        buildCatchupUrl(
          liveUrl: 'https://cdn/live.m3u8',
          spec: const CatchupSpec(mode: CatchupMode.appendQuery),
          when: DateTime.utc(2026, 1, 1, 20),
          now: DateTime.utc(2026, 6, 1, 20),
        ),
        isNotNull,
      );
    });

    test('pathOffset builds the Flussonic form', () {
      final url = buildCatchupUrl(
        liveUrl: 'https://cdn/channel/index.m3u8',
        spec: const CatchupSpec(mode: CatchupMode.pathOffset, days: 7),
        when: DateTime.utc(2026, 1, 1, 19),
        now: DateTime.utc(2026, 1, 1, 20),
        durationMinutes: 60,
      );
      expect(url, 'https://cdn/channel/index.m3u8/3600/3600/index.m3u8');
    });

    test('template substitutes the placeholders', () {
      final url = buildCatchupUrl(
        liveUrl: 'https://cdn/live.m3u8',
        spec: const CatchupSpec(
          mode: CatchupMode.template,
          template: 'https://cdn/replay?start={utc}&end={end_timestamp}',
          days: 7,
        ),
        when: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 2, 20),
        durationMinutes: 60,
      );
      final start = DateTime.utc(2026, 1, 1, 20).millisecondsSinceEpoch ~/ 1000;
      final end =
          DateTime.utc(2026, 1, 1, 21).millisecondsSinceEpoch ~/ 1000;
      expect(url, 'https://cdn/replay?start=$start&end=$end');
    });

    test('a relative template resolves against the live origin', () {
      final url = buildCatchupUrl(
        liveUrl: 'https://cdn.example:8080/live/a.m3u8',
        spec: const CatchupSpec(
          mode: CatchupMode.template,
          template: '/timeshift/{utc}.m3u8',
          days: 7,
        ),
        when: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 2, 20),
      );
      expect(url, startsWith('https://cdn.example:8080/timeshift/'));
    });

    test('parseM3uAttributes reads quoted pairs', () {
      final attrs = parseM3uAttributes(
        '#EXTINF:-1 tvg-id="bbc1.uk" catchup="default" '
        'catchup-days="7" catchup-source="https://cdn/r?utc={utc}",BBC One',
      );
      expect(attrs['tvg-id'], 'bbc1.uk');
      expect(attrs['catchup-days'], '7');
      expect(attrs['catchup-source'], 'https://cdn/r?utc={utc}');
    });

    test('fromM3u picks the dialect from the attributes', () {
      expect(
        CatchupInfo.fromM3u('#EXTINF:-1 catchup="default" catchup-days="7"')
            .spec
            .mode,
        CatchupMode.appendQuery,
      );
      expect(
        CatchupInfo.fromM3u('#EXTINF:-1 catchup="shift"').spec.mode,
        CatchupMode.pathOffset,
      );
      expect(
        CatchupInfo.fromM3u(
          '#EXTINF:-1 catchup-source="https://cdn/{utc}"',
        ).spec.mode,
        CatchupMode.template,
      );
      expect(
        CatchupInfo.fromM3u('#EXTINF:-1').isAvailable,
        isFalse,
      );
    });

    test('catchup-correction shifts the requested start', () {
      final info = CatchupInfo.fromM3u(
        '#EXTINF:-1 catchup="default" catchup-days="7" '
        'catchup-correction="-60"',
      );
      expect(info.correctionSeconds, -60);
      final url = info.urlFor(
        liveUrl: 'https://cdn/live.m3u8',
        when: DateTime.utc(2026, 1, 1, 20),
        now: DateTime.utc(2026, 1, 2, 20),
      );
      final shifted =
          DateTime.utc(2026, 1, 1, 19, 59).millisecondsSinceEpoch ~/ 1000;
      expect(url, contains('utc=$shifted'));
    });

    test('encode/decode round-trips', () {
      const info = CatchupInfo(
        spec: CatchupSpec(
          mode: CatchupMode.template,
          template: 'https://cdn/{utc}',
          days: 5,
        ),
        correctionSeconds: -2,
      );
      final back = decodeCatchup(encodeCatchup(info));
      expect(back.spec.mode, CatchupMode.template);
      expect(back.spec.days, 5);
      expect(back.correctionSeconds, -2);
    });

    test('a malformed payload decodes to unavailable', () {
      expect(decodeCatchup('nope').isAvailable, isFalse);
      expect(decodeCatchup('[]').isAvailable, isFalse);
    });
  });

  group('parseRating', () {
    test('maps provider spellings onto the scale', () {
      expect(parseRating('TV-MA'), ContentRating.adult);
      expect(parseRating('18+'), ContentRating.adult);
      expect(parseRating('R'), ContentRating.adult);
      expect(parseRating('explicit'), ContentRating.adult);
      expect(parseRating('15'), ContentRating.mature);
      expect(parseRating('PG-13'), ContentRating.teen);
      expect(parseRating('TV-14'), ContentRating.teen);
      expect(parseRating('PG'), ContentRating.guidance);
      expect(parseRating('U'), ContentRating.all);
      expect(parseRating('TV-Y7'), ContentRating.all);
    });

    test('unrated and empty input are unrated', () {
      expect(parseRating(null), ContentRating.unrated);
      expect(parseRating(''), ContentRating.unrated);
      expect(parseRating('Not Rated'), ContentRating.unrated);
    });

    test('an unknown number still lands on the right side of the line', () {
      expect(parseRating('21'), ContentRating.adult);
      expect(parseRating('16'), ContentRating.mature);
      expect(parseRating('13'), ContentRating.teen);
    });

    test('exceeds compares restrictiveness', () {
      expect(ContentRating.adult.exceeds(ContentRating.teen), isTrue);
      expect(ContentRating.teen.exceeds(ContentRating.adult), isFalse);
      expect(ContentRating.teen.exceeds(ContentRating.teen), isFalse);
    });
  });

  group('LiveParental', () {
    test('a fresh install restricts nothing', () async {
      final p = LiveParental(storage: _MemoryStorage());
      await p.ensureLoaded();
      expect(p.isInactive, isTrue);
      expect(p.ceiling, ContentRating.adult);
      expect(p.isVisible(rating: ContentRating.adult), isTrue);
    });

    test('setPin then verifyPin unlocks the session', () async {
      final p = LiveParental(storage: _MemoryStorage());
      expect(await p.setPin('1234'), isTrue);
      expect(p.pinSet, isTrue);
      expect(p.unlocked, isFalse);

      expect(await p.verifyPin('0000'), isFalse);
      expect(p.unlocked, isFalse);

      expect(await p.verifyPin('1234'), isTrue);
      expect(p.unlocked, isTrue);
    });

    test('a short PIN is refused', () async {
      final p = LiveParental(storage: _MemoryStorage());
      expect(await p.setPin('12'), isFalse);
      expect(p.pinSet, isFalse);
    });

    test('changing the PIN requires the current one', () async {
      final storage = _MemoryStorage();
      final p = LiveParental(storage: storage);
      await p.setPin('1234');
      expect(await p.setPin('5678'), isFalse);
      expect(await p.setPin('5678', current: 'wrong'), isFalse);
      expect(await p.setPin('5678', current: '1234'), isTrue);
      expect(await p.verifyPin('5678'), isTrue);
    });

    test('the PIN is not stored in plaintext', () async {
      final storage = _MemoryStorage();
      final p = LiveParental(storage: storage);
      await p.setPin('1234');
      expect(storage.data.values, isNot(contains('1234')));
    });

    test('ceiling hides higher-rated content until unlocked', () async {
      final p = LiveParental(storage: _MemoryStorage());
      await p.setPin('1234');
      await p.setCeiling(ContentRating.guidance);
      p.lock();

      expect(p.isVisible(rating: ContentRating.all), isTrue);
      expect(p.isVisible(rating: ContentRating.guidance), isTrue);
      expect(p.isVisible(rating: ContentRating.teen), isFalse);
      expect(p.isVisible(rating: ContentRating.adult), isFalse);

      await p.verifyPin('1234');
      expect(p.isVisible(rating: ContentRating.adult), isTrue);
    });

    test('explicit hides apply regardless of rating', () async {
      final p = LiveParental(storage: _MemoryStorage());
      await p.setHidden('chan.1', true);
      expect(p.isVisible(rating: ContentRating.all, channelId: 'chan.1'), isFalse);
      expect(p.isVisible(rating: ContentRating.all, channelId: 'chan.2'), isTrue);

      await p.setHidden('chan.1', false);
      expect(p.isVisible(rating: ContentRating.all, channelId: 'chan.1'), isTrue);
    });

    test('filter drops the hidden items and keeps the rest', () async {
      final p = LiveParental(storage: _MemoryStorage());
      await p.setCeiling(ContentRating.teen);
      final kept = p.filter(
        ['kids', 'teen', 'adult'],
        ratingOf: (s) => switch (s) {
          'kids' => ContentRating.all,
          'teen' => ContentRating.teen,
          _ => ContentRating.adult,
        },
      );
      expect(kept, ['kids', 'teen']);
    });

    test('settings persist across instances', () async {
      final storage = _MemoryStorage();
      final p = LiveParental(storage: storage);
      await p.setPin('1234');
      await p.setCeiling(ContentRating.teen);
      await p.setHidden('chan.9', true);

      final reopened = LiveParental(storage: storage);
      await reopened.ensureLoaded();
      expect(reopened.pinSet, isTrue);
      expect(reopened.ceiling, ContentRating.teen);
      expect(reopened.hiddenChannels, contains('chan.9'));
    });

    test('clearPin removes the lock only with the right PIN', () async {
      final p = LiveParental(storage: _MemoryStorage());
      await p.setPin('1234');
      expect(await p.clearPin('nope'), isFalse);
      expect(p.pinSet, isTrue);
      expect(await p.clearPin('1234'), isTrue);
      expect(p.pinSet, isFalse);
    });
  });
}
