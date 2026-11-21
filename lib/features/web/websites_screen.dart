import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/web/website.dart';
import '../../core/web/website_store.dart';
import '../../l10n/l10n.dart';
import 'web_protections_screen.dart';
import 'website_view_screen.dart';

/// Saved sites, opened in the in-app browser.
///
/// Mirrors Hikari's Extensions → Webview sites: a grid of named sites, add and
/// remove, no accounts and no addon. The list lives in its own Hive box.
class WebsitesScreen extends StatelessWidget {
  const WebsitesScreen({super.key});

  bool get _isTv => sl.isRegistered<AppMode>() && sl<AppMode>().isTv;

  @override
  Widget build(BuildContext context) {
    final store = sl<WebsiteStore>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.websites),
        actions: [
          IconButton(
            tooltip: context.l10n.webProtections,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const WebProtectionsScreen(),
              ),
            ),
            icon: const Icon(Icons.security_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, store),
        tooltip: context.l10n.websitesAdd,
        child: const Icon(Icons.add_rounded),
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final sites = store.sites;
          if (sites.isEmpty) {
            return _EmptyState(onAdd: () => _add(context, store));
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 220,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
            itemCount: sites.length,
            itemBuilder: (context, i) {
              final site = sites[i];
              return _SiteCard(
                site: site,
                isTv: _isTv,
                onOpen: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WebsiteViewScreen(site: site),
                  ),
                ),
                onRemove: () => _remove(context, store, site),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, WebsiteStore store) async {
    await showDialog<Website>(
      context: context,
      builder: (_) => _AddWebsiteDialog(store: store),
    );
  }

  Future<void> _remove(
    BuildContext context,
    WebsiteStore store,
    Website site,
  ) async {
    final ok = await AppDialog.confirm(
      context,
      title: context.l10n.websitesRemoveTitle,
      message: context.l10n.websitesRemoveBody(site.name),
      confirmLabel: context.l10n.delete,
      destructive: true,
    );
    if (ok) await store.remove(site.id);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.public_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              context.l10n.websitesEmpty,
              style: AppText.headline,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.websitesEmptyBody,
              style: AppText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.l10n.websitesAdd),
            ),
          ],
        ),
      ),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({
    required this.site,
    required this.isTv,
    required this.onOpen,
    required this.onRemove,
  });

  final Website site;
  final bool isTv;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final body = Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Favicon(host: site.host),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.more_vert_rounded, size: 18),
                  tooltip: context.l10n.delete,
                  onPressed: onRemove,
                ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                site.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.body,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                site.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ),
          ],
        ),
      ),
    );

    if (isTv) {
      return TvFocusable(
        onTap: onOpen,
        onLongPress: onRemove,
        borderRadius: 14,
        focusLabel: site.name,
        child: body,
      );
    }
    return InkWell(
      onTap: onOpen,
      onLongPress: onRemove,
      borderRadius: BorderRadius.circular(14),
      child: body,
    );
  }
}

class _Favicon extends StatelessWidget {
  const _Favicon({required this.host});

  final String host;

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: 18,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(host.isEmpty ? '?' : host[0].toUpperCase()),
    );
    if (host.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        'https://www.google.com/s2/favicons?domain=$host&sz=64',
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _AddWebsiteDialog extends StatefulWidget {
  const _AddWebsiteDialog({required this.store});

  final WebsiteStore store;

  @override
  State<_AddWebsiteDialog> createState() => _AddWebsiteDialogState();
}

class _AddWebsiteDialogState extends State<_AddWebsiteDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final site = await widget.store.add(_name.text, _url.text);
    if (!mounted) return;
    if (site == null) {
      setState(() {
        _saving = false;
        _error = context.l10n.websitesInvalidUrl;
      });
      return;
    }
    Navigator.of(context).pop(site);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.websitesAdd),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: context.l10n.websitesNameHint,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _saving ? null : _submit(),
            decoration: InputDecoration(
              hintText: context.l10n.websitesUrlHint,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(context.l10n.add),
        ),
      ],
    );
  }
}
