// Provider-extension handles (`browse:` listing rows, `live:` streams) are
// produced by JS providers like MovieBox. These are pure helpers that decide
// whether a tapped row is a title or an extension, and how to unwrap the
// provider's own spec from the app's scheme prefix.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/home/provider_browse_route.dart';

void main() {
  group('isProviderExtensionUrl', () {
    test('recognises browse: and live: handles', () {
      expect(isProviderExtensionUrl('browse:platform|Netflix'), isTrue);
      expect(isProviderExtensionUrl('browse:filter|type=/home/movieFilter'), isTrue);
      expect(isProviderExtensionUrl('live:123|https://cdn/x.m3u8'), isTrue);
    });

    test('leaves ordinary title urls alone', () {
      expect(isProviderExtensionUrl('mb:123|slug|2'), isFalse);
      expect(isProviderExtensionUrl('https://example.com/x'), isFalse);
      expect(isProviderExtensionUrl(''), isFalse);
    });
  });

  group('browseSpecOf', () {
    test('strips the browse: scheme the provider does not expect', () {
      expect(
        browseSpecOf('browse:platform|Netflix'),
        'platform|Netflix',
      );
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
}
