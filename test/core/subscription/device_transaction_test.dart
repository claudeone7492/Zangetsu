import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';

void main() {
  test('maps a device_transactions row', () {
    final tx = DeviceTransaction.fromMap({
      'reference': 'sx_sub_streamstandard_abc123',
      'product_type': 'subscription_stream',
      'plan_key': 'stream_standard',
      'plan_label': 'Standard',
      'amount_cents': 200,
      'currency': 'USD',
      'status': 'completed',
      'promo_code': null,
      'created_at': '2026-11-23T09:30:00Z',
      'completed_at': '2026-11-23T09:31:00Z',
      'period_end': '2026-12-23T09:31:00Z',
    });

    expect(tx, isNotNull);
    expect(tx!.reference, 'sx_sub_streamstandard_abc123');
    expect(tx.title, kPremiumPlanLabel);
    expect(tx.amountCents, 200);
    expect(tx.completed, isTrue);
    expect(tx.createdAt, DateTime.utc(2026, 11, 23, 9, 30));
  });

  test('ignores a row without a reference', () {
    expect(DeviceTransaction.fromMap({'amount_cents': 200}), isNull);
    expect(
      DeviceTransaction.fromMap({'reference': '', 'amount_cents': 200}),
      isNull,
    );
  });
}
