import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/di/injector.dart';
import '../../core/diagnostics/memory_report.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/log_report_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// In-app log viewer (gap E4): the read side of [AppLogger]'s rolling buffer.
///
/// Hikari ships a LogsScreen over two rolling logs + a crash log with
/// share/save/clear. We already kept the buffer and a one-tap "send report";
/// this adds the *view* so a user can read what went wrong, copy it, save it,
/// or clear it, without leaving the app.
class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  String _text = AppLogger.instance.contents;

  void _refresh() => setState(() => _text = AppLogger.instance.contents);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _text));
    if (!mounted) return;
    _toast(context.l10n.logsCopied);
  }

  Future<void> _save() async {
    final file = await AppLogger.instance.exportFile();
    if (!mounted) return;
    if (file == null) {
      _toast(context.l10n.couldNotExportLogs);
      return;
    }
    // A share sheet is the only way an app can hand a file to the user's own
    // storage on both Android and iOS, so "save" and "share" are the same
    // action here — the sheet offers "Save to Files" / a file manager.
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'Zangetsu logs'),
    );
  }

  /// Send the log straight to us in one tap, falling back to the share sheet.
  ///
  /// Uploading needs the intake Worker deployed AND a network; where it can't
  /// reach, the old share-sheet behaviour is still there rather than a dead
  /// button. This is the same flow the old "Share logs" row ran, moved onto the
  /// page where the log is actually visible.
  Future<void> _sendReport() async {
    final reporter = sl<LogReportService>();
    if (!reporter.configured) return _save();

    _toast(context.l10n.sendingReport);
    final ref = await reporter.send();
    if (!mounted) return;
    if (ref == null) return _save();

    ScaffoldMessenger.of(context).clearSnackBars();
    await AppDialog.show<void>(
      context,
      title: context.l10n.reportSent,
      body: Text(context.l10n.reportSentBody(ref)),
      actions: [
        TvAlertAction(
          label: context.l10n.copy,
          onTap: () {
            Clipboard.setData(ClipboardData(text: ref));
            Navigator.of(context, rootNavigator: true).pop();
          },
        ),
        TvAlertAction(
          label: context.l10n.ok,
          primary: true,
          autofocus: true,
          onTap: () => Navigator.of(context, rootNavigator: true).pop(),
        ),
      ],
    );
  }

  Future<void> _clear() async {
    final ok = await AppDialog.confirm(
      context,
      title: context.l10n.logsClearTitle,
      message: context.l10n.logsClearBody,
      confirmLabel: context.l10n.logsClear,
      destructive: true,
    );
    if (!ok) return;
    await AppLogger.instance.clear();
    if (!mounted) return;
    _toast(context.l10n.logsCleared);
    _refresh();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lines = _text.trim().isEmpty ? 0 : _text.split('\n').length;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        l10n.logsAndDiagnostics,
        actions: [
          IconButton(
            tooltip: l10n.memoryReport,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(l10n.memoryReport),
                content: Text(MemoryReport.short),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(l10n.close),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.memory_outlined),
          ),
          IconButton(
            tooltip: l10n.sendReport,
            onPressed: _text.trim().isEmpty ? null : _sendReport,
            icon: const Icon(Icons.send_outlined),
          ),
          IconButton(
            tooltip: l10n.logsCopy,
            onPressed: _text.trim().isEmpty ? null : _copy,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: l10n.logsSave,
            onPressed: _text.trim().isEmpty ? null : _save,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: l10n.logsClear,
            onPressed: _text.trim().isEmpty ? null : _clear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: _text.trim().isEmpty
          ? EmptyState(
              icon: Icons.receipt_long_outlined,
              message: l10n.logsEmpty,
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.logsTitle, style: AppText.caption),
                      const Spacer(),
                      Text(l10n.logsLineCount(lines), style: AppText.caption),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.settingsCard,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.hairline),
                    ),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          _text,
                          style: AppText.caption.copyWith(
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['Roboto Mono', 'monospace'],
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
