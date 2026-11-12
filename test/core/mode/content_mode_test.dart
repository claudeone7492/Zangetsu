import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/mode/content_mode.dart';
import 'package:watch_app/core/models/provider_info.dart';

void main() {
  test('labels and reading flags', () {
    expect(ContentMode.anime.label, 'Streaming'); // anime mode = all video
    expect(ContentMode.manga.label, 'Manga');
    expect(ContentMode.novel.label, 'Novel');
    expect(ContentMode.anime.isReading, isFalse);
    expect(ContentMode.manga.isReading, isTrue);
    expect(ContentMode.novel.isReading, isTrue);
  });

  test('every mode has its own icon', () {
    final icons = ContentMode.values.map((m) => m.icon).toSet();
    expect(icons.length, ContentMode.values.length);
  });

  test('mode ↔ provider type matching', () {
    // Anime mode owns both existing video types (anime + movie sources).
    expect(ContentMode.anime.matchesProvider(ProviderType.anime), isTrue);
    expect(ContentMode.anime.matchesProvider(ProviderType.movie), isTrue);
    expect(ContentMode.anime.matchesProvider(ProviderType.manga), isFalse);
    expect(ContentMode.manga.matchesProvider(ProviderType.manga), isTrue);
    expect(ContentMode.novel.matchesProvider(ProviderType.novel), isTrue);
    expect(ContentMode.manga.matchesProvider(ProviderType.novel), isFalse);
  });

  test('new ProviderType members round-trip by name', () {
    expect(ProviderType.values.byName('manga'), ProviderType.manga);
    expect(ProviderType.values.byName('novel'), ProviderType.novel);
  });

  group('sourceIdMatchesContentMode', () {
    test('prefix-encoded reading types need no resolver', () {
      expect(sourceIdMatchesContentMode('mihon:17', ContentMode.manga), isTrue);
      expect(sourceIdMatchesContentMode('lnr:9', ContentMode.novel), isTrue);
      expect(sourceIdMatchesContentMode('mihon:17', ContentMode.anime), isFalse);
      expect(sourceIdMatchesContentMode('lnr:9', ContentMode.manga), isFalse);
    });

    test('Mangayomi keys resolve from the encoded type', () {
      expect(
        sourceIdMatchesContentMode('mg:repo:0:0:17', ContentMode.manga),
        isTrue,
      );
      expect(
        sourceIdMatchesContentMode('mg:repo:1:1:23', ContentMode.anime),
        isTrue,
      );
      expect(
        sourceIdMatchesContentMode('mg:repo:2:0:31', ContentMode.novel),
        isTrue,
      );
    });

    test('an unknown id with no resolver is video (anime)', () {
      expect(
        sourceIdMatchesContentMode('legacy-js', ContentMode.anime),
        isTrue,
      );
      expect(
        sourceIdMatchesContentMode('legacy-js', ContentMode.manga),
        isFalse,
      );
    });

    // The bundled pack ships plain JS ids with no reading prefix, so their mode
    // comes from the manifest. Without the resolver they wrongly resolve as
    // anime — the "no sources installed" report on a fresh install.
    ProviderType? manifestType(String id) => switch (id) {
      'mangakakalot' || 'mangapill' => ProviderType.manga,
      'gutenberg' => ProviderType.novel,
      'framextv' || 'iptv' => ProviderType.movie,
      _ => null,
    };

    test('a plain JS manga source lands in manga, not anime', () {
      expect(
        sourceIdMatchesContentMode(
          'mangakakalot',
          ContentMode.manga,
          typeFromManifest: manifestType,
        ),
        isTrue,
      );
      expect(
        sourceIdMatchesContentMode(
          'mangakakalot',
          ContentMode.anime,
          typeFromManifest: manifestType,
        ),
        isFalse,
      );
    });

    test('a plain JS novel source lands in novel, not anime', () {
      expect(
        sourceIdMatchesContentMode(
          'gutenberg',
          ContentMode.novel,
          typeFromManifest: manifestType,
        ),
        isTrue,
      );
      expect(
        sourceIdMatchesContentMode(
          'gutenberg',
          ContentMode.anime,
          typeFromManifest: manifestType,
        ),
        isFalse,
      );
    });

    test('a video source is unaffected by the resolver', () {
      expect(
        sourceIdMatchesContentMode(
          'framextv',
          ContentMode.anime,
          typeFromManifest: manifestType,
        ),
        isTrue,
      );
      expect(
        sourceIdMatchesContentMode(
          'framextv',
          ContentMode.manga,
          typeFromManifest: manifestType,
        ),
        isFalse,
      );
    });
  });

  group('sourceInMode (prebuilt map)', () {
    const types = {
      'mangakakalot': ProviderType.manga,
      'gutenberg': ProviderType.novel,
      'framextv': ProviderType.movie,
    };

    test('classifies a whole pass from the prebuilt map', () {
      expect(sourceInMode('mangakakalot', ContentMode.manga, types), isTrue);
      expect(sourceInMode('gutenberg', ContentMode.novel, types), isTrue);
      expect(sourceInMode('framextv', ContentMode.anime, types), isTrue);
      expect(sourceInMode('framextv', ContentMode.manga, types), isFalse);
    });

    test('an id absent from the map is video', () {
      expect(sourceInMode('unknown', ContentMode.anime, types), isTrue);
      expect(sourceInMode('unknown', ContentMode.novel, types), isFalse);
    });
  });
}
