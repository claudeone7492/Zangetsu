import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/subscription/subscription_repository.dart';
import 'paywall_screen.dart';

/// Ensures this device is entitled before playback starts.
///
/// Returns true when the caller may proceed. A device the server marks as
/// unentitled is shown the paywall; if it is still unentitled afterwards the
/// caller must stop.
///
/// Fails OPEN when the server cannot be reached ([identify] returns null): a
/// network blip must not lock a paying viewer out of a stream they already
/// hold. It fails CLOSED only on an explicit server verdict, which is what
/// makes the trial gate hold after day 14.
Future<bool> ensureEntitled(BuildContext context, {String? reason}) async {
  if (!sl.isRegistered<SubscriptionRepository>()) return true;

  final identity = await sl<SubscriptionRepository>().identify();
  if (identity == null) return true;
  if (identity.entitled || !identity.showPaywall) return true;

  if (!context.mounted) return false;
  return showPaywall(context, reason: reason);
}
