import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/subscription/entitlement_cache.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/core/subscription/subscription_repository.dart';
import 'package:watch_app/core/subscription/trial_countdown.dart';
import 'package:watch_app/features/paywall/subscription_gate.dart';

import '../../support/fake_subscription_api.dart';

/// The gate is what keeps Home and the profile picker hidden until the device
/// is entitled, so these tests pin its decisions: allow an entitled device,
/// allow an offline device only with a still-running cached verdict, and hold
/// an unentitled or unknown device at the paywall.
void main() {
  final sl = GetIt.instance;

  setUp(() {
    sl.reset();
    EntitlementCache.debugSet(null);
    TrialCountdownController.instance.debugReset();
  });
  tearDown(() {
    sl.reset();
    EntitlementCache.debugSet(null);
    TrialCountdownController.instance.debugReset();
  });

  Widget host(FakeSubscriptionApi api) {
    if (!sl.isRegistered<SubscriptionApi>()) {
      sl.registerLazySingleton<SubscriptionApi>(() => api);
    }
    return MaterialApp(
      home: SubscriptionGate(
        api: api,
        child: const Scaffold(body: Text('HOME')),
      ),
    );
  }

  /// Pumps a few frames so the post-frame entitlement check, the modal route
  /// animation and the paywall's async load all land. Deliberately not
  /// [pumpAndSettle]: the loading spinner never settles. The 2.4s of fake time
  /// is enough for GeoPricing's 800ms timezone lookup to time out in tests.
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('an entitled device goes straight to the app', (t) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        status: 'active',
        entitled: true,
        showPaywall: false,
      ),
    );

    await t.pumpWidget(host(api));
    await settle(t);

    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a server that cannot be reached fails closed with no cache', (
    t,
  ) async {
    final api = _ThrowingApi();

    await t.pumpWidget(host(api));
    await settle(t);

    // Going offline must not bypass the paywall.
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('an offline device with a running cached verdict gets in', (
    t,
  ) async {
    final api = _ThrowingApi();
    await EntitlementCache.save(
      DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        status: 'active',
        entitled: true,
        showPaywall: false,
        periodEnd: DateTime.now().add(const Duration(days: 7)),
      ),
    );

    await t.pumpWidget(host(api));
    await settle(t);

    // A paying viewer is not locked out by a network blip while their period
    // is still running.
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('an offline device whose cached trial ended is held', (t) async {
    final api = _ThrowingApi();
    await EntitlementCache.save(
      DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        status: 'active',
        entitled: true,
        showPaywall: false,
        periodEnd: DateTime.now().subtract(const Duration(days: 1)),
      ),
    );

    await t.pumpWidget(host(api));
    await settle(t);

    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('an unentitled device is held at the paywall', (t) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        daysLeft: 0,
        showPaywall: true,
      ),
    );
    // The paywall builds its cubit from GetIt, so register the same fake.
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host(api));
    await settle(t);

    // Home is not reachable; the subscription card is on screen instead.
    expect(find.text('HOME'), findsNothing);
    expect(find.text(kPremiumPlanLabel), findsOneWidget);
    expect(find.byKey(const ValueKey('paywall-close')), findsNothing);

    // The card is modal: a barrier tap must not reveal Home.
    await t.tapAt(const Offset(8, 8));
    await settle(t);
    expect(find.text('HOME'), findsNothing);
    expect(find.text(kPremiumPlanLabel), findsOneWidget);
  });

  testWidgets('the card comes up before onboarding, not after it', (t) async {
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: const DeviceIdentity(
        sessionId: 's1',
        isNew: true,
        trialUsed: false,
        showPaywall: true,
        trialAvailable: true,
      ),
    );
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    // The gate wraps onboarding too, so the card is the first thing after the
    // splash on a device that has never paid.
    await t.pumpWidget(
      MaterialApp(
        home: SubscriptionGate(
          api: api,
          child: const Scaffold(body: Text('ONBOARDING')),
        ),
      ),
    );
    await settle(t);

    expect(find.text('ONBOARDING'), findsNothing);
    expect(find.text(kPremiumPlanLabel), findsOneWidget);
  });

  testWidgets('a second device joins with a code and the gate opens', (
    t,
  ) async {
    final api =
        FakeSubscriptionApi(
            plansResult: samplePlans(),
            identityResult: const DeviceIdentity(
              sessionId: 's1',
              isNew: true,
              trialUsed: false,
              showPaywall: true,
              trialAvailable: true,
            ),
          )
          ..linkResult = SeatResult.fromMap({
            'ok': true,
            'plan_key': 'stream_standard',
            'seats_used': 2,
            'seat_limit': 2,
          });
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host(api));
    await settle(t);
    expect(find.text('HOME'), findsNothing);

    final link = find.text('On someone\'s plan? Enter their code');
    await t.ensureVisible(link);
    await t.tap(link);
    await settle(t);

    await t.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'abcd2345',
    );
    await t.pump();
    await t.tap(find.text('Join'));
    await settle(t);

    // The code is normalised before it leaves the device, and the seat's
    // entitlement comes from the owner's plan, so the gate opens.
    expect(api.linkedCodes, ['ABCD2345']);
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('a subscription found in the database lets a reinstall in', (
    t,
  ) async {
    // What `identify_device` returns for a device whose row already exists —
    // the reinstall case, once the fingerprint survives the uninstall. The
    // trial clock comes back with the same remaining time, not a fresh 14
    // days.
    final now = DateTime.now().toUtc();
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        planKey: 'stream_standard',
        status: 'active',
        entitled: true,
        showPaywall: false,
        daysLeft: 14,
        isTrial: true,
        periodEnd: now.add(const Duration(days: 3, hours: 4)),
        serverNow: now,
      ),
    );

    await t.pumpWidget(host(api));
    await settle(t);

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text(kPremiumPlanLabel), findsNothing);
    expect(TrialCountdownController.instance.countdown.value, isNotNull);
  });

  testWidgets(
    'a running trial shows the countdown, then the paywall at expiry',
    (t) async {
      var clock = DateTime.now().toUtc();
      TrialCountdownController.instance.debugNow = () => clock;
      final api = FakeSubscriptionApi(
        plansResult: samplePlans(),
        identityResult: DeviceIdentity(
          sessionId: 's1',
          isNew: false,
          trialUsed: true,
          status: 'active',
          entitled: true,
          showPaywall: false,
          isTrial: true,
          periodEnd: clock.add(const Duration(seconds: 1)),
          serverNow: clock,
        ),
      );
      sl.registerLazySingleton<SubscriptionApi>(() => api);

      await t.pumpWidget(host(api));
      await t.pump();
      expect(find.text('HOME'), findsOneWidget);
      expect(TrialCountdownController.instance.countdown.value, isNotNull);

      // The one-second trial runs out while the app is open. The gate must not
      // wait for a relaunch or a network round trip to put the card back up.
      clock = clock.add(const Duration(seconds: 2));
      await settle(t);
      expect(find.text('HOME'), findsNothing);
      expect(find.text(kPremiumPlanLabel), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-close')), findsNothing);
    },
  );
}

/// An api with no server verdict, standing in for an offline device. The
/// paywall loads plans through the same api, so this returns null rather than
/// throwing; the gate's own exception path is covered by [deviceEntitled].
class _ThrowingApi extends FakeSubscriptionApi {
  @override
  Future<DeviceIdentity?> identify() async => null;
}
