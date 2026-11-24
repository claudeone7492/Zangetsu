import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/platform/apple_tv.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/theme/app_colors.dart';
import '../update/update_dialog.dart';
import 'entitlement_gate.dart';
import 'paywall_screen.dart';

/// Blocks the app until this device is entitled.
///
/// Sits above Home and the profile picker, so neither is built until the
/// paywall is passed — the premium subscription card is the first thing a new
/// (or lapsed) device sees after onboarding. Access is granted the moment a
/// payment is verified or a promo code is redeemed.
///
/// The entitlement verdict (and its fail-open behaviour) lives in
/// [deviceEntitled], shared with the playback gate so both agree.
class SubscriptionGate extends StatefulWidget {
  const SubscriptionGate({
    super.key,
    required this.child,
    this.api,
    this.checkForUpdates = true,
  });

  /// The app content (profile picker + shell) shown once the device is entitled.
  final Widget child;

  /// Entitlement source. Defaults to the registered subscription service; tests
  /// inject a fake so no backend is needed.
  final SubscriptionApi? api;

  /// Whether to run the mandatory GitHub release check. Tests disable it so
  /// they never touch the network.
  final bool checkForUpdates;

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate>
    with WidgetsBindingObserver {
  bool _allowed = false;
  bool _paywallOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame so a modal has a Navigator/Overlay to attach to.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Start both at once: the paywall must not wait on the update network
      // call, and a required update must cover the paywall when one exists.
      final update = !widget.checkForUpdates || isAppleTv
          ? Future<void>.value()
          : maybeShowUpdateDialog(context);
      unawaited(_evaluate());
      unawaited(update);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_evaluate());
    }
  }

  SubscriptionApi? get _api {
    if (widget.api != null) return widget.api;
    return sl.isRegistered<SubscriptionApi>() ? sl<SubscriptionApi>() : null;
  }

  /// Reads this device's entitlement and either lets the app through or holds
  /// it at the paywall.
  Future<void> _evaluate() async {
    if (!mounted) return;
    if (await deviceEntitled(api: _api)) {
      _allow();
      return;
    }
    _deny();
    unawaited(_openPaywall());
  }

  void _allow() {
    if (!mounted || _allowed) return;
    setState(() => _allowed = true);
  }

  /// Takes the app content away when the server verdict says access has ended.
  /// The paywall is then opened over the spinner.
  void _deny() {
    if (!mounted || !_allowed) return;
    setState(() => _allowed = false);
  }

  Future<void> _openPaywall({
    String reason = 'Subscribe to start watching',
  }) async {
    if (_paywallOpen || !mounted) return;
    _paywallOpen = true;
    final unlocked = await showPaywall(
      context,
      reason: reason,
      onUnlocked: _allow,
      dismissible: false,
    );
    _paywallOpen = false;
    if (!mounted) return;
    if (unlocked) {
      _allow();
    } else {
      // Not unlocked: re-read the server verdict (a promo or charge may have
      // settled) and, if still shut, bring the card back. Home stays hidden.
      await _evaluate();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return widget.child;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.defaultAccent,
          ),
        ),
      ),
    );
  }
}
