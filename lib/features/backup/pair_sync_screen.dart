import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/backup/backup_payload.dart';
import '../../core/backup/backup_service.dart';
import '../../core/di/injector.dart';
import '../../core/pair/pair_protocol.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';

/// Send or receive a backup over the local Wi-Fi, with no cloud account.
///
/// Both devices run this screen: one taps "Send" and reads its code out, the
/// other taps "Receive", picks the sender it hears and types that code. The
/// payload is the same map the file/cloud backup produces, so a paired
/// transfer and a file export are interchangeable.
class PairSyncScreen extends StatefulWidget {
  const PairSyncScreen({super.key});

  @override
  State<PairSyncScreen> createState() => _PairSyncScreenState();
}

enum _Role { idle, sending, receiving }

class _PairSyncScreenState extends State<PairSyncScreen> {
  final Set<BackupBundle> _selected = {...BackupBundle.values};
  _Role _role = _Role.idle;
  PairSender? _sender;
  PairListener? _listener;
  final List<PairPeer> _peers = [];
  final _codeCtrl = TextEditingController();
  PairPeer? _chosen;
  bool _busy = false;
  String? _error;

  BackupService get _service => sl<BackupService>();

  @override
  void dispose() {
    _sender?.stop();
    _listener?.stop();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _startSending() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await _service.buildProtected(_selected, forFile: false);
      final sender = PairSender(
        payload: payload,
        deviceName: Platform.isAndroid ? 'Android device' : 'This device',
      );
      await sender.start(fallbackPort: kPairPort + 1);
      if (!mounted) {
        await sender.stop();
        return;
      }
      setState(() {
        _role = _Role.sending;
        _sender = sender;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start sending: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startReceiving() async {
    setState(() {
      _busy = true;
      _error = null;
      _peers.clear();
      _chosen = null;
    });
    final listener = PairListener();
    await listener.start(
      onPeer: (peer) {
        if (!mounted) return;
        // Replace a stale entry for the same host:port rather than appending.
        setState(() {
          _peers.removeWhere((p) => p.host == peer.host);
          _peers.add(peer);
        });
      },
      onError: (e) {
        if (mounted) setState(() => _error = 'Could not listen: $e');
      },
    );
    if (!mounted) {
      await listener.stop();
      return;
    }
    setState(() {
      _role = _Role.receiving;
      _listener = listener;
      _busy = false;
    });
  }

  Future<void> _stop() async {
    await _sender?.stop();
    await _listener?.stop();
    if (!mounted) return;
    setState(() {
      _role = _Role.idle;
      _sender = null;
      _listener = null;
      _peers.clear();
      _chosen = null;
    });
  }

  Future<void> _receive() async {
    final peer = _chosen;
    final code = _codeCtrl.text.trim();
    if (peer == null || code.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await fetchPairedBackup(peer, code: code);
      final report = await _service.restore(payload, _selected);
      if (!mounted) return;
      await _stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            report.failures.isEmpty
                ? 'Restored from ${peer.deviceName}.'
                : 'Restored with issues: ${report.failures.join('; ')}',
          ),
        ),
      );
      Navigator.pop(context, true);
    } on PairException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Restore failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar('Pair & sync'),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 28),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text(
                  'Move a backup straight between two devices on the same '
                  'Wi-Fi. Nothing goes through a server.',
                  style: AppText.caption,
                ),
              ),
              SettingsSectionLabel('Include in the transfer'),
              SettingsCard(
                children: [
                  for (final b in BackupBundle.values)
                    SettingsTile(
                      icon: _selected.contains(b)
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                      title: switch (b) {
                        BackupBundle.sources => 'Sources and repos',
                        BackupBundle.library => 'Library',
                        BackupBundle.settings => 'Settings',
                      },
                      onTap: _busy || _role != _Role.idle
                          ? null
                          : () => setState(() {
                              if (!_selected.remove(b)) _selected.add(b);
                            }),
                    ),
                ],
              ),
              if (_role == _Role.idle) ...[
                const SettingsSectionLabel('Choose a side'),
                SettingsCard(
                  children: [
                    SettingsTile(
                      icon: Icons.upload_rounded,
                      title: 'Send from this device',
                      subtitle: 'Shows a code the other device types in',
                      onTap: _busy ? null : _startSending,
                    ),
                    SettingsTile(
                      icon: Icons.download_rounded,
                      title: 'Receive on this device',
                      subtitle: 'Finds senders on your Wi-Fi',
                      onTap: _busy ? null : _startReceiving,
                    ),
                  ],
                ),
              ],
              if (_role == _Role.sending) _sendingCard(),
              if (_role == _Role.receiving) _receivingCard(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    _error!,
                    style: AppText.caption.copyWith(color: AppColors.accent),
                  ),
                ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sendingCard() {
    final sender = _sender;
    if (sender == null) return const SizedBox.shrink();
    // The QR carries the same code as the text below, so a device with a
    // scanner can skip typing.
    final qrData = 'zangetsu-pair:${sender.code}:${sender.beacon.port}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Waiting for the other device'),
        SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(10),
                    child: QrImageView(data: qrData, size: 168),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    sender.code,
                    style: AppText.headline.copyWith(
                      fontSize: 34,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Type this code on the other device.',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            SettingsTile(
              icon: Icons.close_rounded,
              title: 'Cancel',
              onTap: _stop,
            ),
          ],
        ),
      ],
    );
  }

  Widget _receivingCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Senders found'),
        SettingsCard(
          children: [
            if (_peers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Looking for a device that is sending…',
                  style: AppText.caption,
                ),
              )
            else
              for (final peer in _peers)
                SettingsTile(
                  icon: peer == _chosen
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  title: peer.deviceName,
                  subtitle: peer.host,
                  onTap: () => setState(() => _chosen = peer),
                ),
          ],
        ),
        if (_peers.isNotEmpty) ...[
          const SettingsSectionLabel('Pairing code'),
          SettingsCard(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      style: AppText.body.copyWith(letterSpacing: 6),
                      decoration: const InputDecoration(
                        hintText: '123456',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy || _chosen == null ? null : _receive,
                      child: const Text('Restore from this device'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        SettingsCard(
          children: [
            SettingsTile(
              icon: Icons.close_rounded,
              title: 'Cancel',
              onTap: _stop,
            ),
          ],
        ),
      ],
    );
  }
}
