import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/privacy/app_lock.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';

/// Wraps the app content and covers it with a PIN prompt whenever [AppLock]
/// says it should be locked — on a cold start, and again once the app has been
/// in the background longer than the configured grace period.
///
/// The gate is a pure overlay: the child stays mounted underneath so the app
/// never re-runs its boot sequence, and a rebuild of this widget is the only
/// thing a lock/unlock does.
class AppLockGate extends StatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  final _pin = TextEditingController();

  bool _locked = false;
  bool _busy = false;
  bool _wrongPin = false;

  /// When the app last left the foreground. Null while it is visible.
  DateTime? _backgroundedAt;

  AppLock get _lock => sl<AppLock>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadThenLock());
  }

  Future<void> _loadThenLock() async {
    await _lock.ensureLoaded();
    if (!mounted || !_lock.enabled) return;
    setState(() => _locked = true);
    unawaited(_promptBiometric());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pin.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final left = _backgroundedAt;
        _backgroundedAt = null;
        // Still on the lock screen: nothing to re-arm.
        if (_locked || left == null || !_lock.enabled) return;
        final away = DateTime.now().difference(left).inSeconds;
        if (away >= _lock.relockSeconds) {
          setState(() {
            _locked = true;
            _wrongPin = false;
            _pin.clear();
          });
          unawaited(_promptBiometric());
        }
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _backgroundedAt ??= DateTime.now();
    }
  }

  /// Offer the biometric shortcut when it is on. A cancel or failure just
  /// leaves the PIN field in front — no error, the PIN is still there.
  Future<void> _promptBiometric() async {
    if (!_lock.biometricEnabled) return;
    if (!await _lock.canUseBiometrics) return;
    if (!mounted) return;
    final ok = await _lock.authenticateBiometric(
      context.l10n.appLockBiometricReason,
    );
    if (ok && mounted) _unlock();
  }

  void _unlock() {
    setState(() {
      _locked = false;
      _wrongPin = false;
      _pin.clear();
    });
  }

  Future<void> _submit() async {
    final value = _pin.text.trim();
    if (value.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ok = await _lock.verifyPin(value);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _wrongPin = !ok;
      if (ok) _pin.clear();
    });
    if (ok) _unlock();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockScreen(
              pin: _pin,
              busy: _busy,
              wrongPin: _wrongPin,
              showBiometric: _lock.biometricEnabled,
              onBiometric: _promptBiometric,
              onSubmit: _submit,
              onChanged: () {
                if (_wrongPin) setState(() => _wrongPin = false);
              },
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({
    required this.pin,
    required this.busy,
    required this.wrongPin,
    required this.showBiometric,
    required this.onBiometric,
    required this.onSubmit,
    required this.onChanged,
  });

  final TextEditingController pin;
  final bool busy;
  final bool wrongPin;
  final bool showBiometric;
  final VoidCallback onBiometric;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 40),
                const SizedBox(height: 18),
                Text(l10n.appLockTitle, style: AppText.title),
                const SizedBox(height: 8),
                Text(
                  l10n.appLockEnterPin,
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: 220,
                  child: TextField(
                    key: const ValueKey('app-lock-pin'),
                    controller: pin,
                    autofocus: true,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    enabled: !busy,
                    textAlign: TextAlign.center,
                    onChanged: (_) => onChanged(),
                    onSubmitted: (_) => onSubmit(),
                    decoration: InputDecoration(
                      counterText: '',
                      errorText: wrongPin ? l10n.appLockWrongPin : null,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 220,
                  child: FilledButton(
                    key: const ValueKey('app-lock-unlock'),
                    onPressed: busy ? null : onSubmit,
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.appLockUnlock),
                  ),
                ),
                if (showBiometric) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const ValueKey('app-lock-biometric'),
                    onPressed: busy ? null : onBiometric,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: Text(l10n.appLockUseBiometric),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
