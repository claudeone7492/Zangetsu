import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/core/subscription/subscription_repository.dart';
import 'package:watch_app/features/paywall/subscription_history_screen.dart';

import '../../support/fake_subscription_api.dart';

void main() {
  final sl = GetIt.instance;

  setUp(() => sl.reset());
  tearDown(() => sl.reset());

  Widget host() => const MaterialApp(home: SubscriptionHistoryScreen());

  DeviceIdentity identity() => DeviceIdentity(
    sessionId: 's1',
    isNew: false,
    trialUsed: true,
    planKey: 'stream_standard',
    status: 'active',
    periodEnd: DateTime(2026, 12, 24),
    entitled: true,
    showPaywall: false,
    daysLeft: 30,
  );

  testWidgets('shows the plan and this device\'s payments with references', (
    t,
  ) async {
    final api = FakeSubscriptionApi(
      identityResult: identity(),
      transactionsResult: [
        DeviceTransaction(
          reference: 'sx_sub_streamstandard_abc123',
          productType: 'subscription_stream',
          planKey: 'stream_standard',
          planLabel: 'Standard',
          amountCents: 200,
          currency: 'USD',
          status: 'completed',
          createdAt: DateTime(2026, 11, 23, 9, 30),
          completedAt: DateTime(2026, 11, 23, 9, 31),
        ),
      ],
    );
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.text('Premium subscription'), findsWidgets);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('\$2.00'), findsOneWidget);
    expect(find.text('sx_sub_streamstandard_abc123'), findsOneWidget);
  });

  testWidgets('an empty history explains what will appear here', (t) async {
    final api = FakeSubscriptionApi(
      identityResult: identity(),
      transactionsResult: const [],
    );
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.textContaining('No payments yet'), findsOneWidget);
  });

  testWidgets('a failed lookup offers a retry notice', (t) async {
    final api = FakeSubscriptionApi(
      identityResult: identity(),
      transactionsResult: null,
    );
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.textContaining('Could not load payments'), findsOneWidget);
  });

  testWidgets('an unreadable plan does not claim the device is unsubscribed', (
    t,
  ) async {
    final api = FakeSubscriptionApi(
      identityResult: null,
      transactionsResult: const [],
    );
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.text('Plan status unavailable'), findsOneWidget);
    expect(find.text('No active plan'), findsNothing);
  });
}
