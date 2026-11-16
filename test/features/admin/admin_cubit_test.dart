import 'package:flutter_test/flutter_test.dart';
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

      final ok = await cubit.setup('zangetsu-admin');

      expect(ok, isTrue);
      expect(cubit.state.gate, AdminGate.unlocked);
    });

    test('a wrong passcode keeps the console locked', () async {
      final api = FakeSubscriptionApi(
        adminConfiguredResult: true,
        adminCheckResult: false,
      );
      final cubit = AdminCubit(api);
      await cubit.init();

      final ok = await cubit.unlock('wrong');

      expect(ok, isFalse);
      expect(cubit.state.gate, AdminGate.locked);
      expect(cubit.state.error, contains('Wrong'));
    });

    test('a correct passcode unlocks', () async {
      final api = FakeSubscriptionApi(
        adminConfiguredResult: true,
        adminCheckResult: true,
      );
      final cubit = AdminCubit(api);
      await cubit.init();

      final ok = await cubit.unlock('zangetsu-admin');

      expect(ok, isTrue);
      expect(cubit.state.gate, AdminGate.unlocked);
    });

    test('setPromo forwards to the API and refreshes', () async {
      final api = FakeSubscriptionApi(adminConfiguredResult: true);
      final cubit = AdminCubit(api);
      await cubit.init();
      await cubit.unlock('zangetsu-admin');

      await cubit.setPromo(code: 'LAUNCH50', percentOff: 50, active: true);

      expect(api.promoWrites, hasLength(1));
      expect(api.promoWrites.single['code'], 'LAUNCH50');
      expect(api.promoWrites.single['percentOff'], 50);
    });
  });
}
