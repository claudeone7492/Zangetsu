import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/di/injector.dart';
import '../../core/live/dvr_capture_service.dart';
import '../../core/live/dvr_store.dart';
import '../../core/notify/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// Recordings and reminders — the DVR schedule.
///
/// Two lists, because they are two different promises: a reminder pops an
/// alert, a recording writes a file. A booking with no resolved stream URL is
/// called out rather than silently recording nothing.
class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  DvrStore? _store;
  DvrCaptureService? _capture;

  @override
  void initState() {
    super.initState();
    _store = sl.isRegistered<DvrStore>() ? sl<DvrStore>() : null;
    _capture = sl.isRegistered<DvrCaptureService>()
        ? sl<DvrCaptureService>()
        : null;
    _store?.addListener(_changed);
    _capture?.start();
    _store?.ensureLoaded();
    _scheduleReminders();
  }

  @override
  void dispose() {
    _store?.removeListener(_changed);
    _capture?.stop();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Arm a local notification for each upcoming reminder. Android-only, which
  /// is what [NotificationService] already enforces.
  Future<void> _scheduleReminders() async {
    final store = _store;
    if (store == null) return;
    await store.ensureLoaded();
    for (final entry in store.upcoming.where(
      (e) => e.kind == DvrKind.reminder,
    )) {
      try {
        await NotificationService.instance.scheduleOnce(
          id: entry.id.hashCode & 0x7fffffff,
          title: '${entry.channelName} · starting now',
          body: entry.title,
          when: tz.TZDateTime.from(entry.start.toLocal(), tz.local),
        );
      } catch (_) {
        // A reminder that can't be armed (permission denied, unsupported host)
        // must not stop the schedule from listing.
      }
    }
  }

  Future<void> _refresh() async {
    await _store?.prune();
    await _scheduleReminders();
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final recordings = store?.recordings ?? const <DvrEntry>[];
    final reminders = store?.reminders ?? const <DvrEntry>[];

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        context.l10n.liveRecordingsAndReminders,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: store == null ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: store == null
          ? const EmptyState(
              icon: Icons.fiber_manual_record_outlined,
              message: 'Recording is not available on this device',
            )
          : recordings.isEmpty && reminders.isEmpty
          ? const EmptyState(
              icon: Icons.fiber_manual_record_outlined,
              message:
                  'Nothing scheduled.\nBook a recording or reminder from the '
                  'TV guide.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                if (recordings.isNotEmpty) ...[
                  Text(context.l10n.liveRecordings, style: AppText.overline),
                  const SizedBox(height: 8),
                  for (final e in recordings) _row(store, e),
                  const SizedBox(height: 24),
                ],
                if (reminders.isNotEmpty) ...[
                  Text(context.l10n.liveReminders, style: AppText.overline),
                  const SizedBox(height: 8),
                  for (final e in reminders) _row(store, e),
                ],
              ],
            ),
    );
  }

  Widget _row(DvrStore store, DvrEntry entry) {
    final recording = _capture?.isRecording(entry.id) ?? false;
    final progress = _capture?.progress[entry.id];
    final needsStream = entry.kind == DvrKind.recording && !entry.hasStream;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                entry.kind == DvrKind.recording
                    ? Icons.fiber_manual_record_rounded
                    : Icons.notifications_active_outlined,
                size: 18,
                color: recording ? AppColors.accent : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body,
                    ),
                    Text(
                      '${entry.channelName} · ${_when(entry)}',
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cancel',
                onPressed: () {
                  NotificationService.instance.cancelScheduled(
                    entry.id.hashCode & 0x7fffffff,
                  );
                  store.cancel(entry.id);
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
          if (recording && progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress <= 0 ? null : progress,
                  minHeight: 3,
                  backgroundColor: AppColors.surface2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
                ),
              ),
            ),
          if (needsStream)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                context.l10n.liveNoStreamResolved,
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  static String _when(DvrEntry entry) {
    final s = entry.start.toLocal();
    final h = s.hour.toString().padLeft(2, '0');
    final m = s.minute.toString().padLeft(2, '0');
    final d = '${s.day}/${s.month}';
    return '$d $h:$m';
  }
}
