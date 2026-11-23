// Provider-extension handles (`browse:` listing rows, `live:` streams) are
// produced by JS providers like MovieBox. These are pure helpers that decide
// whether a tapped row is a title or an extension, and how to unwrap the
// provider's own spec from the app's scheme prefix.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/media_item.dart';
import 'package:watch_app/core/models/provider_info.dart';
import 'package:watch_app/core/repository/catalogue_repository.dart';
import 'package:watch_app/features/home/provider_browse_route.dart';

/// Nothing here is ever reached: the tap under test must be answered before a
/// player or a listing is opened.
class _NoopRepo implements CatalogueRepository {
  @override
  noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('isProviderExtensionUrl', () {
    test('recognises browse: and every live-sports handle', () {
      expect(isProviderExtensionUrl('browse:platform|Netflix'), isTrue);
      expect(
        isProviderExtensionUrl('browse:filter|type=/home/movieFilter'),
        isTrue,
      );
      // MovieBox / StreamFree.
      expect(isProviderExtensionUrl('live:123|https://cdn/x.m3u8'), isTrue);
      // CDNLive TV and TimStreams mint their own schemes; recognising only
      // `live:` mis-routed their fixtures to the detail page, which is where
      // "no source to play this video" came from.
      expect(isProviderExtensionUrl('ev:England @ Spain|...'), isTrue);
      expect(
        isProviderExtensionUrl('ts:{"feeds":[["HD","https://x"]]}'),
        isTrue,
      );
      // Nuvio carries the largest football feed, so its handle has to reach
      // the live resolver instead of the catalogue's detail route.
      expect(isProviderExtensionUrl('nuviotv:nuvio_sport_123'), isTrue);
    });

    test('leaves ordinary title urls alone', () {
      expect(isProviderExtensionUrl('mb:123|slug|2'), isFalse);
      expect(isProviderExtensionUrl('https://example.com/x'), isFalse);
      expect(isProviderExtensionUrl(''), isFalse);
    });
  });

  group('browseSpecOf', () {
    test('strips the browse: scheme the provider does not expect', () {
      expect(browseSpecOf('browse:platform|Netflix'), 'platform|Netflix');
      expect(
        browseSpecOf('browse:filter|type=/home/movieFilter&tabId=2'),
        'filter|type=/home/movieFilter&tabId=2',
      );
    });

    test('passes through a bare spec or an unknown url unchanged', () {
      expect(browseSpecOf('platform|Netflix'), 'platform|Netflix');
      expect(browseSpecOf('mb:123|slug|2'), 'mb:123|slug|2');
    });
  });

  group('openProviderExtensionItem', () {
    testWidgets(
      'a text-only fixture is refused with an explanation, not a player',
      (tester) async {
        final item = MediaItem(
          id: 't1',
          title: 'Text Only United',
          url: 'live:t1|',
          type: ProviderType.movie,
          sourceId: 'mb',
          liveBadge: 'LIVE',
          liveUnplayable: true,
        );

        late bool handled;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    handled = await openProviderExtensionItem(
                      context,
                      item,
                      repository: _NoopRepo(),
                    );
                  },
                  child: const Text('tap'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('tap'));
        await tester.pump();

        expect(handled, isTrue);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.textContaining('Text commentary'), findsOneWidget);
      },
    );
  });
}
