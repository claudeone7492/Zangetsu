import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/tmdb_browse.dart';

void main() {
  test('nicheOf recognises the names Hikari knows', () {
    expect(TmdbBrowse.nicheOf('HiAnime'), 'anime');
    expect(TmdbBrowse.nicheOf('Bollywood Hub'), 'hindi');
    expect(TmdbBrowse.nicheOf('KissKH'), 'kdrama');
    expect(TmdbBrowse.nicheOf('Wiflix'), 'french');
    expect(TmdbBrowse.nicheOf('Persian Movie'), 'persian');
    expect(TmdbBrowse.nicheOf('SuperStream'), 'general');
  });

  test('rowsFor rotates the niche pool by seed', () {
    final first = TmdbBrowse.rowsFor('Anime World', 0, take: 2);
    final second = TmdbBrowse.rowsFor('Anime World', 1, take: 2);
    expect(first, hasLength(2));
    expect(second, hasLength(2));
    expect(first.first.id, isNot(second.first.id));
  });

  test('rowsFor wraps a negative seed and clamps take', () {
    final rows = TmdbBrowse.rowsFor('Plain', -1, take: 99);
    expect(rows, hasLength(TmdbBrowse.generalRows.length));
    expect(TmdbBrowse.rowsFor('Plain', 0, take: 0), isEmpty);
  });

  test('catalog ids round-trip through rowFor', () {
    for (final row in TmdbBrowse.allRows) {
      expect(TmdbBrowse.isOurCatalog(row.catalogId), isTrue);
      expect(TmdbBrowse.rowFor(row.catalogId)?.id, row.id);
    }
    expect(TmdbBrowse.isOurCatalog('provider:123'), isFalse);
    expect(TmdbBrowse.rowFor('tmdb-nope'), isNull);
  });

  test('every row has an API path, and discover rows say how to sort', () {
    for (final row in TmdbBrowse.allRows) {
      expect(row.path, startsWith('/'), reason: row.id);
      if (row.path.startsWith('/discover/')) {
        expect(row.params['sort_by'], isNotNull, reason: row.id);
      }
    }
  });
}
