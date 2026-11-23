import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/announce/announcement.dart';

void main() {
  group('Announcement payload', () {
    test('a daily-pick deep link survives the Hive round-trip', () {
      const a = Announcement(
        id: 'daily_morning_2026-01-01',
        title: 'Trending movies',
        body: 'Dune: Part Two',
        payload: 'daily:morning:eyJzIjoibW92aWVib3gifQ==',
      );
      final restored = Announcement.fromMap(a.toMap());
      expect(restored.payload, a.payload);
    });

    test('a server announcement can carry a payload', () {
      final a = Announcement.fromJson({
        'id': 'n1',
        'title': 'New',
        'body': 'Body',
        'payload': 'daily:evening:abc',
      });
      expect(a?.payload, 'daily:evening:abc');
    });

    test('a plain announcement has no payload', () {
      final a = Announcement.fromJson({'id': 'n1', 'title': 'New'});
      expect(a?.payload, isNull);
    });
  });
}
