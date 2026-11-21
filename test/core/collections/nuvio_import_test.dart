import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/collections/nuvio_import.dart';

void main() {
  test('reads a bare array', () {
    final out = NuvioImport.parse(jsonEncode([
      {'title': 'A', 'type': 'movie', 'tmdbId': 1},
      {'name': 'B', 'year': 2020},
    ]));
    expect(out.single.items, hasLength(2));
    expect(out.single.items.first.id, '1');
    expect(out.single.items.last.year, 2020);
  });

  test('reads named collections', () {
    final out = NuvioImport.parse(jsonEncode({
      'collections': [
        {'name': 'Watchlist', 'items': [{'title': 'A'}]},
        {'items': [{'title': 'B'}]},
      ],
    }));
    expect(out, hasLength(2));
    expect(out.first.name, 'Watchlist');
    expect(out.last.name, 'Nuvio');
  });

  test('rejects a non-export', () {
    expect(() => NuvioImport.parse('"nope"'), throwsFormatException);
  });
}
