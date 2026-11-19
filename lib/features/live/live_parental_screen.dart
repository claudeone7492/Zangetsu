import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/live/live_parental.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/states.dart';

/// Parental controls for live channels: a PIN, a rating ceiling, and a list of
/// channels hidden outright.
///
/// The PIN here is deliberately NOT the app-lock PIN. The app lock gates the
/// whole app; this gates adult channels inside it. A household where a child
/// knows the app PIN is exactly the case this exists for, so the two must be
/// separate secrets.
class LiveParentalScreen extends StatefulWidget {
  const LiveParentalScreen({super.key});

  @override
  State<LiveParentalScreen> createState() => _LiveParentalScreenState();
}

class _LiveParentalScreenState extends State<LiveParentalScreen> {
  LiveParental? _parental;

  @override
  void initState() {
    super.initState();
    _parental = sl.isRegistered<LiveParental>() ? sl<LiveParental>() : null;
    _parental?.addListener(_changed);
    _parental?.ensureLoaded();
  }

  @override
  void dispose() {
    _parental?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _setPin() async {
    final parental = _parental;
    if (parental == null) return;
    final pin = await _askPin(
      title: parental.pinSet ? 'Change PIN' : 'Set PIN',
      subtitle: parental.pinSet
          ? 'Enter a new 4-digit PIN'
          : 'A 4-digit PIN hides channels above the rating you choose',
    );
    if (pin == null || !mounted) return;
    final current = parental.pinSet
        ? await _askPin(title: 'Current PIN', subtitle: 'Confirm the old PIN')
        : null;
    if (parental.pinSet && (current == null || !mounted)) return;
    final ok = await parental.setPin(pin, current: current);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'PIN updated' : 'PIN not changed')),
    );
  }

  Future<void> _clearPin() async {
    final parental = _parental;
    if (parental == null) return;
    final current = await _askPin(
      title: 'Remove PIN',
      subtitle: 'Enter the current PIN to remove the lock',
    );
    if (current == null || !mounted) return;
    final ok = await parental.clearPin(current);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'PIN removed' : 'Wrong PIN')),
    );
  }

  Future<void> _unlock() async {
    final parental = _parental;
    if (parental == null) return;
    final pin = await _askPin(
      title: 'Unlock',
      subtitle: 'Enter the PIN to reveal restricted channels',
    );
    if (pin == null || !mounted) return;
    final ok = await parental.verifyPin(pin);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Unlocked until the app closes' : 'Wrong PIN')),
    );
  }

  Future<String?> _askPin({
    required String title,
    required String subtitle,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: AppText.body),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parental = _parental;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar('Parental controls'),
      body: parental == null
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              message: 'Parental controls are not available on this device',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text('PIN', style: AppText.overline),
                const SizedBox(height: 4),
                Text(
                  parental.pinSet
                      ? 'A PIN is set. Restricted channels stay hidden until it '
                            'is entered.'
                      : 'Set a PIN to hide channels above the rating you '
                            'choose. This is separate from the app lock.',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.tonal(
                      onPressed: _setPin,
                      child: Text(parental.pinSet ? 'Change PIN' : 'Set PIN'),
                    ),
                    const SizedBox(width: 8),
                    if (parental.pinSet) ...[
                      TextButton(
                        onPressed: parental.unlocked ? null : _unlock,
                        child: Text(parental.unlocked ? 'Unlocked' : 'Unlock'),
                      ),
                      TextButton(
                        onPressed: _clearPin,
                        child: const Text('Remove'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 28),
                Text('Show up to', style: AppText.overline),
                const SizedBox(height: 8),
                RadioGroup<ContentRating>(
                  groupValue: parental.ceiling,
                  onChanged: (v) {
                    if (v != null) parental.setCeiling(v);
                  },
                  child: Column(
                    children: [
                      for (final rating in ContentRating.values)
                        RadioListTile<ContentRating>(
                          value: rating,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: AppColors.accent,
                          title: Text(rating.label, style: AppText.body),
                          subtitle: rating == ContentRating.adult
                              ? Text(
                                  'Everything — no rating filtering',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textTertiary,
                                  ),
                                )
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  parental.isInactive
                      ? 'No channels are hidden.'
                      : 'Channels above ${parental.ceiling.label} are hidden '
                            'from Live TV.',
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
    );
  }
}
