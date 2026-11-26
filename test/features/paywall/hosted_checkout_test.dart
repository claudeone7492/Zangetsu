import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/paywall/hosted_checkout.dart';

void main() {
  const returnUrl = 'https://edgesenterprise.com/payment/return';
  const legacy = 'https://zangetsu.online/payment/success';

  CheckoutOutcome? outcome(String url) =>
      checkoutOutcomeForUrl(url, returnUrls: const [returnUrl, legacy]);

  group('checkoutOutcomeForUrl', () {
    test('a successful Flutterwave return is paid', () {
      expect(
        outcome('$returnUrl?status=successful&tx_ref=ZAN-1&transaction_id=42'),
        CheckoutOutcome.paid,
      );
    });

    test('a completed return is paid', () {
      expect(
        outcome('$returnUrl?status=completed&tx_ref=ZAN-2'),
        CheckoutOutcome.paid,
      );
    });

    test('a KoraPay return without a status is paid', () {
      expect(outcome('$returnUrl?reference=ZAN-3'), CheckoutOutcome.paid);
    });

    test('a failed charge on the return URL is cancelled', () {
      expect(
        outcome('$returnUrl?status=failed&tx_ref=ZAN-4'),
        CheckoutOutcome.cancelled,
      );
    });

    test('a bank transfer still processing is pending', () {
      expect(
        outcome('$returnUrl?status=pending&tx_ref=ZAN-5'),
        CheckoutOutcome.pending,
      );
    });

    test('a trailing slash still matches', () {
      expect(outcome('$returnUrl/?status=successful'), CheckoutOutcome.paid);
    });

    test('a lookalike path is not a return', () {
      expect(outcome('${returnUrl}ful?status=successful'), isNull);
    });

    test('another host is not a return', () {
      expect(
        outcome('https://evil.example/payment/return?status=successful'),
        isNull,
      );
    });

    test('a custom scheme is not a return', () {
      expect(outcome('zangetsu://payment/return?status=successful'), isNull);
    });

    test('the legacy callback is still caught during rollout', () {
      expect(outcome('$legacy?reference=ZAN-LEGACY'), CheckoutOutcome.paid);
    });
  });
}
