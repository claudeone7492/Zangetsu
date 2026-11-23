import 'package:supabase_flutter/supabase_flutter.dart';

import '../device/device_fingerprint.dart';
import '../logging/app_logger.dart';
import 'entitlement_cache.dart';
import 'subscription_models.dart';

/// The subscription surface the UI depends on. An interface so the cubits can
/// be exercised without a live Supabase client, and so the RPC-backed
/// implementation stays the only place that knows about the network.
abstract class SubscriptionApi {
  Future<List<SubscriptionPlan>> plans();
  Future<SubscriptionConfig> config();
  Future<DeviceIdentity?> identify();

  /// Resolves a typed code for this device. The result carries `alreadyUsed`
  /// so the paywall can explain that the code has expired for this device.
  Future<PromoResult?> resolvePromo(String code, {String? planKey});
  Future<String?> startTrial(String planKey);

  /// Mints a short code this device's plan can be joined with. Null when the
  /// call itself failed; a refusal comes back as `SeatResult(ok: false)`.
  Future<SeatResult?> createDeviceCode();

  /// Joins the plan behind [code]. On success this device is a seat and
  /// `identify()` starts reporting it entitled.
  Future<SeatResult?> linkDevice(String code, {String? label});

  /// The devices sharing this plan, with the cap.
  Future<SeatSummary?> deviceSeats();

  /// Frees a seat. The owner may drop any seat; a guest may drop its own.
  Future<bool> revokeDeviceSeat(String fingerprint);

  /// Starts a checkout for [planKey] on this device and returns the result,
  /// which carries either a Korapay checkout URL or a free-access grant.
  Future<CheckoutResult> startCheckout({
    required String planKey,
    String? promoCode,
  });

  /// Payments initiated by this device, newest first. A shared-plan guest gets
  /// its own (usually empty) history, not the payer's card history.
  Future<List<DeviceTransaction>?> transactions() async => const [];

  Future<bool> adminConfigured();
  Future<bool> adminCheck(String passcode);

  /// Email/password login for the admin console. The server hashes the
  /// password and checks it against the admin row; the password is kept only
  /// in memory for the session.
  Future<bool> adminLogin(String email, String password);

  /// First-run admin registration. Refused once an active admin exists.
  Future<bool> adminRegister(String email, String password);
  Future<bool> adminSetup(String passcode);
  Future<bool> adminClaim(String passcode);
  Future<List<AdminDeviceRow>> adminDevices(String passcode);
  Future<List<AdminPromoRow>> adminPromos(String passcode);
  Future<List<AdminPlanRow>> adminSubscriptions(String passcode);

  /// Grants a fresh trial period to [fingerprint]. This is the only supported
  /// way to extend a device after its trial has lapsed.
  Future<bool> adminRefreshTrial({
    required String passcode,
    required String fingerprint,
    int days = 14,
  });

  Future<bool> adminSetPromo({
    required String passcode,
    required String code,
    required int percentOff,
    bool active,
    DateTime? expiresAt,
    int? maxUses,
  });

  /// Dashboard totals. Concrete default keeps existing fakes compiling.
  Future<AdminOverview?> adminOverview(String passcode) async => null;

  /// The editable plan catalogue (price, trial, active).
  Future<List<AdminPlanConfig>> adminPlans(String passcode) async => const [];

  Future<bool> adminUpdatePlan({
    required String passcode,
    required String key,
    required int priceCents,
    int? trialDays,
    bool? active,
  }) async => false;

  Future<Map<String, dynamic>?> adminConfig(String passcode) async => null;

  Future<bool> adminUpdateConfig({
    required String passcode,
    int? launchDiscountPct,
    String? displayCurrency,
  }) async => false;

  Future<bool> adminSetDeviceBlocked({
    required String passcode,
    required String fingerprint,
    required bool blocked,
    String? note,
  }) async => false;

  Future<bool> adminGrantSubscription({
    required String passcode,
    required String fingerprint,
    int days = 30,
    String planKey = 'stream_standard',
    String? note,
  }) async => false;

  Future<bool> adminRevokeSubscription({
    required String passcode,
    required String fingerprint,
    String? reason,
  }) async => false;

  Future<bool> adminRevokeSeat({
    required String passcode,
    required String ownerFingerprint,
    required String seatFingerprint,
  }) async => false;

  Future<bool> adminDeletePromo({
    required String passcode,
    required String code,
  }) async => false;

  Future<List<AdminRedemptionRow>> adminRedemptions(String passcode) async =>
      const [];

  Future<List<AdminAccountRow>> adminAdmins(String passcode) async => const [];

  Future<bool> adminCreateAdmin({
    required String passcode,
    required String email,
    required String password,
  }) async => false;

