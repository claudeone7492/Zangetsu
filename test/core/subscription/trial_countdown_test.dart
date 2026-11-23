import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/core/subscription/trial_countdown.dart';
import 'package:watch_app/features/paywall/trial_countdown_badge.dart';

void main() {
  final controller = TrialCountdownController.instance;

  setUp(controller.debugReset);
  tearDown(controller.debugReset);

  DeviceIdentity identity({
    required bool isTrial,
    required bool entitled,
    DateTime? end,
    DateTime? serverNow,
  }) => DeviceIdentity(
    sessionId: 's1',
    isNew: false,
    trialUsed: isTrial,
    status: entitled ? 'active' : 'inactive',
    periodEnd: end,
    entitled: entitled,
    showPaywall: !entitled,
    isTrial: isTrial,
    serverNow: serverNow,
  );

  test('shows a countdown for an active trial', () {
    final now = DateTime.now().toUtc();
    controller.update(
      identity(
        isTrial: true,
        entitled: true,
        end: now.add(const Duration(hours: 2)),
        serverNow: now,
      ),
    );

    final value = controller.countdown.value;
    expect(value, isNotNull);
    expect(
      value!.remaining,
      greaterThan(const Duration(hours: 1, minutes: 59)),
    );
    expect(value.compactLabel, anyOf('2h 0m', '1h 59m'));
  });

  test('never shows a countdown for a paid subscription', () {
    final now = DateTime.now().toUtc();
    controller.update(
      identity(
        isTrial: false,
        entitled: true,
        end: now.add(const Duration(days: 20)),
        serverNow: now,
      ),
    );

    expect(controller.countdown.value, isNull);
    expect(controller.expired.value, isFalse);
  });

  test('an ended trial clears the badge and signals expiry', () {
    final now = DateTime.now().toUtc();
    controller.update(
      identity(
        isTrial: true,
        entitled: true,
        end: now.subtract(const Duration(seconds: 1)),
        serverNow: now,
      ),
    );

    expect(controller.countdown.value, isNull);
    expect(controller.expired.value, isTrue);
  });

  test('the cached identity keeps the trial flag and server clock', () {
    final now = DateTime.utc(2026, 11, 23, 8, 30);
    final original = identity(
      isTrial: true,
      entitled: true,
      end: now.add(const Duration(days: 2)),
      serverNow: now,
    );

    final cached = DeviceIdentity.fromMap(original.toMap());

    expect(cached, isNotNull);
    expect(cached!.isTrial, isTrue);
    expect(cached.serverNow, now);
  });

  test('compact labels cover days, hours and seconds', () {
    final end = DateTime.now();
    expect(
      TrialCountdown(
        endsAt: end,
        remaining: const Duration(days: 13, hours: 4),
      ).compactLabel,
      '13d 4h',
    );
    expect(
      TrialCountdown(
        endsAt: end,
        remaining: const Duration(hours: 4, minutes: 12),
      ).compactLabel,
      '4h 12m',
    );
    expect(
      TrialCountdown(
        endsAt: end,
        remaining: const Duration(minutes: 12, seconds: 8),
      ).compactLabel,
      '12m 08s',
    );
  });

  testWidgets('the badge is a small glass pill and disappears for paid', (
    t,
  ) async {
    final now = DateTime.now().toUtc();
    controller.update(
      identity(
        isTrial: true,
        entitled: true,
        end: now.add(const Duration(hours: 2)),
        serverNow: now,
      ),
    );

    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: TrialCountdownBadge())),
    );
    expect(find.byKey(const ValueKey('trial-countdown-badge')), findsOneWidget);
    expect(find.text('Free trial'), findsOneWidget);

    controller.update(
      identity(
        isTrial: false,
        entitled: true,
        end: now.add(const Duration(days: 20)),
        serverNow: now,
      ),
    );
    await t.pump();
    expect(find.byKey(const ValueKey('trial-countdown-badge')), findsNothing);
  });
}
