import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/live/flat_json_scanner.dart';

void main() {
  List<Map<String, String>> scan(String json) {
    final out = <Map<String, String>>[];
    final scanner = FlatJsonScanner(out.add);
    final bytes = utf8.encode(json);
    for (final byte in bytes) {
      scanner.feed([byte]);
    }
    scanner.finish();
    return out;
  }

  test('reads a bare array of objects, one byte at a time', () {
    final rows = scan(
      '[{"stream_id":1,"name":"One"},{"stream_id":2,"name":"Two"}]',
    );
    expect(rows, hasLength(2));
    expect(rows.first['name'], 'One');
    expect(rows.first['stream_id'], '1');
    expect(rows.last['stream_id'], '2');
  });

  test('reads an object wrapping the array, the way panels answer', () {
    final rows = scan('{"available_channels":[{"name":"A"},{"name":"B"}]}');
    expect(rows.map((r) => r['name']), ['A', 'B']);
  });

  test('keeps nested objects out of the flat map', () {
    final rows = scan('[{"name":"A","meta":{"x":1,"y":[1,2]}}]');
    expect(rows, hasLength(1));
    expect(rows.single['name'], 'A');
    expect(rows.single.containsKey('meta'), isFalse);
  });

  test('handles escapes and unicode split across chunks', () {
    final rows = scan('[{"name":"Caf\\u00e9 \\"Live\\""}]');
    expect(rows.single['name'], 'Café "Live"');
  });

  test('skips booleans, nulls and nested arrays as values', () {
    final rows = scan(
      '[{"name":"A","is_adult":false,"nothing":null,"ids":[1,2,3]}]',
    );
    expect(rows.single['name'], 'A');
    expect(rows.single['is_adult'], 'false');
    expect(rows.single.containsKey('nothing'), isFalse);
    expect(rows.single.containsKey('ids'), isFalse);
  });

  test('a truncated answer throws rather than reporting a short list', () {
    final out = <Map<String, String>>[];
    final scanner = FlatJsonScanner(out.add);
    scanner.feed(utf8.encode('[{"name":"A"},{"name":"B"'));
    expect(scanner.finish, throwsStateError);
    expect(out, hasLength(1));
  });
}
