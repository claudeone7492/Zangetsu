import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/home_dedupe.dart';

void main() {
  test('builds a tmdb key from a bare id', () {
    expect(
      HomeDedupe.keyFor(id: '550', type: 'movie'),
      'tmdb:550:movie',
    );
    expect(
      HomeDedupe.keyFor(id: '1399', type: 'series'),
      'tmdb:1399:tv',
    );
  });

  test('builds imdb and prefixed keys', () {
    expect(HomeDedupe.keyFor(id: 'tt0137523', type: 'movie'), 'imdb:0137523');
    expect(
      HomeDedupe.keyFor(id: 'tmdb:550', type: 'movie'),
      'tmdb:550:movie',
    );
  });

  test('falls back to title and year', () {
    expect(
      HomeDedupe.keyFor(id: 'abc', type: 'movie', year: 1999, title: 'Fight Club'),
      't:fight club|1999|movie',
    );
  });

  test('collapses the same identity across engines', () {
    final rows = [
      ('tmdb:550', 'movie'),
      ('550', 'movie'),
      ('tt0137523', 'movie'),
      ('other', 'movie'),
    ];
    final out = HomeDedupe.dedupe(
      rows,
      key: (r) => HomeDedupe.keyFor(id: r.$1, type: r.$2),
    );
    expect(out, hasLength(3));
    expect(out.first.$1, 'tmdb:550');
  });
}
