import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/geo_pricing.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/features/paywall/paywall_screen.dart';
import 'package:watch_app/features/paywall/subscription_cubit.dart';

import '../../support/fake_subscription_api.dart';

/// The gate must read as an invitation, not a system state: a locked viewer
/// should see a warm pitch, what they get, and the promo discount they hold.
void main() {
  Widget host(SubscriptionCubit cubit, {String? reason}) => MaterialApp(
    home: Scaffold(
      body: BlocProvider.value(
        value: cubit,
        child: PaywallSheet(reason: reason),
      ),
    ),
  );

  /// [SubscriptionCubit.load] resolves the device currency through a platform
  /// channel and can fetch a live FX rate. Both are real I/O, so they must run
  /// outside the widget tester's fake-async zone — otherwise the channel reply
  /// never lands and the await never returns.
  Future<SubscriptionCubit> loaded(
    FakeSubscriptionApi api,
    WidgetTester t,
  ) async {
    final cubit = SubscriptionCubit(api);
    await t.runAsync(cubit.load);
    return cubit;
  }

  testWidgets('shows the warm hero and the reason it was opened', (t) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: const DeviceIdentity(
        sessionId: 's1',
        isNew: true,
        trialUsed: false,
        trialAvailable: true,
        showPaywall: true,
      ),
    );
    final cubit = await loaded(api, t);

    await t.pumpWidget(
      host(cubit, reason: 'Keep watching — this one is a Zangetsu exclusive'),
    );
    await t.pump();

    expect(
      find.text('Keep watching — this one is a Zangetsu exclusive'),
      findsOneWidget,
    );
    // A first-time device is pitched the trial.
    expect(find.textContaining('14-day free trial'), findsOneWidget);
    // ...and the CTA itself offers to start it.
    expect(find.text('Start 14 days free trial'), findsOneWidget);
    // The internal state word must never reach the screen.
    expect(find.textContaining('unentitled'), findsNothing);
    expect(find.textContaining('entitled'), findsNothing);
  });

  testWidgets('an expired viewer sees the trial offer, not a state word', (
    t,
  ) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        daysLeft: 3,
        showPaywall: true,
      ),
    );
    final cubit = await loaded(api, t);

    await t.pumpWidget(host(cubit));
    await t.pump();

    expect(find.textContaining('Keep watching every drama'), findsOneWidget);
    expect(find.textContaining('access ended 3 days ago'), findsOneWidget);
    expect(find.textContaining('unentitled'), findsNothing);
  });

  testWidgets('rejects an unknown promo and then applies a real one', (
    t,
  ) async {
    final api = FakeSubscriptionApi(plansResult: samplePlans());
    final cubit = await loaded(api, t);

    await t.pumpWidget(host(cubit));
    await t.pump();

    // No promo configured on the fake yet, so it is rejected plainly.
    await t.runAsync(() => cubit.applyPromo('EDGE50'));
    await t.pump();
    expect(find.textContaining('not valid'), findsOneWidget);

    // A real promo stacks on the launch offer, and both savings appear.
    api.promoResult = const PromoResult(
      code: 'EDGE50',
      percentOff: 50,
      kind: 'percent',
    );
    await t.runAsync(() => cubit.applyPromo('EDGE50'));
    await t.pump();

    expect(find.textContaining('50% off applied'), findsOneWidget);
    expect(find.text('Promo · 50% off'), findsOneWidget);
    expect(find.text('You save'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    // One product: standard list 349c, no launch discount, then 50% off -> 175c.
    expect(find.text('\$1.75'), findsOneWidget);
    // The promo discount and the "You save" row both read 174c.
    expect(find.text('\$1.74'), findsWidgets);
  });

  testWidgets('the plan card price drops when a promo is applied', (t) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      promoResult: const PromoResult(
        code: 'HALF',
        percentOff: 50,
        kind: 'percent',
      ),
    );
    final cubit = await loaded(api, t);

    // The card quotes the amount and its billing period in one RichText, e.g.
    // "$1.75/mo". Matching that exact string pins the assertion to the card:
    // the summary rows render bare amounts, and a bare-amount finder would also
    // match the Total row and pass even with the card left stale.
    Finder cardPrice(String amount) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText() == '$amount/mo',
      description: 'plan card price $amount',
    );

    await t.pumpWidget(host(cubit));
    await t.pump();

    // Before the promo the card quotes the full list price.
    expect(cardPrice('\$3.49'), findsOneWidget);
    expect(cardPrice('\$1.75'), findsNothing);

    await t.runAsync(() => cubit.applyPromo('HALF'));
    await t.pump();

    // After it, the card headline is the discounted amount — the same figure
    // the summary's Total row quotes.
    expect(cardPrice('\$1.75'), findsOneWidget);
    expect(cardPrice('\$3.49'), findsNothing);
  });

  testWidgets('a free promo turns the CTA into free activation', (t) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      promoResult: const PromoResult(
        code: 'FREEWATCH',
        percentOff: 100,
        kind: 'free',
      ),
    );
    final cubit = await loaded(api, t);

    await t.pumpWidget(host(cubit));
    await t.pump();

    await t.runAsync(() => cubit.applyPromo('FREEWATCH'));
    await t.pump();

    expect(find.text('Activate free access'), findsOneWidget);
    expect(find.text('\$0.00'), findsWidgets);
  });

  testWidgets('shows the approximate local price on the plan card', (
    t,
  ) async {
    final api = FakeSubscriptionApi(plansResult: samplePlans());
    final cubit = await loaded(api, t);
    cubit.emit(
      cubit.state.copyWith(
        geoQuote: const GeoQuote(currency: 'NGN', rate: 1352.11),
      ),
    );

    await t.pumpWidget(host(cubit));
    await t.pump();

    // Standard list 349c at the current rate -> $3.49 -> ~N4,719.
    expect(find.textContaining('₦4,719'), findsWidgets);
  });

  testWidgets('shows a single plan labelled "Premium subscription"', (
    t,
  ) async {
    final api = FakeSubscriptionApi(plansResult: samplePlans());
    final cubit = await loaded(api, t);

    await t.pumpWidget(host(cubit));
    await t.pump();

    // One card, labelled as the premium subscription — no basic/standard tiers.
    expect(find.text(kPremiumPlanLabel), findsOneWidget);
    expect(find.text('Standard'), findsNothing);
    expect(find.text('Basic (with ads)'), findsNothing);
    expect(find.text('Premium'), findsNothing);
    // The price shown is the standard list price, not a discounted offer
    // (it appears on the plan card and again in the summary "Price" row).
    expect(find.text('\$3.49'), findsWidgets);
    expect(find.textContaining('Launch offer'), findsNothing);
  });
}
