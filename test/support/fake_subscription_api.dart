import 'package:watch_app/core/subscription/subscription_models.dart';
import 'package:watch_app/core/subscription/subscription_repository.dart';

/// In-memory [SubscriptionApi] for cubit tests.
///
/// Deliberately a hand-written fake rather than a mock: the cubits only ever
/// consume the return values, and the rules worth testing (trial once per
/// device, promo resolution, price maths) are the ones this fake encodes.
class FakeSubscriptionApi implements SubscriptionApi {
  FakeSubscriptionApi({
    this.plansResult = const [],
    this.identityResult,
    this.promoResult,
    this.trialResult = 'sub-id',
    this.adminConfiguredResult = false,
    this.adminCheckResult = true,
    this.configResult = const SubscriptionConfig(),
    this.seatsResult,
    this.linkResult,
  });

  List<SubscriptionPlan> plansResult;
  DeviceIdentity? identityResult;
  PromoResult? promoResult;
  String? trialResult;
  SubscriptionConfig configResult;
  CheckoutResult checkoutResult = const CheckoutResult(
    ok: true,
    free: false,
    checkoutUrl: 'https://checkout.test/pay',
  );
  bool adminConfiguredResult;
  bool adminCheckResult;

  int startTrialCalls = 0;
  int startCheckoutCalls = 0;
  String? lastCheckoutPlan;
  String? lastCheckoutPromo;
  int identifyCalls = 0;
  int createDeviceCodeCalls = 0;
  SeatResult? deviceCodeResult;
  SeatResult? linkResult;
  SeatSummary? seatsResult;
  bool revokeResult = true;
  final List<String> linkedCodes = [];
  final List<String> revokedSeats = [];
  final List<Map<String, Object?>> redemptions = [];
  final List<Map<String, Object?>> promoWrites = [];

  @override
  Future<List<SubscriptionPlan>> plans() async => plansResult;

  @override
  Future<SubscriptionConfig> config() async => configResult;

  @override
  Future<DeviceIdentity?> identify() async {
    identifyCalls++;
    return identityResult;
  }

  @override
  Future<PromoResult?> resolvePromo(String code, {String? planKey}) async =>
      promoResult;

  @override
  Future<int?> redeemPromo({
    required String code,
    required String planKey,
    required int beforeCents,
    required int afterCents,
  }) async {
    redemptions.add({
      'code': code,
      'planKey': planKey,
      'before': beforeCents,
      'after': afterCents,
    });
    return promoResult?.percentOff ?? 0;
  }

  @override
  Future<String?> startTrial(String planKey) async {
    startTrialCalls++;
    return trialResult;
  }

  @override
  Future<SeatResult?> createDeviceCode() async {
    createDeviceCodeCalls++;
    return deviceCodeResult;
  }

  @override
  Future<SeatResult?> linkDevice(String code, {String? label}) async {
    linkedCodes.add(code);
    if (linkResult?.ok == true) {
      identityResult = const DeviceIdentity(
        sessionId: 's1',
        isNew: false,
        trialUsed: true,
        planKey: 'stream_standard',
        status: 'active',
        entitled: true,
        showPaywall: false,
        daysLeft: 20,
      );
    }
    return linkResult;
  }

  @override
  Future<SeatSummary?> deviceSeats() async => seatsResult;

  @override
  Future<bool> revokeDeviceSeat(String fingerprint) async {
    revokedSeats.add(fingerprint);
    return revokeResult;
  }

  @override
  Future<CheckoutResult> startCheckout({
    required String planKey,
    String? promoCode,
  }) async {
    startCheckoutCalls++;
    lastCheckoutPlan = planKey;
    lastCheckoutPromo = promoCode;
    return checkoutResult;
  }

  @override
  Future<bool> adminConfigured() async => adminConfiguredResult;

  @override
  Future<bool> adminCheck(String passcode) async => adminCheckResult;

  @override
  Future<bool> adminSetup(String passcode) async => true;

  @override
  Future<bool> adminClaim(String passcode) async => true;

  @override
  Future<List<AdminDeviceRow>> adminDevices(String passcode) async => const [];

  @override
  Future<List<AdminPromoRow>> adminPromos(String passcode) async => const [];

  @override
  Future<List<AdminPlanRow>> adminSubscriptions(String passcode) async =>
      const [];

  @override
  Future<bool> adminSetPromo({
    required String passcode,
    required String code,
    required int percentOff,
    bool active = true,
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    promoWrites.add({'code': code, 'percentOff': percentOff, 'active': active});
    return true;
  }
}

/// Three tiers shaped like the seeded Sophie rows (USD cents).
List<SubscriptionPlan> samplePlans() => const [
  SubscriptionPlan(
    key: 'stream_basic',
    label: 'Basic (with ads)',
    priceCents: 199,
    periodDays: 30,
    trialDays: 0,
    features: ['HD', '1 screen'],
    sortOrder: 1,
  ),
  SubscriptionPlan(
    key: 'stream_standard',
    label: 'Standard',
    priceCents: 349,
    periodDays: 30,
    trialDays: 14,
    features: ['Full HD', '2 screens', 'Downloads'],
    sortOrder: 2,
  ),
  SubscriptionPlan(
    key: 'stream_premium',
    label: 'Premium',
    priceCents: 599,
    periodDays: 30,
    trialDays: 14,
    features: ['4K', '4 screens', 'Downloads'],
    sortOrder: 3,
  ),
];
