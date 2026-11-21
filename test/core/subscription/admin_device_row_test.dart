import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';

/// The admin Devices table has to answer "who is sharing with whom" from one
/// column, because that is the question support actually asks.
void main() {
  AdminDeviceRow row(Map<String, dynamic> extra) => AdminDeviceRow.fromMap({
    'fingerprint': 'abcdef0123456789',
    'status': 'active',
    ...extra,
  });

  group('AdminDeviceRow sharing', () {
    test('a device paying for itself reads as unshared', () {
      expect(row(const {}).sharingLabel, '—');
    });

    test('an owner with seats reads as the owner of them', () {
      expect(row(const {'seats': 2}).sharingLabel, 'owner of 2');
    });

    test('a seat points at the fingerprint it rides on', () {
      final seat = row(const {'seat_owner': 'fedcba9876543210', 'seats': 2});
      expect(seat.sharingLabel, 'on fedcba…3210');
    });

    test('a server without the seat columns still renders', () {
      final legacy = row(const {});
      expect(legacy.seatOwner, isNull);
      expect(legacy.seats, 1);
    });
  });
}
