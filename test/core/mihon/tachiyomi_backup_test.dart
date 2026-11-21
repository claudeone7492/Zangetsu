import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/mihon/tachiyomi_backup.dart';

void main() {
  test('reads the current backup shape', () {
    final out = TachiyomiBackup.parse(jsonEncode({
      'backupManga': [
        {'manga': {'title': 'One Piece', 'url': '/one-piece', 'source': '1'}},
        {'manga': {'title': 'Berserk', 'url': '/berserk'}},
      ],
    }));
    expect(out, hasLength(2));
    expect(out.first.title, 'One Piece');
    expect(out.first.sourceId, '1');
  });

  test('reads the older flat shape', () {
    final out = TachiyomiBackup.parse(jsonEncode({
      'manga': [{'title': 'Berserk'}],
    }));
    expect(out.single.title, 'Berserk');
  });

  test('rejects a non-backup', () {
    expect(() => TachiyomiBackup.parse('[]'), throwsFormatException);
  });
}
