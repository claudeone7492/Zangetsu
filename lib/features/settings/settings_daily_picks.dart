import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/notify/daily_picks_prefs.dart';
import '../../core/notify/daily_picks_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/ui/settings_widgets.dart';
import '../../l10n/l10n.dart';

/// Settings → Daily picks. One switch turns the three-a-day digest on or off;
/// the rows below spell out the three slots and the card design each one uses,
/// so it is clear the three are deliberately different rather than a bug.
class DailyPicksScreen extends StatefulWidget {
  const DailyPicksScreen({super.key, this.onEnabled});

  /// Called after the switch is turned on, to arm the alarms and post a slot
  /// that is already due. Defaults to the real scheduler; tests inject a no-op
  /// so a widget test never touches the notification platform channels.
  final Future<void> Function()? onEnabled;

  @override
  State<DailyPicksScreen> createState() => _DailyPicksScreenState();
}

class _DailyPicksScreenState extends State<DailyPicksScreen> {
  late bool _enabled = DailyPicksPrefs.enabled;

  Future<void> _toggle(bool value) async {
    setState(() => _enabled = value);
    await DailyPicksPrefs.setEnabled(value);
    if (value) {
      // Fire-and-forget: the row must flip instantly, not after the scheduler.
      unawaited(
        (widget.onEnabled ??
                () => DailyPicksService.instance.sync(force: true))()
            .catchError((_) {}),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(l10n.dailyPicks),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SettingsTile(
            icon: Icons.auto_awesome_rounded,
            iconAccent: true,
            title: l10n.dailyPicksEnable,
            subtitle: l10n.dailyPicksSubtitle,
            subtitleMaxLines: 2,
            trailing: Switch(
              value: _enabled,
              onChanged: _toggle,
            ),
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            for (final slot in DailyPickSlot.values)
              SettingsTile(
                icon: _iconFor(slot.style),
                title: _label(l10n, slot),
                subtitle: _time(slot),
              ),
            const SizedBox(height: 8),
            SettingsTile(
              icon: Icons.send_rounded,
              title: l10n.dailyPicksNow,
              onTap: () => DailyPicksService.instance.sync(force: true),
            ),
          ],
        ],
      ),
    );
  }

  String _label(AppLocalizations l10n, DailyPickSlot slot) => switch (slot) {
    DailyPickSlot.morning => l10n.dailyPicksMorning,
    DailyPickSlot.afternoon => l10n.dailyPicksAfternoon,
    DailyPickSlot.evening => l10n.dailyPicksEvening,
  };

  IconData _iconFor(DailyPickStyle style) => switch (style) {
    DailyPickStyle.bigText => Icons.subject_rounded,
    DailyPickStyle.bigPicture => Icons.image_rounded,
    DailyPickStyle.inbox => Icons.list_rounded,
  };

  String _time(DailyPickSlot slot) =>
      '${slot.hour.toString().padLeft(2, '0')}:'
      '${slot.minute.toString().padLeft(2, '0')}';
}
