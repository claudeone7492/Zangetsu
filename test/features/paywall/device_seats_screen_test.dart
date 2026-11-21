import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/core/subscription/subscription_repository.dart';
import 'package:watch_app/features/paywall/device_seats_screen.dart';

import '../../support/fake_subscription_api.dart';

/// The owner's view of a shared plan: who is on it, how many slots are left,
/// the code that fills one, and taking one back.
void main() {
  final sl = GetIt.instance;

  setUp(() => sl.reset());
  tearDown(() => sl.reset());

  Widget host() => const MaterialApp(home: DeviceSeatsScreen());

  SeatSummary summary({required int limit, required int used}) => SeatSummary(
    seatLimit: limit,
    seatsUsed: used,
    seats: [
      const DeviceSeat(
        fingerprint: 'owner-fingerprint-aaaa',
        label: 'Pixel 8',
        platform: 'Android 15',
        isSelf: true,
      ),
      for (var i = 1; i < used; i++)
        DeviceSeat(
          fingerprint: 'guest-fingerprint-bbbb$i',
          label: 'iPhone 13',
          platform: 'iOS 18',
        ),
    ],
  );

  testWidgets('lists the devices and how much of the plan is used', (t) async {
    final api = FakeSubscriptionApi(seatsResult: summary(limit: 4, used: 2));
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.text('2 of 4 devices'), findsOneWidget);
    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text('iPhone 13'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
  });

  testWidgets('adding a device shows the code to hand over', (t) async {
    final api = FakeSubscriptionApi(seatsResult: summary(limit: 4, used: 1))
      ..deviceCodeResult = SeatResult.fromMap({
        'ok': true,
        'code': 'ABCD2345',
        'seats_used': 2,
        'seat_limit': 4,
      });
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    await t.tap(find.text('Add a device'));
    await t.pumpAndSettle();

    expect(api.createDeviceCodeCalls, 1);
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.textContaining('Valid for 10 minutes'), findsOneWidget);
  });

  testWidgets('a full plan offers no add button', (t) async {
    final api = FakeSubscriptionApi(seatsResult: summary(limit: 2, used: 2));
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.text('Add a device'), findsNothing);
    expect(
      find.textContaining('Every device on this plan is in use'),
      findsOneWidget,
    );
  });

  testWidgets('removing a device asks first, then revokes it', (t) async {
    final api = FakeSubscriptionApi(seatsResult: summary(limit: 4, used: 2));
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    await t.tap(find.byTooltip('Remove'));
    await t.pumpAndSettle();
    expect(find.text('Remove this device?'), findsOneWidget);

    await t.tap(find.text('Remove'));
    await t.pumpAndSettle();

    expect(api.revokedSeats, ['guest-fingerprint-bbbb1']);
  });

  testWidgets('a guest sees the plan it is on and can leave it', (t) async {
    final api = FakeSubscriptionApi(
      seatsResult: const SeatSummary(
        seatLimit: 2,
        seatsUsed: 2,
        isSeat: true,
        seats: [
          DeviceSeat(fingerprint: 'guest-fingerprint-cccc', isSelf: true),
          DeviceSeat(fingerprint: 'owner-fingerprint-dddd', label: 'Pixel 8'),
        ],
      ),
    );
    sl.registerLazySingleton<SubscriptionApi>(() => api);

    await t.pumpWidget(host());
    await t.pumpAndSettle();

    expect(find.textContaining('shared plan'), findsOneWidget);
    expect(find.text('Leave this plan'), findsOneWidget);
    // A guest cannot manage the owner's other devices.
    expect(find.byTooltip('Remove'), findsNothing);
  });
}
