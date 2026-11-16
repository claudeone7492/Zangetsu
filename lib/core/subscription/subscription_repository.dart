import 'package:supabase_flutter/supabase_flutter.dart';

import '../device/device_fingerprint.dart';
import 'subscription_models.dart';

/// The subscription surface the UI depends on. An interface so the cubits can
/// be exercised without a live Supabase client, and so the RPC-backed
/// implementation stays the only place that knows about the network.
abstract class SubscriptionApi {
  Future<List<SubscriptionPlan>> plans();
  Future<DeviceIdentity?> identify();
  Future<PromoResult?> resolvePromo(String code, {String? planKey});
  Future<int?> redeemPromo({
    required String code,
    required String planKey,
    required int beforeCents,
    required int afterCents,
  });
  Future<String?> startTrial(String planKey);

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
    } catch (_) {
      // Offline, not signed in, or the function errored: callers treat null as
      // "unknown" and stay on the cached/local state rather than blocking.
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

  /// Upserts this device and returns its identity + subscription. Call on boot.
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
    });
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
