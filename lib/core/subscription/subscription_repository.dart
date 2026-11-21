import 'package:supabase_flutter/supabase_flutter.dart';

import '../device/device_fingerprint.dart';
import '../logging/app_logger.dart';
import 'subscription_models.dart';

/// The subscription surface the UI depends on. An interface so the cubits can
/// be exercised without a live Supabase client, and so the RPC-backed
/// implementation stays the only place that knows about the network.
abstract class SubscriptionApi {
  Future<List<SubscriptionPlan>> plans();
  Future<SubscriptionConfig> config();
  Future<DeviceIdentity?> identify();
  Future<PromoResult?> resolvePromo(String code, {String? planKey});
  Future<int?> redeemPromo({
    required String code,
    required String planKey,
    required int beforeCents,
    required int afterCents,
  });
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

  Future<bool> adminConfigured();
  Future<bool> adminCheck(String passcode);
  Future<bool> adminSetup(String passcode);
  Future<bool> adminClaim(String passcode);
  Future<List<AdminDeviceRow>> adminDevices(String passcode);
  Future<List<AdminPromoRow>> adminPromos(String passcode);
  Future<List<AdminPlanRow>> adminSubscriptions(String passcode);
  Future<bool> adminSetPromo({
    required String passcode,
    required String code,
    required int percentOff,
    bool active,
    DateTime? expiresAt,
    int? maxUses,
  });
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
      // Offline or the function errored: callers treat null as "unknown" and
      // stay on the cached/local state rather than blocking. Logged because a
      // silent null here is what made a missing paywall impossible to diagnose
      // from the field — the gate fails open on it.
      AppLogger.instance.log('[subscription] $fn failed: $e', level: 'E');
      return null;
    }
  }

  static List<Map<String, dynamic>> _rows(Object? data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
    }
    if (data is Map) return [data.cast<String, dynamic>()];
    return const [];
  }

  /// Plans for the paywall.
  @override
  Future<List<SubscriptionPlan>> plans() async {
    final res = await _rpc('list_plans', const {}, (d) {
      return _rows(d)
          .map(SubscriptionPlan.fromMap)
          .whereType<SubscriptionPlan>()
          .toList();
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
  /// with no way out. A timeout reads as "no verdict", which the gate treats as
  /// fail-open.
  @override
  Future<DeviceIdentity?> identify() async {
    await DeviceFingerprint.warmSignals();
    final fp = await _fingerprint();
    return _rpc('identify_device', {
      'p_fingerprint': fp,
      'p_platform': DeviceFingerprint.platform,
      'p_model': DeviceFingerprint.model,
    }, (d) {
      final rows = _rows(d);
      return rows.isEmpty ? null : DeviceIdentity.fromMap(rows.first);
    }).timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  /// Resolves a typed code. Returns null when unknown/inactive/expired.
  @override
  Future<PromoResult?> resolvePromo(String code, {String? planKey}) => _rpc(
    'resolve_promo',
    {'p_code': code, 'p_plan': planKey},
    (d) {
      final rows = _rows(d);
      return rows.isEmpty ? null : PromoResult.fromMap(rows.first);
    },
  );

  /// Records a redemption against this device and bumps the counter.
  @override
  Future<int?> redeemPromo({
    required String code,
    required String planKey,
    required int beforeCents,
    required int afterCents,
  }) async {
    final fp = await _fingerprint();
    return _rpc('redeem_promo', {
      'p_code': code,
      'p_fingerprint': fp,
      'p_plan': planKey,
      'p_before': beforeCents,
      'p_after': afterCents,
    }, (d) => (d as num?)?.toInt());
  }

  /// Grants the one-time trial for a first-time device. Returns the new
  /// subscription id, or null when the device already used its trial.
  @override
  Future<String?> startTrial(String planKey) async {
    final fp = await _fingerprint();
    return _rpc(
      'start_trial',
      {'p_fingerprint': fp, 'p_plan': planKey},
      (d) => d is String ? d : null,
    );
  }

  /// Mints a join code for this plan.
  @override
  Future<SeatResult?> createDeviceCode() async {
    final fp = await _fingerprint();
    return _rpc(
      'create_device_code',
      {'p_fingerprint': fp},
      _firstSeatResult,
    );
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
    final res = await _rpc(
      'revoke_device_seat',
      {'p_fingerprint': fp, 'p_seat_fingerprint': fingerprint},
      (d) => _firstSeatResult(d)?.ok,
    );
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
      return const CheckoutResult(ok: false, free: false, error: 'bad_response');
    } catch (e) {
      return CheckoutResult(ok: false, free: false, error: '$e');
    }
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
  Future<bool> adminSetup(String passcode) async =>
      await _rpc('admin_setup', {'p_passcode': passcode}, (d) => d == true) ??
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
      await _rpc(
        'admin_devices',
        {'p_passcode': passcode},
        (d) => _rows(d).map(AdminDeviceRow.fromMap).toList(),
      ) ??
      const [];

  @override
  Future<List<AdminPromoRow>> adminPromos(String passcode) async =>
      await _rpc(
        'admin_promos',
        {'p_passcode': passcode},
        (d) => _rows(d).map(AdminPromoRow.fromMap).toList(),
      ) ??
      const [];

  @override
  Future<List<AdminPlanRow>> adminSubscriptions(String passcode) async =>
      await _rpc(
        'admin_subscriptions',
        {'p_passcode': passcode},
        (d) => _rows(d).map(AdminPlanRow.fromMap).toList(),
      ) ??
      const [];

  @override
  Future<bool> adminSetPromo({
    required String passcode,
    required String code,
    required int percentOff,
    bool active = true,
    DateTime? expiresAt,
    int? maxUses,
  }) async => await _rpc('admin_set_promo', {
        'p_passcode': passcode,
        'p_code': code,
        'p_percent_off': percentOff,
        'p_active': active,
        'p_expires_at': expiresAt?.toUtc().toIso8601String(),
        'p_max_uses': maxUses,
      }, (d) => d == true) ??
      false;
}
