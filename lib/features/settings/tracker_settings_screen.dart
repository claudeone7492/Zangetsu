import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import '../../core/tracker/tracker.dart';
import '../../core/tracker/trakt_service.dart';
import '../../core/ui/app_dialog.dart';
import '../../core/ui/settings_widgets.dart';

/// Connect / disconnect any [Tracker] (AniList, MyAnimeList, Simkl, Trakt,
/// MangaBaka) and toggle
/// its auto-sync. Connecting opens the provider's OAuth consent in the browser;
/// the token returns via the `zangetsu://…` deep link captured by the service.
class TrackerSettingsScreen extends StatefulWidget {
  const TrackerSettingsScreen({super.key, required this.tracker});

  final Tracker tracker;

  @override
  State<TrackerSettingsScreen> createState() => _TrackerSettingsScreenState();
}

class _TrackerSettingsScreenState extends State<TrackerSettingsScreen> {
  Tracker get _t => widget.tracker;
  bool _busy = false;

  Future<void> _connect() async {
    setState(() => _busy = true);
    bool ok;
    final trakt = _t is TraktService ? _t as TraktService : null;
    if (trakt != null) {
      // Trakt's device flow needs the user code on screen, which a generic
      // `connect()` cannot do by itself.
      final login = await trakt.beginDeviceLogin();
      if (!mounted) return;
      if (login == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.trackerConnectionCanceled(_t.displayName),
            ),
          ),
        );
        return;
      }
      ok =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _TraktDeviceDialog(trakt: trakt, login: login),
          ) ??
          false;
    } else {
      ok = await _t.connect();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.l10n.connectedAs(_t.viewerName ?? '')
              : context.l10n.trackerConnectionCanceled(_t.displayName),
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    final ok = await AppDialog.confirm(
      context,
      title: context.l10n.disconnectTrackerQuestion(_t.displayName),
      message: context.l10n.trackerDisconnectBody(_t.displayName),
      confirmLabel: context.l10n.disconnect,
      destructive: true,
    );
    if (ok == true) await _t.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(_t.displayName),
      ),
      body: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final connected = _t.isConnected;
          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              _header(connected),
              if (!connected)
                SettingsCard(
                  children: [
                    SettingsTile(
                      icon: Icons.link_rounded,
                      title: _busy ? context.l10n.connectingEllipsis : context.l10n.connectTracker(_t.displayName),
                      subtitle: _busy ? null : context.l10n.signInToLinkYourAccount,
                      onTap: _busy ? null : _connect,
                      trailing: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ],
                )
              else ...[
                SettingsCard(
                  children: [
                    SettingsTile(
                      icon: Icons.sync_rounded,
                      title: context.l10n.autoSync,
                      subtitle: context.l10n.updateTrackerAsYouWatch(_t.displayName),
                      trailing: Switch.adaptive(
                        value: _t.autoSync,
                        activeThumbColor: AppColors.accent,
                        onChanged: (v) => setState(() => _t.autoSync = v),
                      ),
                    ),
                  ],
                ),
                SettingsCard(
                  children: [
                    SettingsTile(
                      icon: Icons.logout_rounded,
                      title: context.l10n.disconnect,
                      destructive: true,
                      onTap: _disconnect,
                    ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                  'When you start an anime it’s marked Watching, each '
                  'episode you finish updates the count, and a status you set on '
                  'a title is pushed to ${_t.displayName}. Anime only.',
                  style: AppText.caption,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(bool connected) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (connected && (_t.viewerAvatar?.isNotEmpty ?? false))
            ClipOval(
              child: CachedNetworkImage(
                imageUrl: _t.viewerAvatar!,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => _fallbackAvatar(),
              ),
            )
          else
            _fallbackAvatar(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  connected ? (_t.viewerName ?? _t.displayName) : _t.displayName,
                  style: AppText.headline.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  connected ? 'Connected' : 'Not connected',
                  style: AppText.caption.copyWith(
                    color: connected ? AppColors.accent : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallbackAvatar() => Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: AppColors.surface2,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.person_rounded, color: AppColors.textTertiary),
  );
}

/// Shows the code Trakt wants typed on its activate page, and closes when the
/// device poll resolves.
class _TraktDeviceDialog extends StatefulWidget {
  const _TraktDeviceDialog({required this.trakt, required this.login});

  final TraktService trakt;
  final TraktDeviceLogin login;

  @override
  State<_TraktDeviceDialog> createState() => _TraktDeviceDialogState();
}

class _TraktDeviceDialogState extends State<_TraktDeviceDialog> {
  late final Future<bool> _poll = widget.trakt.pollDeviceLogin(widget.login);
  bool _closed = false;

  void _close(bool ok) {
    if (_closed) return;
    _closed = true;
    Navigator.pop(context, ok);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.connectTracker(widget.trakt.displayName)),
      content: FutureBuilder<bool>(
        future: _poll,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.done) {
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _close(snap.data ?? false),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.signInToLinkYourAccount),
              const SizedBox(height: 12),
              SelectableText(
                widget.login.userCode,
                style: AppText.headline.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(widget.login.verificationUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Text(context.l10n.openInBrowser),
              ),
              if (snap.connectionState != ConnectionState.done) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => _close(false),
          child: Text(context.l10n.cancel),
        ),
      ],
    );
  }
}
