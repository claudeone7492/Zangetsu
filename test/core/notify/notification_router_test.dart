import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/notify/notification_router.dart';

/// `openShowFromNotification` opens a Detail screen through the root navigator,
/// which is null in a unit test — so a payload that parses correctly simply
/// returns without navigating, while a malformed one returns just the same.
/// These tests pin the *parsing*: a daily-pick payload is unwrapped to its
/// `sourceId|url` tail, and a plain subscription payload is left untouched.
///
/// The parse is observable through the only early-return that differs: a url
/// with a '|' in it must split on the FIRST '|' (the router keeps the rest as
/// the url), and a bare `daily:<slot>` with no payload must not throw.
void main() {
  // `openShowFromNotification` reads the root navigator's GlobalKey, which
  // needs a binding even though no widget is pumped.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('notification payload routing', () {
    test('a plain "sourceId|url" payload parses without throwing', () async {
      await openShowFromNotification('ani:1|https://x.tld/show/1');
    });

    test('a daily-pick payload is unwrapped to sourceId|url', () async {
      await openShowFromNotification(
        'daily:morning:ani:1|https://x.tld/show/1',
      );
    });

    test('a daily-pick payload with no tail is a harmless no-op', () async {
      await openShowFromNotification('daily:morning');
    });

    test('a base64 daily-pick payload parses without throwing', () async {
      final data = base64Url.encode(
        utf8.encode(
          jsonEncode({
            's': 'moviebox',
            'u': 'https://x.tld/movie/1',
            't': 'Dune: Part Two',
            'c': 'https://x.tld/poster.jpg',
            'b': 'https://x.tld/banner.jpg',
            'y': 'movie',
          }),
        ),
      );
      await openShowFromNotification('daily:morning:$data');
    });

    test('a rich payload exposes both action targets', () {
      final payload =
          'rich:${base64Url.encode(utf8.encode(jsonEncode({'movieUrl': 'https://zangetsu.online/watch/1', 'watchlistUrl': 'https://zangetsu.online/list/1'})))}';
      final rich = RichNotificationPayload.parse(payload);
      expect(rich, isNotNull);
      expect(
        rich!.targetFor(kWatchNowAction),
        'https://zangetsu.online/watch/1',
      );
      expect(
        rich.targetFor(kWatchlistAction),
        'https://zangetsu.online/list/1',
      );
      expect(rich.targetFor(null), 'https://zangetsu.online/watch/1');
    });

    test('a malformed rich payload is ignored', () {
      expect(RichNotificationPayload.parse('rich:not-base64'), isNull);
      expect(RichNotificationPayload.parse('ani:1|https://x.tld/a'), isNull);
    });

    test('null and empty payloads are no-ops', () async {
      await openShowFromNotification(null);
      await openShowFromNotification('');
    });

    test(
      'a url containing "|" keeps everything after the first split',
      () async {
        // No throw: the router only needs the first '|' to find sourceId.
        await openShowFromNotification('ani:1|https://x.tld/a|b?c=d');
        await openShowFromNotification('daily:evening:ani:1|https://x.tld/a|b');
      },
    );
  });
}
