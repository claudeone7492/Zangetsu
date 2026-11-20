import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../../core/di/injector.dart';
import '../../core/hikari/hikari_extension_service.dart';
import '../../core/hikari/hikari_manager.dart';
import '../../core/hikari/hikari_provider.dart';
import '../../core/hikari/hikari_repo.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/source_icon_tile.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// Manage native `.hiki` extensions.
///
/// Deliberately its own screen rather than a [JsPackEngine] family: a `.hiki`
/// is a dexed Kotlin JAR, so it installs and uninstalls through the native
/// host ([HikariExtensionService]) and has no JS module to edit. The repo
/// index is fetched fresh each visit — it is small, and a stale plugin list is
/// how a user ends up installing a version the repo already replaced.
class HikariSourcesScreen extends StatefulWidget {
  const HikariSourcesScreen({super.key});

  @override
  State<HikariSourcesScreen> createState() => _HikariSourcesScreenState();
}

class _HikariSourcesScreenState extends State<HikariSourcesScreen> {
  final HikariExtensionService _service = HikariExtensionService();
  HikariManager? _manager;

  List<HikariInstalled> _installed = const [];
  List<HikariRepo> _repos = const [];
  bool _busy = false;
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _manager = sl.isRegistered<HikariManager>() ? sl<HikariManager>() : null;
    _manager?.addListener(_changed);
    _reload();
  }

  @override
  void dispose() {
    _manager?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<String> get _repoUrls {
    if (!Hive.isBoxOpen(kHikariReposBox)) return const [];
    return Hive.box<String>(kHikariReposBox).values.toList();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final installed = _service.installed()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final urls = _repoUrls.isEmpty ? const [kDefaultHikariRepo] : _repoUrls;
    final repos = <HikariRepo>[];
    for (final url in urls) {
      final repo = await _service.fetchRepo(url);
      if (repo != null) repos.add(repo);
    }
    if (!mounted) return;
    setState(() {
      _installed = installed;
      _repos = repos;
      _loading = false;
    });
  }

  Future<void> _install(HikariRepoEntry entry) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Installing ${entry.name}…';
    });
    final record = await _service.install(entry, manager: _manager);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = record == null
          ? 'Could not install ${entry.name}'
          : 'Installed ${record.name}';
    });
    await _reload();
  }

  Future<void> _uninstall(HikariInstalled record) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _service.uninstall(record.sourceId, manager: _manager);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = 'Removed ${record.name}';
    });
    await _reload();
  }

  Future<void> _addRepo() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.addRepository),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'https://…/repo.json'),
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
    if (!Hive.isBoxOpen(kHikariReposBox)) {
      setState(() => _status = 'Storage not ready');
      return;
    }
    final box = Hive.box<String>(kHikariReposBox);
    if (!url.startsWith('http')) {
      setState(() => _status = 'That is not a repository URL');
      return;
    }
    if (box.values.contains(url)) {
      setState(() => _status = 'Repository already added');
      return;
    }
    await box.add(url);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        'Hikari extensions',
        actions: [
          IconButton(
            tooltip: 'Add repository',
            onPressed: _busy ? null : _addRepo,
            icon: const Icon(Icons.add_link_rounded),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _busy ? null : _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _body(),
    );
  }

  /// The entry a record was installed from, matched by download URL.
  ///
  /// The source id carries the provider id the archive declares (`hiki:yts`)
  /// while an index row is the catalogue's label (`YTS Movies`), so comparing
  /// the two never matches. The URL is what both sides actually share.
  HikariInstalled? _installedFor(HikariRepoEntry entry) {
    for (final r in _installed) {
      if (r.repoUrl.isNotEmpty && r.repoUrl == entry.url) return r;
    }
    // Records written before `repoUrl` existed have only a name to go on.
    for (final r in _installed) {
      if (r.repoUrl.isEmpty &&
          r.name.toLowerCase() == entry.name.toLowerCase()) {
        return r;
      }
    }
    return null;
  }

  Widget _body() {
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
        if (_installed.isNotEmpty) ...[
          Text('${_installed.length} installed', style: AppText.overline),
          const SizedBox(height: 8),
          for (final record in _installed) _installedRow(record),
          const SizedBox(height: 28),
        ],
        if (_repos.isEmpty)
          const EmptyState(
            icon: Icons.cloud_off_outlined,
            message: 'Could not load any Hikari repository',
          )
        else
          for (final repo in _repos) ...[
            Text(repo.name.toUpperCase(), style: AppText.overline),
            const SizedBox(height: 8),
            for (final entry in repo.entries) _entryRow(entry),
            const SizedBox(height: 24),
          ],
      ],
    );
  }

  Widget _installedRow(HikariInstalled record) {
    final provider = _manager?.get(record.sourceId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SourceIconTile(
            name: record.name,
            icon: provider is HikariProviderAdapter
                ? provider.info.iconUrl
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.name, style: AppText.body),
                Text(
                  'v${record.version}',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: _busy ? null : () => _uninstall(record),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _entryRow(HikariRepoEntry entry) {
    final record = _installedFor(entry);
    // A repo entry advertising a higher version than the installed record is
    // an update, not a reinstall — say so rather than showing a bare tick.
    final hasUpdate = record != null && entry.version > record.version;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: AppText.body),
                if (entry.description.isNotEmpty)
                  Text(
                    entry.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (record == null)
            TextButton(
              onPressed: _busy ? null : () => _install(entry),
              child: Text(context.l10n.install),
            )
          else if (hasUpdate)
            TextButton(
              onPressed: _busy ? null : () => _install(entry),
              child: Text(context.l10n.update),
            )
          else
            const Icon(
              Icons.check_circle_outline_rounded,
              size: 20,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}
