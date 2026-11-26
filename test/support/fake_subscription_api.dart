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
    this.adminConfiguredResult = false,
    this.adminCheckResult = true,
    this.adminLoginResult = true,
    this.adminRegisterResult = true,
    this.configResult = const SubscriptionConfig(),
    this.seatsResult,
    this.linkResult,
    this.adminOverviewResult,
    this.adminPlansResult = const [],
    this.adminConfigResult,
    this.adminAdminsResult = const [],
    this.adminAuditResult = const [],
    this.adminRedemptionsResult = const [],
    this.transactionsResult = const [],
  });

  List<SubscriptionPlan> plansResult;
  DeviceIdentity? identityResult;
  PromoResult? promoResult;
  SubscriptionConfig configResult;
  CheckoutResult checkoutResult = const CheckoutResult(
    ok: true,
    free: false,
    checkoutUrl: 'https://checkout.test/pay',
  );
  bool adminConfiguredResult;
  bool adminCheckResult;
  bool adminLoginResult;
  bool adminRegisterResult;

  int adminLoginCalls = 0;
  int adminRegisterCalls = 0;
  String? lastAdminEmail;
  String? lastAdminPassword;
  String? lastNewPassword;
  int startCheckoutCalls = 0;
  int confirmCalls = 0;
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
  final List<Map<String, Object?>> promoWrites = [];
  List<DeviceTransaction>? transactionsResult = const [];

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
  Future<void> confirmPendingPayment() async {
    confirmCalls++;
  }

  @override
  Future<List<DeviceTransaction>?> transactions() async => transactionsResult;

  @override
  Future<bool> adminConfigured() async => adminConfiguredResult;

  @override
  Future<bool> adminCheck(String passcode) async => adminCheckResult;

  @override
  Future<bool> adminLogin(String email, String password) async {
    adminLoginCalls++;
    lastAdminEmail = email;
    lastAdminPassword = password;
    return adminLoginResult;
  }

  @override
  Future<bool> adminRegister(String email, String password) async {
    adminRegisterCalls++;
    lastAdminEmail = email;
    lastAdminPassword = password;
    return adminRegisterResult;
  }

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

  AdminOverview? adminOverviewResult;
  List<AdminPlanConfig> adminPlansResult = const [];
  Map<String, dynamic>? adminConfigResult;
  List<AdminAccountRow> adminAdminsResult = const [];
  List<AdminAuditRow> adminAuditResult = const [];
  List<AdminRedemptionRow> adminRedemptionsResult = const [];
  final List<Map<String, Object?>> adminActions = [];

  @override
  Future<AdminOverview?> adminOverview(String passcode) async =>
      adminOverviewResult;

  @override
  Future<List<AdminPlanConfig>> adminPlans(String passcode) async =>
      adminPlansResult;

  @override
  Future<bool> adminUpdatePlan({
    required String passcode,
    required String key,
    required int priceCents,
    bool? active,
  }) async {
    adminActions.add({
      'action': 'plan',
      'key': key,
      'price': priceCents,
      'active': active,
    });
    return true;
  }

  @override
  Future<Map<String, dynamic>?> adminConfig(String passcode) async =>
      adminConfigResult;

  @override
  Future<bool> adminUpdateConfig({
    required String passcode,
    int? launchDiscountPct,
    String? displayCurrency,
  }) async {
    adminActions.add({
      'action': 'config',
      'discount': launchDiscountPct,
      'currency': displayCurrency,
    });
    return true;
  }

  @override
  Future<bool> adminSetDeviceBlocked({
    required String passcode,
    required String fingerprint,
    required bool blocked,
    String? note,
  }) async {
    adminActions.add({
      'action': 'block',
      'fingerprint': fingerprint,
      'blocked': blocked,
      'note': note,
    });
    return true;
  }

  @override
  Future<bool> adminGrantSubscription({
    required String passcode,
    required String fingerprint,
    int days = 30,
    String planKey = 'stream_standard',
    String? note,
  }) async {
    adminActions.add({
      'action': 'grant',
      'fingerprint': fingerprint,
      'days': days,
      'plan': planKey,
      'note': note,
    });
    return true;
  }

  @override
  Future<bool> adminRevokeSubscription({
    required String passcode,
    required String fingerprint,
    String? reason,
  }) async {
    adminActions.add({
      'action': 'revoke',
      'fingerprint': fingerprint,
      'reason': reason,
    });
    return true;
  }

  @override
  Future<bool> adminRevokeSeat({
    required String passcode,
    required String ownerFingerprint,
    required String seatFingerprint,
  }) async {
    adminActions.add({
      'action': 'seat',
      'owner': ownerFingerprint,
      'seat': seatFingerprint,
    });
    return true;
  }

  @override
  Future<bool> adminDeletePromo({
    required String passcode,
    required String code,
  }) async {
    adminActions.add({'action': 'deletePromo', 'code': code});
    return true;
  }

  @override
  Future<List<AdminRedemptionRow>> adminRedemptions(String passcode) async =>
      adminRedemptionsResult;

  @override
  Future<List<AdminAccountRow>> adminAdmins(String passcode) async =>
      adminAdminsResult;

  @override
  Future<bool> adminCreateAdmin({
    required String passcode,
    required String email,
    required String password,
  }) async {
    adminActions.add({'action': 'createAdmin', 'email': email});
    return true;
  }

  @override
  Future<bool> adminSetAdminActive({
    required String passcode,
    required String email,
    required bool active,
  }) async {
    adminActions.add({
      'action': 'adminActive',
      'email': email,
      'active': active,
    });
    return true;
  }

  @override
  Future<bool> adminChangePassword({
    required String passcode,
    required String newPassword,
  }) async {
    lastNewPassword = newPassword;
    adminActions.add({'action': 'password'});
    return true;
  }

  @override
  Future<List<AdminAuditRow>> adminAudit(String passcode) async =>
      adminAuditResult;
}

/// Three tiers shaped like the seeded Sophie rows (USD cents).
List<SubscriptionPlan> samplePlans() => const [
  SubscriptionPlan(
    key: 'stream_basic',
    label: 'Basic (with ads)',
    priceCents: 75,
    periodDays: 30,
    features: ['HD', '1 screen'],
    sortOrder: 1,
  ),
  SubscriptionPlan(
    key: 'stream_standard',
    label: 'Standard',
    priceCents: 75,
    periodDays: 30,
    features: ['Full HD', '2 screens', 'Downloads'],
    sortOrder: 2,
  ),
  SubscriptionPlan(
    key: 'stream_premium',
    label: 'Premium',
    priceCents: 75,
    periodDays: 30,
    features: ['4K', '4 screens', 'Downloads'],
    sortOrder: 3,
  ),
];
