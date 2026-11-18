import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/privacy/app_lock.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/settings_widgets.dart';
import '../../l10n/l10n.dart';

/// Settings for the device-wide [AppLock] (gap E2): turn the lock on with a
/// PIN, add a biometric shortcut, and choose how quickly the app re-locks once
/// it has been in the background.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  AppLock get _lock => sl<AppLock>();

  Future<void> _toggle(bool value) async {
    if (value) {
      final pin = await _askNewPin(
        context,
        context.l10n.appLockSet,
        context.l10n.appLockSetBody,
      );
      if (pin == null || !mounted) return;
      final ok = await _lock.setPin(pin);
      if (!mounted) return;
      if (!ok) {
        _toast(context.l10n.appLockInvalidPin);
        return;
      }
      // Offer the biometric shortcut right away — it's the natural follow-up.
      if (await _lock.canUseBiometrics && mounted) {
        final use = await AppDialog.confirm(
          context,
          title: context.l10n.appLockBiometric,
          message: context.l10n.appLockBiometricSubtitle,
          confirmLabel: context.l10n.enable,
        );
        await _lock.setBiometricEnabled(use);
      }
      if (mounted) _toast(context.l10n.appLockEnabled);
    } else {
      final pin = await _askPin(
        context,
        context.l10n.appLockRemove,
        context.l10n.appLockRemoveBody,
      );
      if (pin == null || !mounted) return;
      final ok = await _lock.disable(pin);
      if (!mounted) return;
      _toast(ok ? context.l10n.appLockDisabled : context.l10n.appLockWrongPin);
    }
    if (mounted) setState(() {});
  }

  Future<void> _changePin() async {
    final current = await _askPin(
      context,
      context.l10n.appLockChange,
      context.l10n.appLockCurrentPin,
    );
    if (current == null || !mounted) return;
    if (!await _lock.verifyPin(current)) {
      if (mounted) _toast(context.l10n.appLockWrongPin);
      return;
    }
    final pin = await _askNewPin(
      context,
      context.l10n.appLockChange,
      context.l10n.appLockSetBody,
    );
    if (pin == null || !mounted) return;
    if (!await _lock.setPin(pin)) {
      if (mounted) _toast(context.l10n.appLockInvalidPin);
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _pickRelock() async {
    final l10n = context.l10n;
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.bg,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final seconds in AppLock.relockDelayChoices)
              ListTile(
                title: Text(_relockLabel(l10n, seconds)),
                trailing: _lock.relockSeconds == seconds
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(seconds),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    await _lock.setRelockSeconds(chosen);
    if (mounted) setState(() {});
  }

  static String _relockLabel(AppLocalizations l10n, int seconds) {
    if (seconds == 0) return l10n.appLockRelockImmediately;
    final minutes = seconds ~/ 60;
    return minutes == 1
        ? l10n.appLockRelockMinute(minutes)
        : l10n.appLockRelockMinutes(minutes);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final on = _lock.enabled;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(l10n.appLock),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          SettingsCard(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            children: [
              SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: l10n.appLock,
                subtitle: l10n.appLockSubtitle,
                trailing: Switch.adaptive(
                  value: on,
                  activeThumbColor: AppColors.accent,
                  onChanged: _toggle,
                ),
              ),
            ],
          ),
          if (on) ...[
            SettingsSectionLabel(l10n.privacy),
            SettingsCard(
              children: [
                SettingsTile(
                  icon: Icons.password_rounded,
                  title: l10n.appLockChange,
                  onTap: _changePin,
                ),
                SettingsTile(
                  icon: Icons.fingerprint_rounded,
                  title: l10n.appLockBiometric,
                  subtitle: l10n.appLockBiometricSubtitle,
                  trailing: Switch.adaptive(
                    value: _lock.biometricEnabled,
                    activeThumbColor: AppColors.accent,
                    onChanged: (v) async {
                      await _lock.setBiometricEnabled(v);
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                SettingsTile(
                  icon: Icons.timer_outlined,
                  title: l10n.appLockRelock,
                  trailing: Text(
                    _relockLabel(l10n, _lock.relockSeconds),
                    style: AppText.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  onTap: _pickRelock,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Ask for the existing PIN. Returns null when cancelled.
Future<String?> _askPin(
  BuildContext context,
  String title,
  String message,
) => _pinDialog(context: context, title: title, message: message);

/// Ask for a new PIN, then confirm it. Returns null on cancel, mismatch, or a
/// PIN that fails the length/format floor.
Future<String?> _askNewPin(
  BuildContext context,
  String title,
  String message,
) async {
  final l10n = context.l10n;
  final first = await _pinDialog(
    context: context,
    title: title,
    message: message,
    isNew: true,
  );
  if (first == null || !AppLock.isValidPin(first)) return null;
  final again = await _pinDialog(
    context: context,
    title: title,
    message: l10n.appLockConfirmPin,
    isNew: true,
  );
  if (again == null || again != first) return null;
  return first;
}

Future<String?> _pinDialog({
  required BuildContext context,
  required String title,
  required String message,
  bool isNew = false,
}) async {
  final controller = TextEditingController();
  final l10n = context.l10n;
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: AppText.body),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
          ),
          if (isNew) ...[
            const SizedBox(height: 4),
            Text(l10n.appLockInvalidPin, style: AppText.caption),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(dialogContext).pop(controller.text.trim()),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
  controller.dispose();
  return (result == null || result.isEmpty) ? null : result;
}