  Future<bool> adminSetAdminActive({
    required String passcode,
    required String email,
    required bool active,
  }) async => false;

  Future<bool> adminChangePassword({
    required String passcode,
    required String newPassword,
  }) async => false;

  Future<List<AdminAuditRow>> adminAudit(String passcode) async => const [];
}

/// All subscription + admin data access, via SECURITY DEFINER RPCs.
///
/// The app never reads the underlying tables: the promo catalogue, device
/// registry and subscription rows are service-role only, so nothing here can
/// enumerate codes or read other devices. Everything goes through a function
/// that enforces its own rules.
class SubscriptionRepository implements SubscriptionApi {
  SubscriptionRepository(this._client, {Future<String> Function()? fingerprint})
    : _fingerprint = fingerprint ?? DeviceFingerprint.value;

  final SupabaseClient _client;
  final Future<String> Function() _fingerprint;

  Future<T?> _rpc<T>(
    String fn,
    Map<String, dynamic> params,
    T? Function(Object? data) parse,
  ) async {
    try {
      final data = await _client.rpc(fn, params: params);
      return parse(data);
    } catch (e) {
      // Offline or the function errored: callers treat null as "unknown".
      // The gate then reads the cached verdict and, with no usable cache,
      // fails closed. Logged so a missing paywall is diagnosable from the
      // field.
      AppLogger.instance.log('[subscription] $fn failed: $e', level: 'E');
      return null;
    }
  }

  static List<Map<String, dynamic>> _rows(Object? data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (data is Map) return [data.cast<String, dynamic>()];
    return const [];
  }

  /// Plans for the paywall.
  @override
  Future<List<SubscriptionPlan>> plans() async {
    final res = await _rpc('list_plans', const {}, (d) {
      return _rows(
        d,
      ).map(SubscriptionPlan.fromMap).whereType<SubscriptionPlan>().toList();
    });
    return res ?? const [];
  }

  /// Paywall display config (launch discount, display currency).
  ///
  /// Falls back to [SubscriptionConfig]'s defaults — a 0% discount — when the
  /// call fails, so an offline paywall never quotes a discount the server
  /// might not honour.
  @override
  Future<SubscriptionConfig> config() async {
    final res = await _rpc('subscription_config', const {}, (d) {
      final rows = _rows(d);
      return rows.isEmpty ? null : SubscriptionConfig.fromMap(rows.first);
    });
    return res ?? const SubscriptionConfig();
  }

  /// Upserts this device and returns its identity + subscription. Call on boot.
  ///
  /// Bounded: the launch gate awaits this before it can decide whether to show
  /// the card, so a hung connection would otherwise hold the app on a spinner
  /// with no way out. A timeout reads as "no verdict"; the gate then falls
  /// back to the last cached verdict instead of failing open.
  @override
  Future<DeviceIdentity?> identify() async {
    await DeviceFingerprint.warmSignals();
    final fp = await _fingerprint();
    final identity = await _rpc(
      'identify_device',
      {
        'p_fingerprint': fp,
        'p_platform': DeviceFingerprint.platform,
        'p_model': DeviceFingerprint.model,
      },
      (d) {
        final rows = _rows(d);
        return rows.isEmpty ? null : DeviceIdentity.fromMap(rows.first);
      },
    ).timeout(const Duration(seconds: 8), onTimeout: () => null);

    if (identity != null) await EntitlementCache.save(identity);
    return identity;
  }

  /// Resolves a typed code for this device. The result carries `alreadyUsed`
  /// so the paywall can explain that the code has expired for this device.
  @override
  Future<PromoResult?> resolvePromo(String code, {String? planKey}) async {
    final fp = await _fingerprint();
    return _rpc(
      'resolve_promo',
      {'p_code': code, 'p_plan': planKey, 'p_fingerprint': fp},
      (d) {
        final rows = _rows(d);
        return rows.isEmpty ? null : PromoResult.fromMap(rows.first);
      },
    );
  }

  /// Grants the one-time trial for a first-time device. Returns the new
  /// subscription id, or null when the device already used its trial.
  @override
  Future<String?> startTrial(String planKey) async {
    final fp = await _fingerprint();
    return _rpc('start_trial', {
      'p_fingerprint': fp,
      'p_plan': planKey,
    }, (d) => d is String ? d : null);
  }

  /// Mints a join code for this plan.
  @override
  Future<SeatResult?> createDeviceCode() async {
    final fp = await _fingerprint();
    return _rpc('create_device_code', {'p_fingerprint': fp}, _firstSeatResult);
  }

