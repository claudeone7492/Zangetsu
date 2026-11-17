import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
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
    if (identity == null) return true;
    return identity.entitled || !identity.showPaywall;
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
