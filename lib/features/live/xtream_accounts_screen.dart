import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/live/xtream_account_store.dart';
import '../../core/live/epg_store.dart';
import '../../core/live/xtream_api.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/states.dart';

/// Xtream Codes accounts — the panel protocol most IPTV subscriptions use.
///
/// A Xtream account replaces the public channel lists with the subscriber's
/// own line-up: live channels, VOD and series, plus the panel's own XMLTV
/// guide. Credentials are entered here and kept in secure storage, so this is
/// the one place in the app that handles a third-party password.
class XtreamAccountsScreen extends StatefulWidget {
  const XtreamAccountsScreen({super.key});

  @override
  State<XtreamAccountsScreen> createState() => _XtreamAccountsScreenState();
}

class _XtreamAccountsScreenState extends State<XtreamAccountsScreen> {
  XtreamAccountStore? _store;
  XtreamApi? _api;

  /// id → login result, so each row can show status/expiry without re-logging
  /// in on every rebuild.
  final Map<String, XtreamProfile> _profiles = {};
  final Set<String> _probing = {};

  @override
  void initState() {
    super.initState();
    _store = sl.isRegistered<XtreamAccountStore>()
        ? sl<XtreamAccountStore>()
        : null;
    _api = sl.isRegistered<XtreamApi>() ? sl<XtreamApi>() : null;
    _store?.addListener(_changed);
    _probeAll();
  }

  @override
  void dispose() {
    _store?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _probeAll() async {
    final store = _store;
    final api = _api;
    if (store == null || api == null) return;
    await store.ensureLoaded();
    for (final account in store.accounts) {
      await _probe(account, api);
    }
  }

  Future<void> _probe(XtreamAccount account, XtreamApi api) async {
    if (!_probing.add(account.id)) return;
    try {
      final profile = await api.login(account);
      if (mounted) setState(() => _profiles[account.id] = profile);
    } catch (e) {
      if (mounted) setState(() => _profiles.remove(account.id));
    } finally {
      _probing.remove(account.id);
    }
  }

  Future<void> _add() async {
    final store = _store;
    final api = _api;
    if (store == null || api == null) return;

    final result = await showModalBottomSheet<_NewAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (context) => const _AddAccountSheet(),
    );
    if (result == null || !mounted) return;

    try {
      final account = await store.add(
        host: result.host,
        username: result.username,
        password: result.password,
        label: result.label,
      );
      // Log in immediately: a wrong password should fail here, while the user
      // is still looking at the form, not silently later.
      await _probe(account, api);
      // The panel publishes its own XMLTV guide; register it so channels from
      // this account resolve in the TV guide without the user adding a feed.
      if (sl.isRegistered<EpgStore>()) {
        await sl<EpgStore>().addSource(
          EpgSource(url: api.epgUrl(account), name: account.displayName),
        );
      }
      if (!mounted) return;
      final profile = _profiles[account.id];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profile == null
                ? 'Added, but the panel rejected the login'
                : 'Added · ${profile.status}'
                      '${profile.daysLeft != null ? ' · ${profile.daysLeft} days left' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        'Xtream accounts',
        actions: [
          if (store != null)
            IconButton(
              tooltip: 'Add account',
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: store == null
          ? const EmptyState(
              icon: Icons.dns_outlined,
              message: 'Xtream accounts are not available on this device',
            )
          : store.accounts.isEmpty
          ? EmptyState(
              icon: Icons.live_tv_outlined,
              message:
                  'No Xtream accounts.\nAdd your IPTV subscription to get its '
                  'live channels, films, series and TV guide.',
              actionLabel: 'Add account',
              onAction: _add,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                Text(
                  '${store.accounts.length} account(s)',
                  style: AppText.overline,
                ),
                const SizedBox(height: 8),
                for (final account in store.accounts)
                  _accountRow(store, account),
              ],
            ),
    );
  }

  Widget _accountRow(XtreamAccountStore store, XtreamAccount account) {
    final profile = _profiles[account.id];
    final probing = _probing.contains(account.id);
    final subtitle = probing
        ? 'Checking…'
        : profile == null
        ? 'Login failed'
        : '${profile.status}'
              '${profile.daysLeft != null ? ' · ${profile.daysLeft} days left' : ''}'
              '${profile.maxConnections != null ? ' · ${profile.maxConnections} connections' : ''}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            profile?.isActive == true
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            size: 20,
            color: profile?.isActive == true
                ? AppColors.accent
                : AppColors.textTertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.displayName, style: AppText.body),
                Text(
                  subtitle,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            onPressed: () => store.remove(account.id),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

/// The values collected by the add-account sheet.
class _NewAccount {
  const _NewAccount({
    required this.host,
    required this.username,
    required this.password,
    required this.label,
  });

  final String host;
  final String username;
  final String password;
  final String label;
}

class _AddAccountSheet extends StatefulWidget {
  const _AddAccountSheet();

  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  final _host = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _label = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _host.dispose();
    _username.dispose();
    _password.dispose();
    _label.dispose();
    super.dispose();
  }

  void _submit() {
    if (_host.text.trim().isEmpty || _username.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      _NewAccount(
        host: _host.text,
        username: _username.text,
        password: _password.text,
        label: _label.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        _host.text.trim().isNotEmpty && _username.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Xtream account', style: AppText.barTitle),
          const SizedBox(height: 16),
          TextField(
            controller: _host,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Panel address',
              hintText: 'http://example.tv:8080',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: 'Username'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              hintText: 'Living room',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit ? _submit : null,
              child: const Text('Add account'),
            ),
          ),
        ],
      ),
    );
  }
}