  /// Redeems [code] on this device.
  @override
  Future<SeatResult?> linkDevice(String code, {String? label}) async {
    final fp = await _fingerprint();
    return _rpc('link_device', {
      'p_code': code.trim().toUpperCase(),
      'p_fingerprint': fp,
      'p_label': label ?? DeviceFingerprint.model,
    }, _firstSeatResult);
  }

  /// Lists the devices on this plan.
  @override
  Future<SeatSummary?> deviceSeats() async {
    final fp = await _fingerprint();
    return _rpc('device_seat_list', {'p_fingerprint': fp}, (d) {
      final rows = _rows(d);
      return rows.isEmpty ? null : SeatSummary.fromMap(rows.first);
    });
  }

  /// Drops a seat from this plan.
  @override
  Future<bool> revokeDeviceSeat(String fingerprint) async {
    final fp = await _fingerprint();
    final res = await _rpc('revoke_device_seat', {
      'p_fingerprint': fp,
      'p_seat_fingerprint': fingerprint,
    }, (d) => _firstSeatResult(d)?.ok);
    return res ?? false;
  }

  /// The seat RPCs answer with one jsonb object; [_rows] normalises the
  /// list-or-object shape PostgREST can return.
  static SeatResult? _firstSeatResult(Object? data) {
    final rows = _rows(data);
    return rows.isEmpty ? null : SeatResult.fromMap(rows.first);
  }

  /// Starts a checkout through the `stream-subscribe` edge function.
  ///
  /// A function error is returned as a [CheckoutResult] with `ok == false`
  /// rather than thrown, so the UI can show a reason without a try/catch.
  @override
  Future<CheckoutResult> startCheckout({
    required String planKey,
    String? promoCode,
  }) async {
    final fp = await _fingerprint();
    try {
      final res = await _client.functions.invoke(
        'stream-subscribe',
        body: {
          'fingerprint': fp,
          'planKey': planKey,
          if (promoCode != null && promoCode.isNotEmpty) 'promoCode': promoCode,
        },
      );
      final data = res.data;
      if (data is Map) {
        return CheckoutResult.fromMap(data.cast<String, dynamic>());
      }
      return const CheckoutResult(
        ok: false,
        free: false,
        error: 'bad_response',
      );
    } catch (e) {
      return CheckoutResult(ok: false, free: false, error: '$e');
    }
  }

  @override
  Future<List<DeviceTransaction>?> transactions() async {
    final fp = await _fingerprint();
    return _rpc('device_transactions', {'p_fingerprint': fp}, (d) {
      return _rows(
        d,
      ).map(DeviceTransaction.fromMap).whereType<DeviceTransaction>().toList();
    });
  }

  // ---- Admin -------------------------------------------------------------

  @override
  Future<bool> adminConfigured() async =>
      await _rpc('admin_configured', const {}, (d) => d == true) ?? false;

  @override
  Future<bool> adminCheck(String passcode) async =>
      await _rpc('admin_check', {'p_passcode': passcode}, (d) => d == true) ??
      false;

  @override
  Future<bool> adminLogin(String email, String password) async =>
      await _rpc('admin_login', {
        'p_email': email.trim(),
        'p_password': password,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminRegister(String email, String password) async =>
      await _rpc('admin_register', {
        'p_email': email.trim(),
        'p_password': password,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminSetup(String passcode) async =>
      await _rpc('admin_setup', {'p_passcode': passcode}, (d) => d == true) ??
      false;

  @override
  Future<bool> adminRefreshTrial({
    required String passcode,
    required String fingerprint,
    int days = 14,
  }) async =>
      await _rpc('admin_refresh_trial', {
        'p_passcode': passcode,
        'p_fingerprint': fingerprint,
        'p_days': days,
      }, (d) => d is Map && d['ok'] == true) ??
      false;

  @override
  Future<bool> adminClaim(String passcode) async {
    final fp = await _fingerprint();
    return await _rpc('admin_claim', {
          'p_passcode': passcode,
          'p_fingerprint': fp,
        }, (d) => d == true) ??
        false;
  }

  @override
  Future<List<AdminDeviceRow>> adminDevices(String passcode) async =>
      await _rpc('admin_devices', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminDeviceRow.fromMap).toList()) ??
      const [];

  @override
  Future<List<AdminPromoRow>> adminPromos(String passcode) async =>
      await _rpc('admin_promos', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminPromoRow.fromMap).toList()) ??
      const [];

  @override
  Future<List<AdminPlanRow>> adminSubscriptions(String passcode) async =>
      await _rpc('admin_subscriptions', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminPlanRow.fromMap).toList()) ??
      const [];

  @override
  Future<bool> adminSetPromo({
    required String passcode,
    required String code,
    required int percentOff,
    bool active = true,
    DateTime? expiresAt,
    int? maxUses,
  }) async =>
      await _rpc('admin_set_promo', {
        'p_passcode': passcode,
        'p_code': code,
        'p_percent_off': percentOff,
        'p_active': active,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_max_uses': maxUses,
      }, (d) => d == true) ??
      false;

  @override
  Future<AdminOverview?> adminOverview(String passcode) => _rpc(
    'admin_overview',
    {'p_passcode': passcode},
    (d) => d is Map ? AdminOverview.fromMap(d.cast<String, dynamic>()) : null,
  );

  @override
  Future<List<AdminPlanConfig>> adminPlans(String passcode) async =>
      await _rpc('admin_plans', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminPlanConfig.fromMap).toList()) ??
      const [];

