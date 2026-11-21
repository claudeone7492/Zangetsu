import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/web/ad_block.dart';
import '../../core/web/redirect_allow.dart';
import '../../l10n/l10n.dart';
import 'userscripts_screen.dart';

/// Ad blocking, promo filtering and the redirect allowlist — the switches the
/// in-app browser reads. Kept separate from [PrivacySettingsScreen] because
/// these only affect [WebsiteViewScreen], not provider playback.
class WebProtectionsScreen extends StatefulWidget {
  const WebProtectionsScreen({super.key});

  @override
  State<WebProtectionsScreen> createState() => _WebProtectionsScreenState();
}

class _WebProtectionsScreenState extends State<WebProtectionsScreen> {
  bool _ads = AdBlock.instance.enabled;
  bool _promos = AdBlock.instance.promosEnabled;
  bool _busy = false;
  late final TextEditingController _allow = TextEditingController(
    text: RedirectAllow.instance.entries.join('\n'),
  );

  @override
  void dispose() {
    _allow.dispose();
    super.dispose();
  }

  Future<void> _setAds(bool value) async {
    await AdBlock.instance.setEnabled(value);
    if (mounted) setState(() => _ads = value);
  }

  Future<void> _setPromos(bool value) async {
    await AdBlock.instance.setPromosEnabled(value);
    if (mounted) setState(() => _promos = value);
  }

  Future<void> _update() async {
    setState(() => _busy = true);
    try {
      final count = await AdBlock.instance.refresh(sl<Dio>());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.adListUpdated(count))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.adListFailed)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveAllow() async {
    await RedirectAllow.instance.set(_allow.text.split(RegExp(r'[\n,]')));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.saved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text(l10n.webProtections),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _ads,
            activeThumbColor: AppColors.accent,
            onChanged: _setAds,
            title: Text(l10n.blockAds, style: AppText.body),
            subtitle: Text(
              l10n.blockAdsBody,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.download_rounded),
            title: Text(l10n.updateAdList, style: AppText.body),
            trailing: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _busy ? null : _update,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _promos,
            activeThumbColor: AppColors.accent,
            onChanged: _setPromos,
            title: Text(l10n.blockPromos, style: AppText.body),
            subtitle: Text(
              l10n.blockPromosBody,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const Divider(height: 32),
          Text(l10n.allowedHosts, style: AppText.headline),
          const SizedBox(height: 4),
          Text(
            l10n.allowedHostsBody,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _allow,
            minLines: 3,
            maxLines: 8,
            autocorrect: false,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _saveAllow,
              child: Text(l10n.save),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.code_rounded),
            title: Text(l10n.userscripts, style: AppText.body),
            subtitle: Text(
              l10n.userscriptsBody,
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const UserscriptsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
