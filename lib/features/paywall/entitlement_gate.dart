import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/logging/app_logger.dart';
import '../../core/subscription/subscription_repository.dart';
import 'paywall_screen.dart';

/// The server's verdict on whether this device may proceed: entitled, or the
/// server is not asking for the paywall.
///
/// Fails OPEN when the server cannot be reached ([identify] returns null): a
/// network blip must not lock a paying viewer out of a stream they already
/// hold. It fails CLOSED only on an explicit server verdict, which is what
/// makes the trial gate hold after day 14 and the launch gate hold a new device.
Future<bool> deviceEntitled({SubscriptionApi? api}) async {
  final repo =
      api ??
      (sl.isRegistered<SubscriptionRepository>()
          ? sl<SubscriptionRepository>()
          : null);
  if (repo == null) return true;

  try {
    final identity = await repo.identify();
    if (identity == null) {
      // No verdict: the device is offline, or the RPC failed (logged by the
      // repository). Allowing access is deliberate — a paying viewer must not
      // be locked out by a network blip.
      AppLogger.instance.log('[paywall] no server verdict — allowing access');
      return true;
    }
    final allowed = identity.entitled || !identity.showPaywall;
    if (!allowed) {
      AppLogger.instance.log(
        '[paywall] device not entitled (status=${identity.status}, '
        'trial_used=${identity.trialUsed}, plan=${identity.planKey ?? "-"}) '
        '— showing the subscription card',
      );
    }
    return allowed;
  } catch (_) {
    return true;
  }
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