  @override
  Future<bool> adminUpdatePlan({
    required String passcode,
    required String key,
    required int priceCents,
    int? trialDays,
    bool? active,
  }) async =>
      await _rpc('admin_update_plan', {
        'p_passcode': passcode,
        'p_key': key,
        'p_price_usd_cents': priceCents,
        'p_trial_days': trialDays,
        'p_active': active,
      }, (d) => d == true) ??
      false;

  @override
  Future<Map<String, dynamic>?> adminConfig(String passcode) => _rpc(
    'admin_config',
    {'p_passcode': passcode},
    (d) => d is Map ? d.cast<String, dynamic>() : null,
  );

  @override
  Future<bool> adminUpdateConfig({
    required String passcode,
    int? launchDiscountPct,
    String? displayCurrency,
  }) async =>
      await _rpc('admin_update_config', {
        'p_passcode': passcode,
        'p_launch_discount_pct': launchDiscountPct,
        'p_display_currency': displayCurrency,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminSetDeviceBlocked({
    required String passcode,
    required String fingerprint,
    required bool blocked,
    String? note,
  }) async =>
      await _rpc('admin_set_device_blocked', {
        'p_passcode': passcode,
        'p_fingerprint': fingerprint,
        'p_blocked': blocked,
        'p_note': note,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminGrantSubscription({
    required String passcode,
    required String fingerprint,
    int days = 30,
    String planKey = 'stream_standard',
    String? note,
  }) async =>
      await _rpc('admin_grant_subscription', {
        'p_passcode': passcode,
        'p_fingerprint': fingerprint,
        'p_days': days,
        'p_plan_key': planKey,
        'p_note': note,
      }, (d) => d is Map && d['ok'] == true) ??
      false;

  @override
  Future<bool> adminRevokeSubscription({
    required String passcode,
    required String fingerprint,
    String? reason,
  }) async =>
      await _rpc('admin_revoke_subscription', {
        'p_passcode': passcode,
        'p_fingerprint': fingerprint,
        'p_reason': reason,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminRevokeSeat({
    required String passcode,
    required String ownerFingerprint,
    required String seatFingerprint,
  }) async =>
      await _rpc('admin_revoke_seat', {
        'p_passcode': passcode,
        'p_owner_fingerprint': ownerFingerprint,
        'p_seat_fingerprint': seatFingerprint,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminDeletePromo({
    required String passcode,
    required String code,
  }) async =>
      await _rpc('admin_delete_promo', {
        'p_passcode': passcode,
        'p_code': code,
      }, (d) => d == true) ??
      false;

  @override
  Future<List<AdminRedemptionRow>> adminRedemptions(String passcode) async =>
      await _rpc('admin_redemptions', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminRedemptionRow.fromMap).toList()) ??
      const [];

  @override
  Future<List<AdminAccountRow>> adminAdmins(String passcode) async =>
      await _rpc('admin_admins', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminAccountRow.fromMap).toList()) ??
      const [];

  @override
  Future<bool> adminCreateAdmin({
    required String passcode,
    required String email,
    required String password,
  }) async =>
      await _rpc('admin_create_admin', {
        'p_passcode': passcode,
        'p_email': email.trim(),
        'p_password': password,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminSetAdminActive({
    required String passcode,
    required String email,
    required bool active,
  }) async =>
      await _rpc('admin_set_admin_active', {
        'p_passcode': passcode,
        'p_email': email,
        'p_active': active,
      }, (d) => d == true) ??
      false;

  @override
  Future<bool> adminChangePassword({
    required String passcode,
    required String newPassword,
  }) async =>
      await _rpc('admin_change_password', {
        'p_passcode': passcode,
        'p_new_password': newPassword,
      }, (d) => d == true) ??
      false;

  @override
  Future<List<AdminAuditRow>> adminAudit(String passcode) async =>
      await _rpc('admin_audit', {
        'p_passcode': passcode,
      }, (d) => _rows(d).map(AdminAuditRow.fromMap).toList()) ??
      const [];
}
