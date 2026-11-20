import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/provider/js_pack_engine.dart';
import '../../core/provider/js_pack_manager.dart';
import '../../core/provider/js_pack_module.dart';
import '../../core/provider/js_pack_provisioner.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/source_icon_tile.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// Manage the sources of ONE JS plugin-pack family (`nuvio:`, `vega:`, …).
///
/// One screen serves all six families — they differ only in their label and
/// default repo list, both of which come from [JsPackEngine]. That keeps the
/// install/remove/add-repo flow identical everywhere instead of six screens
/// drifting apart, and means a family added later needs no new UI.
class JsPackSourcesScreen extends StatefulWidget {
  const JsPackSourcesScreen({super.key, required this.engine});

  final JsPackEngine engine;

  @override
  State<JsPackSourcesScreen> createState() => _JsPackSourcesScreenState();
}

class _JsPackSourcesScreenState extends State<JsPackSourcesScreen> {
  JsPackManager? _manager;
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _manager = _resolve();
    _manager?.addListener(_changed);
  }

  @override
  void dispose() {
    _manager?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The family's manager, when this device wired it. Null means the family has
  /// no manager in this build — the screen then shows an explanatory empty
  /// state rather than a spinner that never resolves.
  JsPackManager? _resolve() {
    if (!sl.isRegistered<JsPackManager>(instanceName: widget.engine.name)) {
      return null;
    }
    return sl<JsPackManager>(instanceName: widget.engine.name);
  }

  Future<void> _run(Future<void> Function(JsPackManager) action) async {
    final manager = _manager;
    if (manager == null || _busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action(manager);
    } catch (e) {
      if (mounted) setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addRepo() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.addRepo),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://…/index.json'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.l10n.add),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    await _run((m) async {
      final ids = await m.addRepository(url);
      if (mounted) {
        setState(() => _status = 'Installed ${ids.length} source(s)');
      }
    });
  }

  Future<void> _installDefaults() => _run((m) async {
    final result = await provisionPackDefaults(manager: m);
    if (mounted) {
      setState(
        () => _status =
            'Installed ${result.installedIds.length} source(s) '
            'from ${result.repoCount} repo(s)',
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final manager = _manager;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        '${widget.engine.label} sources',
        actions: [
          if (manager != null)
            IconButton(
              tooltip: 'Add repo',
              onPressed: _busy ? null : _addRepo,
              icon: const Icon(Icons.add_link_rounded),
            ),
        ],
      ),
      body: manager == null
          ? const EmptyState(
              icon: Icons.extension_off_outlined,
              message: 'Not available on this device',
            )
          : _body(manager),
    );
  }

  Widget _body(JsPackManager manager) {
    final modules = [...manager.all]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final repos = manager.repositories;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _status!,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
        if (modules.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No ${widget.engine.label} sources installed.',
                  style: AppText.body,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _installDefaults,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Install default repos'),
                ),
              ],
            ),
          )
        else ...[
          Text('${modules.length} source(s)', style: AppText.overline),
          const SizedBox(height: 8),
          for (final m in modules) _moduleRow(manager, m),
        ],
        if (repos.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text(context.l10n.repositories, style: AppText.overline),
          const SizedBox(height: 8),
          for (final url in repos) _repoRow(manager, url),
        ],
      ],
    );
  }

  Widget _moduleRow(JsPackManager manager, JsPackModule module) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SourceIconTile(
          name: module.name,
          icon: module.logo.isEmpty ? null : module.logo,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(module.name, style: AppText.body),
              Text(
                '${module.type} · v${module.version}',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Remove',
          onPressed: _busy
              ? null
              : () => _run((m) => m.uninstall(module.sourceId)),
          icon: const Icon(Icons.delete_outline_rounded, size: 20),
        ),
      ],
    ),
  );

  Widget _repoRow(JsPackManager manager, String url) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        const Icon(
          Icons.link_rounded,
          size: 18,
          color: AppColors.textSecondary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            url,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
        IconButton(
          tooltip: 'Remove repo',
          onPressed: _busy ? null : () => _run((m) => m.removeRepository(url)),
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  );
}
