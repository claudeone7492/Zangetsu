import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/collections/nuvio_import.dart';
import '../../core/mihon/tachiyomi_backup.dart';
import '../../core/music/lossless_source.dart';
import '../../core/parity/parity_native.dart';
import '../../core/tracker/kitsu_service.dart';
import '../../core/tracker/shikimori_service.dart';
import '../../core/ui/help_sheet.dart';
import '../../core/ui/ui_scale.dart';

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
  List<String>? _voicePacks;

  @override
  void initState() {
    super.initState();
    _losslessUrl.text = LosslessSource.baseUrl;
    _losslessKey.text = LosslessSource.apiKey;
    unawaited(_loadVoicePacks());
  }

  Future<void> _loadVoicePacks() async {
    final packs = await ParityNative.voicePacks();
    if (mounted) setState(() => _voicePacks = packs);
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
                  ? 'None installed — hosted voices are used'
                  : _voicePacks!.join(', '),
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('Telegram (TDLib)'),
            subtitle: const Text('Not in this build — Telegram uses the Bot API'),
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
