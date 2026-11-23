import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/features/admin/admin_cubit.dart';

import '../../support/fake_subscription_api.dart';

void main() {
  group('AdminCubit gate', () {
    test('asks for setup when no admin exists yet', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: false);
      final cubit = AdminCubit(api);
      await cubit.init();

      expect(cubit.state.gate, AdminGate.needsSetup);
    });

    test('locks when an admin already exists', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();

      expect(cubit.state.gate, AdminGate.locked);
    });

    test('setup unlocks the console', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: false);
      final cubit = AdminCubit(api);
      await cubit.init();

      final ok = await cubit.setup('admin@example.com', 'zangetsu-admin');

      expect(ok, isTrue);
      expect(cubit.state.gate, AdminGate.unlocked);
    });

    test('a wrong passcode keeps the console locked', () async {
      final api = FakeSubscriptionApi(
        adminConfiguredResult: true,
        adminLoginResult: false,
      );
      final cubit = AdminCubit(api);
      await cubit.init();

      final ok = await cubit.unlock('admin@example.com', 'wrong');

      expect(ok, isFalse);
      expect(cubit.state.gate, AdminGate.locked);
      expect(cubit.state.error, contains('Wrong email or password'));
    });

    test('a correct passcode unlocks', () async {
      final api = FakeSubscriptionApi(
        adminConfiguredResult: true,
        adminCheckResult: true,
      );
      final cubit = AdminCubit(api);
      await cubit.init();

      final ok = await cubit.unlock('admin@example.com', 'zangetsu-admin');

      expect(ok, isTrue);
      expect(cubit.state.gate, AdminGate.unlocked);
    });

    test('refresh loads the complete console snapshot', () async {
      final api = FakeSubscriptionApi(
        adminConfiguredResult: true,
        adminOverviewResult: const AdminOverview(
          devices: 12,
          activeSubs: 7,
          mrrCents: 1400,
          trialing: 3,
        ),
        adminPlansResult: const [
          AdminPlanConfig(
            key: 'stream_standard',
            label: 'Standard',
            priceCents: 200,
            periodDays: 30,
            trialDays: 14,
            active: true,
            sortOrder: 11,
          ),
        ],
        adminAdminsResult: const [
          AdminAccountRow(
            email: 'owner@example.com',
            role: 'owner',
            active: true,
          ),
        ],
        adminAuditResult: const [
          AdminAuditRow(actor: 'owner@example.com', action: 'plan.update'),
        ],
        adminRedemptionsResult: const [
          AdminRedemptionRow(code: 'LAUNCH', fingerprint: 'abcdef012345'),
        ],
        adminConfigResult: const {
          'launch_discount_pct': 15,
          'display_currency': 'NGN',
        },
      );
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('owner@example.com', 'zangetsu-admin');

      expect(cubit.state.overview.devices, 12);
      expect(cubit.state.activeSubs, 7);
      expect(cubit.state.mrrCents, 1400);
      expect(cubit.state.planConfigs.single.priceCents, 200);
      expect(cubit.state.admins.single.role, 'owner');
      expect(cubit.state.audit.single.action, 'plan.update');
      expect(cubit.state.redemptions.single.code, 'LAUNCH');
      expect(cubit.state.launchDiscountPct, 15);
      expect(cubit.state.displayCurrency, 'NGN');
    });

    test('grantSubscription forwards the period and plan', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('owner@example.com', 'zangetsu-admin');

      final ok = await cubit.grantSubscription(
        'abcdef0123456789',
        days: 90,
        note: 'support credit',
      );

      expect(ok, isTrue);
      final action = api.adminActions.single;
      expect(action['action'], 'grant');
      expect(action['days'], 90);
      expect(action['plan'], 'stream_standard');
      expect(action['note'], 'support credit');
    });

    test('blocking a device forwards the ban and note', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('owner@example.com', 'zangetsu-admin');

      await cubit.setDeviceBlocked(
        'abcdef0123456789',
        blocked: true,
        note: 'chargeback',
      );

      final action = api.adminActions.single;
      expect(action['action'], 'block');
      expect(action['blocked'], isTrue);
      expect(action['note'], 'chargeback');
    });

    test('plan price edits stay in cents', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('owner@example.com', 'zangetsu-admin');

      await cubit.updatePlan(
        key: 'stream_standard',
        priceCents: 250,
        trialDays: 7,
        active: true,
      );

      final action = api.adminActions.single;
      expect(action['action'], 'plan');
      expect(action['price'], 250);
      expect(action['trial'], 7);
    });

    test('changing the password keeps the console usable', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('owner@example.com', 'zangetsu-admin');

      final ok = await cubit.changePassword('new-secret-123');

      expect(ok, isTrue);
      expect(api.lastNewPassword, 'new-secret-123');
      expect(cubit.state.gate, AdminGate.unlocked);
    });

    test('device rows expose operator blocks and notes', () {
      final row = AdminDeviceRow.fromMap({
        'fingerprint': 'abcdef012345',
        'status': 'active',
        'blocked': true,
        'admin_note': 'chargeback',
      });

      expect(row.blocked, isTrue);
      expect(row.adminNote, 'chargeback');
    });

    test('overview totals parse from the dashboard RPC', () {
      final overview = AdminOverview.fromMap({
        'devices': 10,
        'devices_active_24h': 4,
        'active_subs': 6,
        'trialing': 2,
        'mrr_cents': 1200,
        'revenue_30d_cents': 2400,
        'promos_active': 3,
        'redemptions_30d': 5,
        'admins': 2,
      });

      expect(overview.devices, 10);
      expect(overview.activeSubs, 6);
      expect(overview.mrrCents, 1200);
      expect(overview.admins, 2);
    });

    test('lock drops the passcode and returns to the gate', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('owner@example.com', 'zangetsu-admin');

      cubit.lock();

      expect(cubit.state.gate, AdminGate.locked);
    });

    test('refreshTrial forwards the fingerprint and refreshes', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('admin@example.com', 'zangetsu-admin');

      final ok = await cubit.refreshTrial('abcdef0123456789');

      expect(ok, isTrue);
      expect(api.adminRefreshTrialCalls, 1);
      expect(api.lastRefreshFingerprint, 'abcdef0123456789');
    });

    test('setPromo forwards to the API and refreshes', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('admin@example.com', 'zangetsu-admin');

      await cubit.setPromo(code: 'LAUNCH50', percentOff: 50, active: true);

      expect(api.promoWrites, hasLength(1));
      expect(api.promoWrites.single['code'], 'LAUNCH50');
      expect(api.promoWrites.single['percentOff'], 50);
    });
  });

  group('Admin dashboard device activity', () {
    AdminDeviceRow device({
      required Duration seenAgo,
      String status = 'active',
    }) => AdminDeviceRow(
      fingerprint: 'abcdef0123456789',
      status: status,
      lastSeenAt: DateTime.now().subtract(seenAgo),
    );

    test('a device seen recently counts as active', () {
      final row = device(seenAgo: const Duration(minutes: 5));
      expect(row.isActive, isTrue);
      expect(row.lastSeenLabel, '5m');
    });

    test('a device seen long ago is idle, not active', () {
      final row = device(seenAgo: const Duration(days: 3));
      expect(row.isActive, isFalse);
      expect(row.lastSeenLabel, '3d');
    });

    test('a device with no timestamp is never active', () {
      const row = AdminDeviceRow(fingerprint: 'abcdef0123456789');
      expect(row.isActive, isFalse);
      expect(row.lastSeenLabel, isEmpty);
    });

    test('the state counts active devices for the KPI', () {
      final state = AdminState(
        devices: [
          device(seenAgo: const Duration(minutes: 1)),
          device(seenAgo: const Duration(hours: 2)),
          device(seenAgo: const Duration(days: 9)),
        ],
      );
      expect(state.activeDevices, 2);
    });
  });
}
