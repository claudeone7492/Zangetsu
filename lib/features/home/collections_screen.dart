import 'package:flutter/material.dart';

import '../../core/collections/collection_store.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/settings_widgets.dart';
import '../../l10n/l10n.dart';

/// Manage personal collections: the hand-made Home rows.
///
/// Kept deliberately plain — a list of collections, each expanding to its
/// folders and titles. Everything here writes through [CollectionStore], and
/// the Home page picks the result up on its next load, so this screen never
/// has to reach into Home state.
class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});

  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  CollectionStore get _store => sl<CollectionStore>();

  Future<void> _create() async {
    final name = await _promptName(title: 'New collection');
    if (name == null || !mounted) return;
    await _store.create(name);
    if (mounted) setState(() {});
  }

  Future<String?> _promptName({required String title, String? initial}) {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: AppText.headline),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: AppText.body,
          decoration: const InputDecoration(hintText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(Collection c) async {
    final name = await _promptName(title: context.l10n.collectionsRename, initial: c.name);
    if (name == null || !mounted) return;
    await _store.rename(c.id, name);
    if (mounted) setState(() {});
  }

  Future<void> _addFolder(Collection c) async {
    final name = await _promptName(title: context.l10n.collectionsNewFolder);
    if (name == null || !mounted) return;
    await _store.addFolder(c.id, name);
    if (mounted) setState(() {});
  }

  Future<void> _addLiveFolder(Collection c) async {
    final name = await _promptName(title: context.l10n.collectionsNewLiveFolder);
    if (name == null || !mounted) return;
    final query = await _promptName(title: context.l10n.collectionsSearchText, initial: name);
    if (query == null || query.trim().isEmpty || !mounted) return;
    await _store.addLiveFolder(c.id, name, query);
    if (mounted) setState(() {});
  }

  Future<void> _delete(Collection c) async {
    final ok = await AppDialog.confirm(
      context,
      title: context.l10n.collectionsDeleteTitle(c.name),
      message:
          'The collection and its folders are removed. The titles '
          'themselves stay in your library.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _store.delete(c.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final collections = _store.all();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar('Collections'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_rounded),
        label: Text(context.l10n.collectionsNewCollection),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Your own rows on Home. Group titles into folders, or save a '
              'search that keeps itself up to date.',
              style: AppText.caption,
            ),
          ),
          if (collections.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.l10n.collectionsEmpty,
                style: AppText.body.copyWith(color: AppColors.textTertiary),
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final c in collections) _collectionCard(c),
        ],
      ),
    );
  }

  Widget _collectionCard(Collection c) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.name,
                    style: AppText.headline,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: c.hidden ? 'Show on Home' : 'Hide from Home',
                  icon: Icon(
                    c.hidden
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: c.hidden ? AppColors.textTertiary : AppColors.accent,
                  ),
                  onPressed: () async {
                    await _store.setHidden(c.id, !c.hidden);
                    if (mounted) setState(() {});
                  },
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded),
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _rename(c);
                      case 'folder':
                        _addFolder(c);
                      case 'live':
                        _addLiveFolder(c);
                      case 'delete':
                        _delete(c);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(context.l10n.rename),
                    ),
                    PopupMenuItem(
                      value: 'folder',
                      child: Text(context.l10n.collectionsAddFolder),
                    ),
                    PopupMenuItem(
                      value: 'live',
                      child: Text(context.l10n.collectionsAddLiveFolder),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(context.l10n.delete),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (c.folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                context.l10n.collectionsNoFolders,
                style: AppText.caption,
              ),
            )
          else
            for (final f in c.folders)
              ListTile(
                dense: true,
                leading: Icon(
                  f.isLive ? Icons.autorenew_rounded : Icons.folder_outlined,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                title: Text(f.name, style: AppText.body),
                subtitle: Text(
                  f.isLive
                      ? 'Live · "${f.query}"'
                      : '${f.items.length} '
                            '${f.items.length == 1 ? 'title' : 'titles'}',
                  style: AppText.caption,
                ),
              ),
          const SizedBox(height: 6),
        ],
      ),
    ),
  );
}
