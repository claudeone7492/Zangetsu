import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/live/live_playlist_store.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// The user's own M3U / JSON playlists. Adding one merges its channels into
/// Live TV beside the bundled IPTV catalogue; removing it takes them out
/// again. Remote playlists are fetched and validated before they are stored,
/// so a bad URL fails here rather than silently producing an empty rail.
class LivePlaylistsScreen extends StatefulWidget {
  const LivePlaylistsScreen({super.key});

  @override
  State<LivePlaylistsScreen> createState() => _LivePlaylistsScreenState();
}

class _LivePlaylistsScreenState extends State<LivePlaylistsScreen> {
  LivePlaylistStore? _store;

  @override
  void initState() {
    super.initState();
    _store = sl.isRegistered<LivePlaylistStore>()
        ? sl<LivePlaylistStore>()
        : null;
  }

  Future<void> _add() async {
    final store = _store;
    if (store == null) return;
    final result = await showModalBottomSheet<_NewPlaylist>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _AddPlaylistSheet(),
    );
    if (result == null || !mounted) return;
    try {
      if (result.url.isNotEmpty) {
        await store.addUrl(name: result.name, url: result.url, dio: sl<Dio>());
      } else {
        await store.addText(name: result.name, text: result.text);
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.playlistAdded)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.playlistFailed)),
      );
    }
  }

  Future<void> _remove(LivePlaylistEntry entry) async {
    final store = _store;
    if (store == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(context.l10n.playlistRemoveTitle),
        content: Text(context.l10n.playlistRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(context.l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.remove(entry.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final entries = store?.entries ?? const <LivePlaylistEntry>[];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(context.l10n.livePlaylists),
        actions: [
          IconButton(
            tooltip: context.l10n.addPlaylist,
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: store == null
          ? const SizedBox.shrink()
          : entries.isEmpty
          ? EmptyState(
              icon: Icons.playlist_play_rounded,
              message: context.l10n.playlistEmpty,
              actionLabel: context.l10n.addPlaylist,
              onAction: _add,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  context.l10n.playlistCount(entries.length),
                  style: AppText.overline,
                ),
                const SizedBox(height: 8),
                for (final entry in entries) _row(entry),
              ],
            ),
    );
  }

  Widget _row(LivePlaylistEntry entry) {
    final subtitle = entry.isInline
        ? context.l10n.playlistSourcePaste
        : entry.source;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.playlist_play_rounded,
            size: 20,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: AppText.body),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.playlistRemove,
            onPressed: () => _remove(entry),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _NewPlaylist {
  const _NewPlaylist({
    required this.name,
    required this.url,
    required this.text,
  });

  final String name;
  final String url;
  final String text;
}

class _AddPlaylistSheet extends StatefulWidget {
  const _AddPlaylistSheet();

  @override
  State<_AddPlaylistSheet> createState() => _AddPlaylistSheetState();
}

class _AddPlaylistSheetState extends State<_AddPlaylistSheet> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _text = TextEditingController();
  bool _error = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _url.text.trim();
    final text = _text.text.trim();
    if (url.isEmpty && text.isEmpty) {
      setState(() => _error = true);
      return;
    }
    Navigator.of(
      context,
    ).pop(_NewPlaylist(name: _name.text.trim(), url: url, text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.addPlaylist, style: AppText.headline),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.l10n.playlistName,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.l10n.playlistUrl,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: context.l10n.playlistPaste,
                alignLabelWithHint: true,
              ),
            ),
            if (_error) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.playlistFailed,
                style: AppText.caption.copyWith(color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                  ),
                  onPressed: _submit,
                  child: Text(context.l10n.add),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
