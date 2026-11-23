import 'dart:async';

import 'package:flutter/foundation.dart';

import '../di/injector.dart';
import 'entitlement_cache.dart';
import 'subscription_models.dart';
import 'subscription_repository.dart';

/// The visible trial window. [remaining] is recomputed every second from the
/// server clock captured when the identity was last read, not from the device
/// clock, so changing the device time does not stretch the trial.
class TrialCountdown {
  const TrialCountdown({required this.endsAt, required this.remaining});

  final DateTime endsAt;
  final Duration remaining;

  /// Compact label for the top-left badge: `13d 4h`, `4h 12m`, `12m 08s`.
  String get compactLabel {
    if (remaining.inDays > 0) {
      return '${remaining.inDays}d ${remaining.inHours % 24}h';
    }
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
    }
    final seconds = remaining.inSeconds % 60;
    return '${remaining.inMinutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}

/// App-wide trial clock. One instance lives for the process lifetime.
///
/// It only produces a countdown when the server says the current entitlement
/// is a trial (`DeviceIdentity.isTrial`). A paid subscription clears it, even
/// if the device once used a trial.
///
/// Expiry is signalled through [expired] after the last second runs out. The
/// subscription gate listens and opens the non-dismissible paywall. The timer
/// is stopped when the trial is no longer the active entitlement.
class TrialCountdownController {
  TrialCountdownController._();

  static final TrialCountdownController instance = TrialCountdownController._();

  final ValueNotifier<TrialCountdown?> countdown =
      ValueNotifier<TrialCountdown?>(null);

  /// Flips true once an active trial reaches its end. The gate consumes this
  /// event; it is not a persistent "paywall forever" flag.
  final ValueNotifier<bool> expired = ValueNotifier<bool>(false);

  SubscriptionApi? _api;
  DeviceIdentity? _identity;
  DateTime? _serverNow;
  Duration _baseElapsed = Duration.zero;
  Stopwatch? _stopwatch;
  Timer? _ticker;
  bool _started = false;
  bool _notifyExpiry = true;
  Object? _owner;

  /// Test seam: fake time advances without waiting on the wall clock.
  @visibleForTesting
  DateTime Function()? debugNow;

  DeviceIdentity? get identity => _identity;

  /// Reads the cached verdict so a countdown appears immediately after a cold
  /// start, then lets the launch gate's fresh server call replace it.
  Future<void> start({SubscriptionApi? api}) async {
    if (_started) return;
    _api = api ?? _registeredApi();
    if (_api == null) return;
    _started = true;

    final cached = await EntitlementCache.read();
    if (cached == null) return;
    update(cached.identity, checkedAt: cached.checkedAt, notifyExpiry: false);
  }

  /// Re-reads the server identity. Safe to call on resume or after an unlock.
  Future<void> refresh({SubscriptionApi? api}) async {
    if (api != null) _api = api;
    final source = _api ?? _registeredApi();
    if (source == null) return;
    _api = source;
    final identity = await source.identify();
    if (identity != null) update(identity);
  }

  /// Replaces the current window. [checkedAt] is the local time the identity
  /// was cached, so an offline cold start still advances the clock instead of
  /// restarting it.
  void update(
    DeviceIdentity? identity, {
    DateTime? checkedAt,
    bool notifyExpiry = true,
  }) {
    if (identity == null ||
        !identity.isTrial ||
        !identity.entitled ||
        identity.periodEnd == null) {
      _stop();
      return;
    }

    _identity = identity;
    _serverNow = identity.serverNow?.toUtc();
    _baseElapsed = _safeElapsed(checkedAt);
    _stopwatch = Stopwatch()..start();
    _notifyExpiry = notifyExpiry;
    expired.value = false;
    _tick();
  }

  Duration _safeElapsed(DateTime? checkedAt) {
    if (checkedAt == null) return Duration.zero;
    final elapsed = DateTime.now().toUtc().difference(checkedAt.toUtc());
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  DateTime _now() {
    final testNow = debugNow;
    if (testNow != null) return testNow().toUtc();
    final server = _serverNow;
    if (server == null) return DateTime.now().toUtc();
    return server.add(_baseElapsed).add(_stopwatch?.elapsed ?? Duration.zero);
  }

  void _tick() {
    final identity = _identity;
    final end = identity?.periodEnd?.toUtc();
    if (identity == null || end == null) {
      _stop();
      return;
    }

    final left = end.difference(_now());
    if (left <= Duration.zero) {
      _stop(expiredNow: _notifyExpiry);
      return;
    }

    countdown.value = TrialCountdown(endsAt: end, remaining: left);
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stop({bool expiredNow = false}) {
    _ticker?.cancel();
    _ticker = null;
    _identity = null;
    _serverNow = null;
    _baseElapsed = Duration.zero;
    _stopwatch = null;
    countdown.value = null;
    expired.value = expiredNow;
  }

  SubscriptionApi? _registeredApi() =>
      sl.isRegistered<SubscriptionApi>() ? sl<SubscriptionApi>() : null;

  /// Ties the clock to the gate that started it. A replacement gate attaches
  /// before the old one is disposed, so the old gate's [detach] cannot clear
  /// the new gate's countdown.
  void attach(Object owner) => _owner = owner;

  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    stop();
  }

  /// Stops the timer and removes the badge. Called when the launch gate is
  /// disposed; the next gate instance calls [start] again.
  void stop() {
    _stop();
    _started = false;
  }

  @visibleForTesting
  void debugReset() {
    stop();
    _owner = null;
    _api = null;
    _notifyExpiry = true;
    debugNow = null;
  }
}
