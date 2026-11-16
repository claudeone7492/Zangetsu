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
      final state = withPlan(samplePlans()[1]); // Standard, 349c
      expect(state.listCents, 349);
      expect(state.offerCents, 297); // 349 * 0.85 = 296.65 -> 297
      expect(money(state.listCents), '\$3.49');
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
        promo: () => const PromoResult(
          code: '\$EDGES',
          percentOff: 100,
          kind: 'free',
        ),
      );
      expect(state.totalCents, 0);
      expect(state.isFreeAccess, isTrue);
    });

    test('discount is configurable', () {
      final state = withPlan(samplePlans()[1], discountPct: 0);
      expect(state.offerCents, 349);
    });
  });

  group('SubscriptionCubit', () {
    test('load defaults to the middle tier and becomes ready', () async {
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
      expect(cubit.state.selectedKey, 'stream_standard');
      expect(cubit.state.trialEligible, isTrue);
    });

    test('load reports error when no plans come back', () async {
      final api = FakeSubscriptionApi(plansResult: const []);
      final cubit = SubscriptionCubit(api);
      await cubit.load();

      expect(cubit.state.stage, PaywallStage.error);
      expect(cubit.state.message, isNotNull);
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

    test('startTrial surfaces a refusal when the trial was already used',
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
    });

    test('commitPromo records the redemption with list and final amounts',
        () async {
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
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
      cubit.selectPlan('stream_premium');
      await cubit.applyPromo('PRIME85!');
      await cubit.commitPromo();

      expect(api.redemptions, hasLength(1));
      expect(api.redemptions.single['code'], 'PRIME85!');
      expect(api.redemptions.single['planKey'], 'stream_premium');
      expect(api.redemptions.single['before'], 599);
      expect(api.redemptions.single['after'], 76);
    });
  });
}
