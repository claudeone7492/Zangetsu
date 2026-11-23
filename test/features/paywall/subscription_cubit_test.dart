import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/features/paywall/subscription_cubit.dart';

import '../../support/fake_subscription_api.dart';

void main() {
  group('SubscriptionState pricing', () {
    SubscriptionState withPlan(SubscriptionPlan plan, {int discountPct = 15}) =>
        SubscriptionState(
          plans: [plan],
          selectedKey: plan.key,
          discountPct: discountPct,
        );

    test('launch offer takes the discount off the list price', () {
      final state = withPlan(samplePlans()[1]); // Standard, 200c
      expect(state.listCents, 200);
      expect(state.offerCents, 170); // 200 * 0.85 = 170
      expect(money(state.listCents), '\$2.00');
    });

    test('promo percentage stacks on top of the offer', () {
      var state = withPlan(samplePlans()[2]); // Premium, 599c
      expect(state.offerCents, 509); // 599 * 0.85 = 509.15 -> 509

      state = state.copyWith(
        promo: () => const PromoResult(
          code: 'NETFLIX85!',
          percentOff: 85,
          kind: 'percent',
        ),
      );
      // 509 * 0.15 = 76.35 -> 76
      expect(state.totalCents, 76);
      expect(state.isFreeAccess, isFalse);
    });

    test('a 100% promo is free access regardless of kind', () {
      final state = withPlan(samplePlans()[1]).copyWith(
        promo: () =>
            const PromoResult(code: '\$EDGES', percentOff: 100, kind: 'free'),
      );
      expect(state.totalCents, 0);
      expect(state.isFreeAccess, isTrue);
    });

    test('discount is configurable', () {
      final state = withPlan(samplePlans()[1], discountPct: 0);
      expect(state.offerCents, 200);
    });

    test('the card amount follows the promo, not just the launch offer', () {
      // The plan card renders payableCents; the summary renders totalCents.
      // They must be the same number, or a promo shows one price on the card
      // and charges another at checkout.
      final state = withPlan(samplePlans()[1], discountPct: 0).copyWith(
        promo: () =>
            const PromoResult(code: 'HALF', percentOff: 50, kind: 'percent'),
      );
      expect(state.listCents, 200);
      expect(state.payableCents, 100); // 200 * 0.5 = 100
      expect(state.payableCents, state.totalCents);
    });

    test('a free promo makes the card amount zero', () {
      final state = withPlan(samplePlans()[1]).copyWith(
        promo: () =>
            const PromoResult(code: 'FREEWATCH', percentOff: 100, kind: 'free'),
      );
      expect(state.payableCents, 0);
    });

    test('without a promo the card quotes the list price', () {
      final state = withPlan(samplePlans()[1], discountPct: 0);
      expect(state.payableCents, 200);
    });

    test('defaults to no discount until the server config loads', () {
      const state = SubscriptionState();
      expect(state.discountPct, 0);
      expect(state.offerCents, 0);
    });
  });

  group('SubscriptionConfig', () {
    test('parses the launch discount and currency', () {
      final config = SubscriptionConfig.fromMap(const {
        'launch_discount_pct': 15,
        'display_currency': 'NGN',
      });
      expect(config.launchDiscountPct, 15);
      expect(config.displayCurrency, 'NGN');
    });

    test('defaults to no discount and USD on a bad row', () {
      final config = SubscriptionConfig.fromMap(const {});
      expect(config.launchDiscountPct, 0);
      expect(config.displayCurrency, 'USD');
    });

    test('clamps an out-of-range discount', () {
      expect(
        SubscriptionConfig.fromMap(const {
          'launch_discount_pct': 250,
        }).launchDiscountPct,
        100,
      );
      expect(
        SubscriptionConfig.fromMap(const {
          'launch_discount_pct': -5,
        }).launchDiscountPct,
        0,
      );
    });
  });

  group('period labels', () {
    test('a 30-day plan reads as monthly', () {
      expect(periodSuffix(30), '/mo');
      expect(periodWord(30), 'monthly');
    });

    test('a 365-day plan reads as yearly', () {
      expect(periodSuffix(365), '/yr');
      expect(periodWord(365), 'yearly');
    });

    test('an odd period falls back to days', () {
      expect(periodSuffix(90), '/90d');
      expect(periodWord(90), 'every 90 days');
    });
  });

  group('SubscriptionCubit', () {
    test('load collapses to the single premium subscription', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: const DeviceIdentity(
          sessionId: 's1',
          isNew: true,
          trialUsed: false,
        ),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      expect(cubit.state.stage, PaywallStage.ready);
      // One product only: the standard tier at the standard price, shown as
      // "Premium subscription".
      expect(cubit.state.plans, hasLength(1));
      expect(cubit.state.selectedKey, 'stream_standard');
      expect(cubit.state.selected?.label, kPremiumPlanLabel);
      expect(cubit.state.selected?.priceCents, 200);
      expect(cubit.state.trialEligible, isTrue);
    });

    test(
      'the amount is whatever the server quotes, not a client constant',
      () async {
        final api = FakeSubscriptionApi(
          plansResult: const [
            SubscriptionPlan(
              key: 'stream_standard',
              label: 'Standard',
              priceCents: 350,
              periodDays: 30,
              trialDays: 14,
              features: ['Full HD'],
              sortOrder: 11,
            ),
          ],
        );
        final cubit = SubscriptionCubit(api);
        await cubit.load();

        expect(cubit.state.listCents, 350);
        expect(cubit.state.payableCents, 350);
        expect(money(cubit.state.listCents), '\$3.50');
      },
    );

    test('load reports error when no plans come back', () async {
      final api = FakeSubscriptionApi(plansResult: const []);
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      expect(cubit.state.stage, PaywallStage.error);
      expect(cubit.state.message, isNotNull);
    });

    test('load takes the launch discount from the server config', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        configResult: const SubscriptionConfig(launchDiscountPct: 20),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      expect(cubit.state.discountPct, 20);
      // Standard is 200c; 20% off -> 160c.
      expect(cubit.state.offerCents, 160);
    });

    test('unknown promo is rejected without clearing the plan', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        promoResult: null,
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();
      await cubit.applyPromo('nope');

      expect(cubit.state.promo, isNull);
      expect(cubit.state.promoRejected, isTrue);
      expect(cubit.state.message, contains('not valid'));
    });

    test('valid promo is applied', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        promoResult: const PromoResult(
          code: 'STARZ_85',
          percentOff: 85,
          kind: 'percent',
        ),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();
      await cubit.applyPromo('STARZ_85');

      expect(cubit.state.promo?.code, 'STARZ_85');
      expect(cubit.state.promoRejected, isFalse);
    });

    test('trial eligibility is false once the device used its trial', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: const DeviceIdentity(
          sessionId: 's1',
          isNew: false,
          trialUsed: true,
        ),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      expect(cubit.state.trialEligible, isFalse);
    });

    test('startTrial grants once and refreshes identity', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: const DeviceIdentity(
          sessionId: 's1',
          isNew: true,
          trialUsed: false,
        ),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      // After the trial the server reports it used; the second identify()
      // (inside startTrial) reflects that.
      api.identityResult = const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        planKey: 'stream_standard',
        status: 'active',
      );
      final ok = await cubit.startTrial();

      expect(ok, isTrue);
      expect(api.startTrialCalls, 1);
      expect(cubit.state.trialEligible, isFalse);
    });

    test(
      'startTrial surfaces a refusal when the trial was already used',
      () async {
        final api = FakeSubscriptionApi(
          plansResult: samplePlans(),
          identityResult: const DeviceIdentity(
            sessionId: 's1',
            isNew: false,
            trialUsed: false,
          ),
          trialResult: null,
        );
        final cubit = SubscriptionCubit(api);
        await cubit.load();

        final ok = await cubit.startTrial();

        expect(ok, isFalse);
        expect(cubit.state.stage, PaywallStage.ready);
        expect(cubit.state.message, contains('already used'));
      },
    );

    test(
      'commitPromo records the redemption with list and final amounts',
      () async {
        final api = FakeSubscriptionApi(
          plansResult: samplePlans(),
          configResult: const SubscriptionConfig(launchDiscountPct: 15),
          identityResult: const DeviceIdentity(
            sessionId: 's1',
            isNew: true,
            trialUsed: false,
          ),
          promoResult: const PromoResult(
            code: 'PRIME85!',
            percentOff: 85,
            kind: 'percent',
          ),
        );
        final cubit = SubscriptionCubit(api);
        await cubit.load();
        await cubit.applyPromo('PRIME85!');
        await cubit.commitPromo();

        expect(api.redemptions, hasLength(1));
        expect(api.redemptions.single['code'], 'PRIME85!');
        expect(api.redemptions.single['planKey'], 'stream_standard');
        // List 200c, 15% launch offer -> 170c, then 85% off -> 26c. The recorded
        // pair is what the redemption is checked against, so it has to be the
        // same chain the server charges.
        expect(api.redemptions.single['before'], 200);
        expect(api.redemptions.single['after'], 26);
      },
    );
  });

  group('SubscriptionCubit checkout', () {
    test('beginCheckout sends the selected plan and current promo', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: const DeviceIdentity(
          sessionId: 's1',
          isNew: false,
          trialUsed: true,
        ),
        promoResult: const PromoResult(
          code: 'STARZ_85',
          percentOff: 85,
          kind: 'percent',
        ),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();
      await cubit.applyPromo('STARZ_85');

      final result = await cubit.beginCheckout();

      expect(result?.ok, isTrue);
      expect(api.startCheckoutCalls, 1);
      expect(api.lastCheckoutPlan, 'stream_standard');
      expect(api.lastCheckoutPromo, 'STARZ_85');
      expect(cubit.state.stage, PaywallStage.ready);
    });

    test('beginCheckout surfaces a server failure as a message', () async {
      final api =
          FakeSubscriptionApi(
              plansResult: samplePlans(),
              identityResult: const DeviceIdentity(
                sessionId: 's1',
                isNew: false,
                trialUsed: true,
              ),
            )
            ..checkoutResult = const CheckoutResult(
              ok: false,
              free: false,
              error: 'korapay_init_failed',
            );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      final result = await cubit.beginCheckout();

      expect(result?.ok, isFalse);
      expect(cubit.state.stage, PaywallStage.ready);
      expect(cubit.state.promoRejected, isTrue);
      expect(cubit.state.message, contains('Could not start checkout'));
    });

    test('a free checkout needs no URL', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: const DeviceIdentity(
          sessionId: 's1',
          isNew: false,
          trialUsed: true,
        ),
      )..checkoutResult = const CheckoutResult(ok: true, free: true);
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      final result = await cubit.beginCheckout();

      expect(result?.ok, isTrue);
      expect(result?.free, isTrue);
      expect(result?.checkoutUrl, isNull);
    });

    test('refreshEntitlement re-reads the server verdict', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: const DeviceIdentity(
          sessionId: 's1',
          isNew: false,
          trialUsed: true,
          entitled: false,
        ),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();
      expect(cubit.state.identity?.entitled, isFalse);

      // The webhook settled the charge while the WebView was open.
      api.identityResult = const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        planKey: 'stream_standard',
        status: 'active',
        entitled: true,
        showPaywall: false,
        daysLeft: 30,
      );
      final entitled = await cubit.refreshEntitlement();

      expect(entitled, isTrue);
      expect(cubit.state.identity?.daysLeft, 30);
    });
  });

  group('Device seats', () {
    test('joining a plan re-reads the identity and unlocks the card', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        linkResult: SeatResult.fromMap({
          'ok': true,
          'plan_key': 'stream_standard',
          'seats_used': 2,
          'seat_limit': 2,
        }),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      final result = await cubit.linkDevice('abcd2345');

      expect(result?.ok, isTrue);
      expect(api.linkedCodes, ['abcd2345']);
      // The seat's entitlement comes from the owner's plan, so the card must
      // reflect the re-read identity rather than assume the join worked.
      expect(cubit.state.identity?.entitled, isTrue);
      expect(cubit.state.stage, PaywallStage.ready);
    });

    test('a refused code leaves the device where it was', () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        linkResult: SeatResult.fromMap({'ok': false, 'error': 'no_seats'}),
      );
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      final result = await cubit.linkDevice('ABCD2345');

      expect(result?.ok, isFalse);
      expect(result?.message, contains('already in use'));
      expect(cubit.state.identity?.entitled ?? false, isFalse);
      expect(cubit.state.stage, PaywallStage.ready);
    });
  });
}
