import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/collections/nuvio_import.dart';
import '../../core/mihon/tachiyomi_backup.dart';
import '../../core/music/lossless_source.dart';
import '../../core/music/potoken.dart';
import '../../core/parity/parity_native.dart';
import '../../core/tracker/kitsu_service.dart';
import '../../core/tracker/shikimori_service.dart';
import '../../core/ui/help_sheet.dart';
import '../../core/ui/ui_scale.dart';
import '../../core/music/vx_quality.dart';
import '../../core/net/dns_providers.dart';
import '../../core/ui/header_prefs.dart';
import 'dns_mode_screen.dart';
import 'music_quality_screen.dart';
import '../../l10n/l10n.dart';
import '../home/tmdb_browse_screen.dart';

/// One place for the integrations that used to have no entry point:
/// the two importers, the lossless endpoint, tracker configuration and the
/// in-app UI scale.
class ParityToolsScreen extends StatefulWidget {
  const ParityToolsScreen({super.key});

  @override
  State<ParityToolsScreen> createState() => _ParityToolsScreenState();
}

class _ParityToolsScreenState extends State<ParityToolsScreen> {
  final _nuvio = TextEditingController();
  final _tachiyomi = TextEditingController();
  final _losslessUrl = TextEditingController();
  final _losslessKey = TextEditingController();
  String? _status;
  double _scale = UiScale.factor;
  int _header = HeaderPrefs.percent;
  List<String>? _voicePacks;
  bool _tdlib = false;

  @override
  void initState() {
    super.initState();
    _losslessUrl.text = LosslessSource.baseUrl;
    _losslessKey.text = LosslessSource.apiKey;
    unawaited(_loadVoicePacks());
  }

  Future<void> _loadVoicePacks() async {
    final packs = await ParityNative.voicePacks();
    final tdlib = await ParityNative.tdlibAvailable();
    if (mounted) {
      setState(() {
        _voicePacks = packs;
        _tdlib = tdlib;
      });
    }
  }

  @override
  void dispose() {
    _nuvio.dispose();
    _tachiyomi.dispose();
    _losslessUrl.dispose();
    _losslessKey.dispose();
    super.dispose();
  }

  void _importNuvio() {
    try {
      final collections = NuvioImport.parse(_nuvio.text);
      final count = collections.fold<int>(0, (sum, c) => sum + c.items.length);
      setState(() => _status = 'Nuvio: ${collections.length} collections, $count titles');
    } catch (error) {
      setState(() => _status = 'Nuvio import failed: $error');
    }
  }

