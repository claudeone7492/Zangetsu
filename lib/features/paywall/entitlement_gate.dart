import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/logging/app_logger.dart';
import '../../core/subscription/entitlement_cache.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';
import 'paywall_screen.dart';

/// The server's verdict on whether this device may proceed: entitled, or the
/// server is not asking for the paywall.
///
/// A fresh verdict is authoritative and is cached. When the server cannot be
/// reached, the last verdict is honoured only while its period is still
/// running. With no usable cache the gate fails CLOSED, so turning the network
/// off cannot extend an entitlement or bypass the paywall.
Future<bool> deviceEntitled({SubscriptionApi? api}) async {
  final repo =
      api ??
      (sl.isRegistered<SubscriptionRepository>()
          ? sl<SubscriptionRepository>()
          : null);
  if (repo == null) return true;

  DeviceIdentity? identity;
  try {
    identity = await repo.identify();
  } catch (_) {
    identity = null;
  }

  if (identity != null) {
    await EntitlementCache.save(identity);
    final allowed = identity.entitled || !identity.showPaywall;
    if (!allowed) {
      AppLogger.instance.log(
        '[paywall] device not entitled (status=${identity.status}, '
        'plan=${identity.planKey ?? "-"}) — showing the subscription card',
      );
    }
    return allowed;
  }

  return _cachedVerdict();
}

/// Offline path: trust only a still-running cached entitlement.
Future<bool> _cachedVerdict() async {
  final cached = await EntitlementCache.read();
  if (cached == null) {
    AppLogger.instance.log(
      '[paywall] no server verdict and no cached entitlement — blocking',
    );
    return false;
  }

  final now = DateTime.now().toUtc();
  if (cached.checkedAt.isAfter(now.add(const Duration(minutes: 2)))) {
    // A clock moved backwards must not resurrect a lapsed period. Two minutes
    // tolerates normal NTP drift without allowing a meaningful rollback.
    AppLogger.instance.log(
      '[paywall] cached verdict timestamp is in the future',
    );
    return false;
  }

  final identity = cached.identity;
  if (!identity.entitled && identity.showPaywall) {
    AppLogger.instance.log('[paywall] cached verdict says unentitled');
    return false;
  }

  final end = identity.periodEnd?.toUtc();
  if (end != null) {
    final stillRunning = now.isBefore(end);
    AppLogger.instance.log(
      '[paywall] cached verdict ${stillRunning ? "allows" : "denies"} access '
      'until ${end.toIso8601String()}',
    );
    return stillRunning;
  }

  // No period end (older server shape): allow a short offline window only.
  final fresh = now.difference(cached.checkedAt) <= const Duration(hours: 24);
  AppLogger.instance.log(
    '[paywall] cached verdict without period_end — '
    '${fresh ? "allowing" : "blocking"} after 24h',
  );
  return fresh;
}

/// Ensures this device is entitled before playback starts.
///
/// Returns true when the caller may proceed. A device the server marks as
/// unentitled is shown the paywall; if it is still unentitled afterwards the
/// caller must stop.
Future<bool> ensureEntitled(BuildContext context, {String? reason}) async {
  if (await deviceEntitled()) return true;

  if (!context.mounted) return false;
  return showPaywall(context, reason: reason);
}
