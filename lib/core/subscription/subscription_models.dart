/// Subscription + promo models. All prices are USD cents.
library;

/// The single product the paywall sells. The backend catalogue is tiered, but
/// the app presents one premium subscription at the standard price, so this is
/// the label every card and summary row uses.
const String kPremiumPlanLabel = 'Premium subscription';

/// A purchasable tier, loaded from `subscription_plans`.
class SubscriptionPlan {
  const SubscriptionPlan({
    required this.key,
    required this.label,
    required this.priceCents,
    required this.periodDays,
    required this.features,
    required this.sortOrder,
  });

  final String key;
  final String label;
  final int priceCents;
  final int periodDays;
  final List<String> features;
  final int sortOrder;

  /// List price in dollars, e.g. `0.75`.
  double get listDollars => priceCents / 100;

  SubscriptionPlan copyWith({String? label}) => SubscriptionPlan(
    key: key,
    label: label ?? this.label,
    priceCents: priceCents,
    periodDays: periodDays,
    features: features,
    sortOrder: sortOrder,
  );

  static SubscriptionPlan? fromMap(Map<String, dynamic> m) {
    final key = m['key'];
    final label = m['label'];
    if (key is! String || label is! String) return null;
    return SubscriptionPlan(
      key: key,
      label: label,
      priceCents: (m['price_usd_cents'] as num?)?.toInt() ?? 0,
      periodDays: (m['period_days'] as num?)?.toInt() ?? 30,
      features: ((m['features'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(growable: false),
      sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The resolved result of typing a promo code. Never exposes the catalogue.
class PromoResult {
  const PromoResult({
    required this.code,
    required this.percentOff,
    required this.kind,
    this.label,
    this.alreadyUsed = false,
    this.usable = true,
  });

  final String code;
  final int percentOff;
  final String kind; // 'free' | 'percent'
  final String? label;

  /// True when this device has already redeemed the code. The redemption row
  /// is kept after the one-month access window, so reuse is refused forever.
  final bool alreadyUsed;

  /// False when the code is inactive, expired or exhausted.
  final bool usable;

  bool get isFree => kind == 'free' || percentOff >= 100;

  static PromoResult? fromMap(Map<String, dynamic> m) {
    final code = m['code'];
    if (code is! String) return null;
    return PromoResult(
      code: code,
      percentOff: (m['percent_off'] as num?)?.toInt() ?? 0,
      kind: (m['kind'] as String?) ?? 'percent',
      label: m['label'] as String?,
      alreadyUsed: m['already_used'] == true,
      usable: m['usable'] != false,
    );
  }
}

/// This device's identity + current subscription, from `identify_device`.
class DeviceIdentity {
  const DeviceIdentity({
    required this.sessionId,
    required this.isNew,
    this.planKey,
    this.status = 'inactive',
    this.periodEnd,
    this.entitled = false,
    this.showPaywall = true,
    this.daysLeft = 0,
    this.serverNow,
  });

  final String sessionId;
  final bool isNew;
  final String? planKey;
  final String status;
  final DateTime? periodEnd;

  /// Server verdict: this device may watch right now.
  final bool entitled;

  /// Server verdict: the paywall must be shown (no entitlement).
  final bool showPaywall;

  /// Whole days left in the current period.
  final int daysLeft;

  /// Server clock at the moment this identity was read. The countdown uses
  /// this instead of the device clock, so moving the device clock back cannot
  /// stretch a trial.
  final DateTime? serverNow;

  bool get isActive => entitled || status == 'active' || status == 'grace';

  /// Round-trips through [DeviceIdentity.fromMap] for the offline entitlement
  /// cache. Only fields the gate needs are written.
  Map<String, dynamic> toMap() => {
    'session_id': sessionId,
    'is_new': isNew,
    'plan_key': planKey,
    'status': status,
    'period_end': periodEnd?.toUtc().toIso8601String(),
    'entitled': entitled,
    'show_paywall': showPaywall,
    'days_left': daysLeft,
    'server_now': serverNow?.toUtc().toIso8601String(),
  };

  static DeviceIdentity? fromMap(Map<String, dynamic> m) {
    final session = m['session_id'];
    if (session is! String) return null;
    final end = m['period_end'];
    final server = m['server_now'];
    return DeviceIdentity(
      sessionId: session,
      isNew: m['is_new'] == true,
      planKey: m['plan_key'] as String?,
      status: (m['status'] as String?) ?? 'inactive',
      periodEnd: end is String ? DateTime.tryParse(end) : null,
      entitled: m['entitled'] == true,
      showPaywall: m['show_paywall'] != false,
      daysLeft: (m['days_left'] as num?)?.toInt() ?? 0,
      serverNow: server is String ? DateTime.tryParse(server) : null,
    );
  }
}

/// The result of starting a checkout, from the `stream-subscribe` function.
class CheckoutResult {
  const CheckoutResult({
    required this.ok,
    required this.free,
    this.checkoutUrl,
    this.reference,
    this.planKey,
    this.amountCents = 0,
    this.error,
  });

  final bool ok;

  /// The promo covered the full price, so access was granted without a charge.
  final bool free;
  final String? checkoutUrl;
  final String? reference;
  final String? planKey;
  final int amountCents;
  final String? error;

  static CheckoutResult fromMap(Map<String, dynamic> m) => CheckoutResult(
    ok: m['ok'] == true,
    free: m['free'] == true,
    checkoutUrl: m['checkoutUrl'] as String?,
    reference: m['reference'] as String?,
    planKey: m['planKey'] as String?,
    amountCents: (m['amountUsdCents'] as num?)?.toInt() ?? 0,
    error: m['error'] as String?,
  );
}

/// One payment row from `device_transactions`, scoped to this device's own
/// session. The Korapay reference is the link between the merchant-billed
/// charge and the device that initiated it.
class DeviceTransaction {
  const DeviceTransaction({
    required this.reference,
    required this.productType,
    required this.amountCents,
    required this.currency,
    required this.status,
    this.planKey,
    this.planLabel,
    this.promoCode,
    this.createdAt,
    this.completedAt,
    this.periodEnd,
  });

  final String reference;
  final String productType;
  final String? planKey;
  final String? planLabel;
  final int amountCents;
  final String currency;
  final String status;
  final String? promoCode;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? periodEnd;

  bool get completed => status == 'completed';
  bool get failed => status == 'failed' || status == 'refunded';

  String get title {
    if (planKey == 'stream_standard') return kPremiumPlanLabel;
    return planLabel ?? 'Subscription';
  }

  static DeviceTransaction? fromMap(Map<String, dynamic> m) {
    final reference = m['reference'];
    if (reference is! String || reference.isEmpty) return null;
    DateTime? date(Object? value) =>
        value is String ? DateTime.tryParse(value) : null;
    return DeviceTransaction(
      reference: reference,
      productType: (m['product_type'] as String?) ?? 'subscription_stream',
      planKey: m['plan_key'] as String?,
      planLabel: m['plan_label'] as String?,
      amountCents: (m['amount_cents'] as num?)?.toInt() ?? 0,
      currency: (m['currency'] as String?) ?? 'USD',
      status: (m['status'] as String?) ?? 'pending',
      promoCode: m['promo_code'] as String?,
      createdAt: date(m['created_at']),
      completedAt: date(m['completed_at']),
      periodEnd: date(m['period_end']),
    );
  }
}

/// A row of the admin Devices table, from `admin_devices`.
class AdminDeviceRow {
  const AdminDeviceRow({
    required this.fingerprint,
    this.platform,
    this.plan,
    this.promo,
    this.percentOff = 0,
    this.paidCents = 0,
    this.status = 'inactive',
    this.renewsAt,
    this.watch = 0,
    this.lastSeenAt,
    this.seatOwner,
    this.seats = 1,
    this.blocked = false,
    this.adminNote,
  });

  final String fingerprint;
  final String? platform;
  final String? plan;
  final String? promo;
  final int percentOff;
  final int paidCents;
  final String status;
  final DateTime? renewsAt;
  final int watch;
  final DateTime? lastSeenAt;

  /// The fingerprint this device is linked to, when it watches on someone
  /// else's plan. Null for a device that pays for itself.
  final String? seatOwner;

  /// Devices on the plan this device is on, itself included. 1 when unshared.
  final int seats;

  /// Operator ban: a blocked device gets no entitlement, even with a live plan.
  final bool blocked;

  /// Free-text note shown next to the device in the console.
  final String? adminNote;

  /// The Sharing column: who this device rides on, or how many ride on it.
  String get sharingLabel {
    final owner = seatOwner;
    if (owner != null && owner.isNotEmpty) {
      return 'on ${_shortFingerprint(owner)}';
    }
    if (seats > 1) return 'owner of $seats';
    return '—';
  }

  static String _shortFingerprint(String fp) => fp.length <= 10
      ? fp
      : '${fp.substring(0, 6)}…${fp.substring(fp.length - 4)}';

  /// Whether this device counts as "active" on the dashboard: the app checked in
  /// recently. A device the operator is looking at is only useful to know about
  /// while it is still checking in; a row last seen weeks ago is history, not a
  /// live device. [identify_device] stamps `last_seen_at` on every launch, so a
  /// short window is a reliable "someone is using this right now" signal.
  bool get isActive {
    final seen = lastSeenAt;
    if (seen == null) return false;
    return DateTime.now().difference(seen) < const Duration(hours: 24);
  }

  /// A human label for how long ago the device last checked in, e.g. `2m`,
  /// `3h`, `4d`. Empty when there is no timestamp.
  String get lastSeenLabel {
    final seen = lastSeenAt;
    if (seen == null) return '';
    final d = DateTime.now().difference(seen);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  static AdminDeviceRow fromMap(Map<String, dynamic> m) => AdminDeviceRow(
    fingerprint: '${m['fingerprint']}',
    platform: m['platform'] as String?,
    plan: m['plan'] as String?,
    promo: m['promo'] as String?,
    percentOff: (m['percent_off'] as num?)?.toInt() ?? 0,
    paidCents: (m['paid_cents'] as num?)?.toInt() ?? 0,
    status: (m['status'] as String?) ?? 'inactive',
    renewsAt: _dt(m['renews_at']),
    watch: (m['watch'] as num?)?.toInt() ?? 0,
    lastSeenAt: _dt(m['last_seen_at']),
    seatOwner: m['seat_owner'] as String?,
    seats: (m['seats'] as num?)?.toInt() ?? 1,
    blocked: m['blocked'] == true,
    adminNote: m['admin_note'] as String?,
  );
}

/// A row of the admin Promo Codes table, from `admin_promos`.
class AdminPromoRow {
  const AdminPromoRow({
    required this.code,
    required this.percentOff,
    required this.kind,
    required this.active,
    this.maxUses,
    this.usedCount = 0,
    this.expiresAt,
  });

  final String code;
  final int percentOff;
  final String kind;
  final bool active;
  final int? maxUses;
  final int usedCount;
  final DateTime? expiresAt;

  static AdminPromoRow fromMap(Map<String, dynamic> m) => AdminPromoRow(
    code: '${m['code']}',
    percentOff: (m['percent_off'] as num?)?.toInt() ?? 0,
    kind: (m['kind'] as String?) ?? 'percent',
    active: m['active'] == true,
    maxUses: (m['max_uses'] as num?)?.toInt(),
    usedCount: (m['used_count'] as num?)?.toInt() ?? 0,
    expiresAt: _dt(m['expires_at']),
  );
}

/// A row of the admin Subscriptions table, from `admin_subscriptions`.
class AdminPlanRow {
  const AdminPlanRow({
    required this.plan,
    required this.subscribers,
    required this.priceCents,
    required this.revenueCents,
  });

  final String plan;
  final int subscribers;
  final int priceCents;
  final int revenueCents;

  static AdminPlanRow fromMap(Map<String, dynamic> m) => AdminPlanRow(
    plan: '${m['plan']}',
    subscribers: (m['subscribers'] as num?)?.toInt() ?? 0,
    priceCents: (m['price_usd_cents'] as num?)?.toInt() ?? 0,
    revenueCents: (m['revenue_cents'] as num?)?.toInt() ?? 0,
  );
}

/// Dashboard totals from `admin_overview`.
class AdminOverview {
  const AdminOverview({
    this.devices = 0,
    this.devicesActive24h = 0,
    this.blocked = 0,
    this.activeSubs = 0,
    this.expiring7d = 0,
    this.promosActive = 0,
    this.redemptions30d = 0,
    this.mrrCents = 0,
    this.revenue30dCents = 0,
    this.admins = 0,
  });

  final int devices;
  final int devicesActive24h;
  final int blocked;
  final int activeSubs;
  final int expiring7d;
  final int promosActive;
  final int redemptions30d;
  final int mrrCents;
  final int revenue30dCents;
  final int admins;

  static AdminOverview fromMap(Map<String, dynamic> m) => AdminOverview(
    devices: (m['devices'] as num?)?.toInt() ?? 0,
    devicesActive24h: (m['devices_active_24h'] as num?)?.toInt() ?? 0,
    blocked: (m['blocked'] as num?)?.toInt() ?? 0,
    activeSubs: (m['active_subs'] as num?)?.toInt() ?? 0,
    expiring7d: (m['expiring_7d'] as num?)?.toInt() ?? 0,
    promosActive: (m['promos_active'] as num?)?.toInt() ?? 0,
    redemptions30d: (m['redemptions_30d'] as num?)?.toInt() ?? 0,
    mrrCents: (m['mrr_cents'] as num?)?.toInt() ?? 0,
    revenue30dCents: (m['revenue_30d_cents'] as num?)?.toInt() ?? 0,
    admins: (m['admins'] as num?)?.toInt() ?? 0,
  );
}

/// A row of the admin Plans table, from `admin_plans`. Unlike
/// [AdminPlanRow], this carries the editable fields as well as the totals.
class AdminPlanConfig {
  const AdminPlanConfig({
    required this.key,
    required this.label,
    required this.priceCents,
    required this.periodDays,
    required this.active,
    required this.sortOrder,
    this.subscribers = 0,
  });

  final String key;
  final String label;
  final int priceCents;
  final int periodDays;
  final bool active;
  final int sortOrder;
  final int subscribers;

  static AdminPlanConfig fromMap(Map<String, dynamic> m) => AdminPlanConfig(
    key: '${m['key']}',
    label: '${m['label']}',
    priceCents: (m['price_usd_cents'] as num?)?.toInt() ?? 0,
    periodDays: (m['period_days'] as num?)?.toInt() ?? 30,
    active: m['active'] == true,
    sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
    subscribers: (m['subscribers'] as num?)?.toInt() ?? 0,
  );
}

/// An operator account, from `admin_admins`.
class AdminAccountRow {
  const AdminAccountRow({
    required this.email,
    required this.role,
    required this.active,
    this.createdAt,
    this.lastLoginAt,
  });

  final String email;
  final String role;
  final bool active;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  static AdminAccountRow fromMap(Map<String, dynamic> m) => AdminAccountRow(
    email: '${m['email']}',
    role: (m['role'] as String?) ?? 'admin',
    active: m['active'] == true,
    createdAt: _dt(m['created_at']),
    lastLoginAt: _dt(m['last_login_at']),
  );
}

/// One entry in `admin_audit_log`.
class AdminAuditRow {
  const AdminAuditRow({
    required this.actor,
    required this.action,
    this.target,
    this.details = const {},
    this.createdAt,
  });

  final String actor;
  final String action;
  final String? target;
  final Map<String, dynamic> details;
  final DateTime? createdAt;

  static AdminAuditRow fromMap(Map<String, dynamic> m) => AdminAuditRow(
    actor: '${m['actor']}',
    action: '${m['action']}',
    target: m['target'] as String?,
    details: m['details'] is Map
        ? (m['details'] as Map).cast<String, dynamic>()
        : const {},
    createdAt: _dt(m['created_at']),
  );
}

/// A promo redemption, from `admin_redemptions`.
class AdminRedemptionRow {
  const AdminRedemptionRow({
    required this.code,
    required this.fingerprint,
    this.planKey,
    this.percentOff = 0,
    this.amountBefore = 0,
    this.amountAfter = 0,
    this.createdAt,
  });

  final String code;
  final String fingerprint;
  final String? planKey;
  final int percentOff;
  final int amountBefore;
  final int amountAfter;
  final DateTime? createdAt;

  static AdminRedemptionRow fromMap(Map<String, dynamic> m) =>
      AdminRedemptionRow(
        code: '${m['code']}',
        fingerprint: '${m['fingerprint']}',
        planKey: m['plan_key'] as String?,
        percentOff: (m['percent_off'] as num?)?.toInt() ?? 0,
        amountBefore: (m['amount_before'] as num?)?.toInt() ?? 0,
        amountAfter: (m['amount_after'] as num?)?.toInt() ?? 0,
        createdAt: _dt(m['created_at']),
      );
}

DateTime? _dt(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// Admin-managed paywall display config, from the `subscription_config` RPC.
///
/// The launch discount lives in the database so it can change without a
/// release; the card must quote whatever the server will actually charge.
class SubscriptionConfig {
  const SubscriptionConfig({
    this.launchDiscountPct = 0,
    this.displayCurrency = 'USD',
  });

  final int launchDiscountPct;
  final String displayCurrency;

  static SubscriptionConfig fromMap(Map<String, dynamic> m) =>
      SubscriptionConfig(
        launchDiscountPct: ((m['launch_discount_pct'] as num?)?.toInt() ?? 0)
            .clamp(0, 100),
        displayCurrency: (m['display_currency'] as String?)?.isNotEmpty == true
            ? m['display_currency'] as String
            : 'USD',
      );
}

/// Formats USD cents as `$2.00`.
String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Compact billing-period suffix for a plan: `/mo` for a ~monthly period,
/// `/yr` for ~yearly, else `/Nd`. Keeps the card honest when a plan is not
/// monthly rather than hardcoding `/mo`.
String periodSuffix(int periodDays) {
  if (periodDays >= 360) return '/yr';
  if (periodDays >= 28 && periodDays <= 31) return '/mo';
  return '/${periodDays}d';
}

/// Spelled-out billing period for labels, e.g. `monthly` / `yearly`.
String periodWord(int periodDays) {
  if (periodDays >= 360) return 'yearly';
  if (periodDays >= 28 && periodDays <= 31) return 'monthly';
  return 'every $periodDays days';
}

/// Outcome of a seat operation (`create_device_code`, `link_device`,
/// `revoke_device_seat`).
///
/// The server answers expected refusals as `{ok: false, error: '<code>'}` rather
/// than raising, so [error] is a stable token the UI turns into copy instead of
/// a message that has to be parsed.
class SeatResult {
  const SeatResult._({
    required this.ok,
    this.error,
    this.planKey,
    this.periodEnd,
    this.seatsUsed,
    this.seatLimit,
    this.code,
    this.expiresAt,
  });

  static SeatResult fromMap(Map<String, dynamic> m) => SeatResult._(
    ok: m['ok'] == true,
    error: m['error'] as String?,
    planKey: m['plan_key'] as String?,
    periodEnd: _dt(m['period_end']),
    seatsUsed: (m['seats_used'] as num?)?.toInt(),
    seatLimit: (m['seat_limit'] as num?)?.toInt(),
    code: m['code'] as String?,
    expiresAt: _dt(m['expires_at']),
  );

  final bool ok;
  final String? error;
  final String? planKey;
  final DateTime? periodEnd;
  final int? seatsUsed;
  final int? seatLimit;

  /// The 8-character code, when this was a `create_device_code` call.
  final String? code;
  final DateTime? expiresAt;

  /// Copy for [error], so every surface words a refusal the same way.
  String get message => switch (error) {
    'not_entitled' => 'This device has no active plan to share.',
    'linked_device' => "A device on someone else's plan can't add devices.",
    'no_seats' => 'Every device on this plan is already in use.',
    'bad_code' => 'That code is wrong or has expired.',
    'own_code' => 'That code is for this device.',
    'already_linked' => 'This device is already on a plan.',
    'own_subscription' => 'This device already has its own subscription.',
    'plan_ended' => "That plan has ended, so it can't add devices.",
    'too_many_attempts' => 'Too many tries. Wait an hour and try again.',
    'code_busy' => 'Could not make a code. Try again.',
    'not_found' => 'That device is no longer on this plan.',
    _ => "That didn't work. Try again.",
  };
}

/// One device sharing a plan, from `device_seat_list`.
class DeviceSeat {
  const DeviceSeat({
    required this.fingerprint,
    this.label,
    this.platform,
    this.model,
    this.addedAt,
    this.lastSeenAt,
    this.isSelf = false,
  });

  final String fingerprint;
  final String? label;
  final String? platform;
  final String? model;
  final DateTime? addedAt;
  final DateTime? lastSeenAt;
  final bool isSelf;

  /// What the list shows: the name the owner gave it, else the hardware, else
  /// the tail of the fingerprint so two unlabelled phones stay distinguishable.
  String get displayName {
    final named = label?.trim();
    if (named != null && named.isNotEmpty) return named;
    final hardware = [platform, model]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' · ');
    if (hardware.isNotEmpty) return hardware;
    final tail = fingerprint.length > 4
        ? fingerprint.substring(fingerprint.length - 4)
        : fingerprint;
    return 'Device $tail';
  }

  static DeviceSeat fromMap(Map<String, dynamic> m) => DeviceSeat(
    fingerprint: '${m['fingerprint']}',
    label: m['label'] as String?,
    platform: m['platform'] as String?,
    model: m['device_model'] as String?,
    addedAt: _dt(m['added_at']),
    lastSeenAt: _dt(m['last_seen_at']),
    isSelf: m['is_self'] == true,
  );
}

/// The seat picture for this plan: the cap, how much of it is used, and who is
/// on it. `seats_used` counts the owner, so a 2-device plan with one friend on
/// it reports 2 of 2.
class SeatSummary {
  const SeatSummary({
    this.seatLimit = 1,
    this.seatsUsed = 1,
    this.isSeat = false,
    this.seats = const [],
  });

  final int seatLimit;
  final int seatsUsed;

  /// True when this device is the guest rather than the plan owner.
  final bool isSeat;
  final List<DeviceSeat> seats;

  int get seatsLeft => (seatLimit - seatsUsed).clamp(0, 99);

  static SeatSummary fromMap(Map<String, dynamic> m) => SeatSummary(
    seatLimit: (m['seat_limit'] as num?)?.toInt() ?? 1,
    seatsUsed: (m['seats_used'] as num?)?.toInt() ?? 1,
    isSeat: m['is_seat'] == true,
    seats:
        (m['seats'] as List?)
            ?.whereType<Map>()
            .map((e) => DeviceSeat.fromMap(e.cast<String, dynamic>()))
            .toList() ??
        const [],
  );
}
