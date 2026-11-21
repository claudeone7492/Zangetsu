import 'dart:async';

import 'package:flutter/foundation.dart';

/// Ported from Hikari's `providers/ExtensionRecovery.kt`.
///
/// A JS-pack runtime that times out twice in a row is wedged: every later
/// call queues behind the same stuck work and the provider looks dead until
/// the app restarts. This counts consecutive stalls per provider and says
/// when to drop its cached runtime; the caller does the eviction, because
/// only it knows how its engine is built.
///
/// Two recovery paths, as in Hikari:
///  * [shouldRecover] — N consecutive timeouts, 30 s between attempts.
///  * [shouldRecoverEmpty] — the provider answered but with nothing, one
///    clean-room retry a minute.
class ExtensionRecovery {
  const ExtensionRecovery._();

  /// Consecutive timed-out calls before a provider is declared wedged.
  static const int stallsToRecover = 2;

  /// Minimum gap between two recoveries of the same provider.
  static const Duration recoverCooldown = Duration(seconds: 30);

  /// Minimum gap between two clean-room retries of the same provider.
  static const Duration emptyRecoverCooldown = Duration(seconds: 60);

  static final Map<String, int> _stalls = <String, int>{};
  static final Map<String, DateTime> _lastRecoverAt = <String, DateTime>{};
  static final Map<String, DateTime> _lastEmptyRecoverAt = <String, DateTime>{};

  /// Records a timed-out (or gate-stalled) call; returns the consecutive
  /// count.
  static int noteTimeout(String providerId) {
    final next = (_stalls[providerId] ?? 0) + 1;
    _stalls[providerId] = next;
    return next;
  }

  /// Records any real answer (servers OR an honest empty): the provider lives.
  static void noteSuccess(String providerId) => _stalls.remove(providerId);

  static int stalls(String providerId) => _stalls[providerId] ?? 0;

  /// True when the provider may be recovered right now (count + cooldown).
  static bool shouldRecover(String providerId, {DateTime? now}) {
    if (stalls(providerId) < stallsToRecover) return false;
    final last = _lastRecoverAt[providerId];
    if (last == null) return true;
    return (now ?? DateTime.now()).difference(last) >= recoverCooldown;
  }

  /// Stamps a recovery so the next one waits out [recoverCooldown].
  static void markRecovered(String providerId, {DateTime? now}) {
    _lastRecoverAt[providerId] = now ?? DateTime.now();
  }

  /// True when an answered-empty provider gets its one clean-room retry.
  static bool shouldRecoverEmpty(String providerId, {DateTime? now}) {
    final last = _lastEmptyRecoverAt[providerId];
    if (last == null) return true;
    return (now ?? DateTime.now()).difference(last) >= emptyRecoverCooldown;
  }

  static void markRecoveredEmpty(String providerId, {DateTime? now}) {
    _lastEmptyRecoverAt[providerId] = now ?? DateTime.now();
  }

  /// Wraps one provider call: counts stalls, clears them on any answer, and
  /// runs [recover] once when the provider is wedged. Returns [call]'s value;
  /// its error is rethrown after the bookkeeping, so callers see exactly what
  /// they saw before.
  static Future<T> guard<T>(
    String providerId,
    Future<T> Function() call, {
    Future<void> Function()? recover,
  }) async {
    try {
      final value = await call();
      noteSuccess(providerId);
      return value;
    } on TimeoutException {
      noteTimeout(providerId);
      if (recover != null && shouldRecover(providerId)) {
        markRecovered(providerId);
        unawaited(recover());
      }
      rethrow;
    }
  }

  @visibleForTesting
  static void reset() {
    _stalls.clear();
    _lastRecoverAt.clear();
    _lastEmptyRecoverAt.clear();
  }
}