  void _importTachiyomi() {
    try {
      final entries = TachiyomiBackup.parse(_tachiyomi.text);
      setState(() => _status = 'Tachiyomi: ${entries.length} manga');
    } catch (error) {
      setState(() => _status = 'Tachiyomi import failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parity tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Nuvio import', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _nuvio,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Paste the Nuvio JSON export'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _importNuvio, child: const Text('Parse Nuvio')),
          const Divider(height: 32),
          Text('Tachiyomi / Mihon import', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _tachiyomi,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Paste the unpacked backup JSON'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _importTachiyomi, child: const Text('Parse backup')),
          const Divider(height: 32),
          Text('Lossless music endpoint', style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _losslessUrl,
            decoration: const InputDecoration(hintText: 'https://music.example.com'),
          ),
          TextField(
            controller: _losslessKey,
            decoration: const InputDecoration(hintText: 'API key (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () async {
              await LosslessSource.save(
                baseUrl: _losslessUrl.text,
                apiKey: _losslessKey.text,
              );
              if (mounted) {
                setState(
                  () => _status = LosslessSource.baseUrl.isNotEmpty
                      ? 'Lossless endpoint saved'
                      : 'Lossless endpoint cleared',
                );
              }
            },
            child: const Text('Save endpoint'),
          ),
          ListTile(
            leading: const Icon(Icons.music_video_outlined),
            title: const Text('YouTube Music'),
            subtitle: Text(
              YouTubePoToken.isAvailable
                  ? 'Catalogue ready · PO token minted on demand'
                  : 'Catalogue ready · PO token unavailable on this build, '
                        'native clients still play',
            ),
          ),
          const Divider(height: 32),
          Text('Trackers', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            title: const Text('Kitsu'),
            subtitle: Text(KitsuService.clientId.isEmpty ? 'Not configured' : 'Configured'),
          ),
          ListTile(
            title: const Text('Shikimori'),
            subtitle: Text(ShikimoriService.clientId.isEmpty ? 'Not configured' : 'Configured'),
          ),
          const Divider(height: 32),
          Text('UI scale', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _scale,
            min: UiScale.min,
            max: UiScale.max,
            divisions: 12,
            label: '${(_scale * 100).round()}%',
            onChanged: (value) {
              UiScale.set(value);
              setState(() => _scale = value);
            },
          ),
          Text(
            context.l10n.detailHeaderHeight,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Slider(
            value: _header.toDouble(),
            min: HeaderPrefs.minPercent.toDouble(),
            max: HeaderPrefs.maxPercent.toDouble(),
            divisions: 10,
            label: '$_header%',
            onChanged: (value) {
              HeaderPrefs.setPercent(value.round());
              setState(() => _header = value.round());
            },
          ),
          ListTile(
            leading: const Icon(Icons.graphic_eq),
            title: Text(context.l10n.equalizer),
            subtitle: Text(
              '${context.l10n.streamingQuality}: '
              '${VxQuality.labelFor(VxQuality.streamQuality)}',
            ),
            onTap: () => Navigator.push(context, MusicQualityScreen.route()),
          ),
          ListTile(
            leading: const Icon(Icons.movie_filter_outlined),
            title: Text(context.l10n.tmdbBrowse),
            subtitle: Text(context.l10n.tmdbTrending),
            onTap: () => Navigator.push(context, TmdbBrowseScreen.route()),
          ),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: Text(context.l10n.dnsMode),
            subtitle: Text(DnsProviders.byKey(DnsProviders.choice).label),
            onTap: () => Navigator.push(context, DnsModeScreen.route()),
          ),
          const Divider(height: 32),
          Text('Native seams', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            dense: true,
            title: const Text('Frame capture with subtitles'),
            subtitle: Text(
              ParityNative.isSupported
                  ? 'Saves to Pictures/Zangetsu'
                  : 'Android only; the raw-frame fallback is used',
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('Background job keeper'),
            subtitle: Text(
              ParityNative.workLabel.isEmpty
                  ? 'Idle'
                  : 'Running: ${ParityNative.workLabel}',
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('Offline voice packs'),
            subtitle: Text(
              _voicePacks == null
                  ? 'Checking…'
                  : _voicePacks!.isEmpty
                  ? 'None downloaded — hosted voices are used'
                  : '${_voicePacks!.length} installed: ${_voicePacks!.join(', ')}',
            ),
            trailing: ParityNative.isSupported
                ? TextButton(
                    onPressed: () {
                      unawaited(ParityNative.openTtsSettings());
                      // The packs are downloaded in another screen, so the
                      // list is stale on return; re-reading is the only way to
                      // see a fresh one.
                      unawaited(_loadVoicePacks());
                    },
                    child: const Text('Download'),
                  )
                : null,
          ),
          ListTile(
            dense: true,
            title: const Text('Telegram (TDLib)'),
            subtitle: Text(
              _tdlib
                  ? 'Linked — private channels available'
                  : 'Not in this build — Telegram streams public channels '
                        'through the web preview',
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('How this page works'),
            onTap: () => showHelpSheet(
              context,
              title: 'Parity tools',
              body: 'Import your Nuvio collections and Tachiyomi library, point '
                  'the lossless source at your own server, and scale the UI.',
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
