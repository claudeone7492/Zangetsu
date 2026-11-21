import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/core/subscription/subscription_repository.dart';
import 'package:watch_app/features/paywall/subscription_gate.dart';

import '../../support/fake_subscription_api.dart';

/// The gate is what keeps Home and the profile picker hidden until the device
/// is entitled, so these tests pin its three decisions: allow an entitled
/// device, allow when the server cannot be reached (fail open), and hold an
/// unentitled device at the paywall.
void main() {
  final sl = GetIt.instance;

  setUp(() => sl.reset());
  tearDown(() => sl.reset());

  Widget host(FakeSubscriptionApi api) => MaterialApp(
    home: SubscriptionGate(
      api: api,
      child: const Scaffold(body: Text('HOME')),
    ),
  );

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

  testWidgets('a server that cannot be reached fails open', (t) async {
    final api = _ThrowingApi();

    await t.pumpWidget(host(api));
    await settle(t);

    // A network blip must not lock a paying viewer out.
    expect(find.text('HOME'), findsOneWidget);
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
    // the reinstall case, once the fingerprint survives the uninstall.
    final api = FakeSubscriptionApi(
      plansResult: samplePlans(),
      identityResult: const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        planKey: 'stream_standard',
        status: 'active',
        entitled: true,
        showPaywall: false,
        daysLeft: 14,
      ),
    );

    await t.pumpWidget(host(api));
    await settle(t);

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text(kPremiumPlanLabel), findsNothing);
  });
}

/// An api whose [identify] always fails, standing in for an offline device.
class _ThrowingApi extends FakeSubscriptionApi {
  @override
  Future<DeviceIdentity?> identify() async => throw Exception('offline');
}
