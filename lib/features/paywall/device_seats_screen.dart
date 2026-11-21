import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// The devices sharing this plan — the owner's view (code to add one, list,
/// revoke) and the guest's view (what it is on, leave).
///
/// Everything here is answered by `device_seat_list` / `create_device_code` /
/// `revoke_device_seat`; the app holds no seat state of its own, so two phones
/// looking at the same plan always agree.
class DeviceSeatsScreen extends StatefulWidget {
  const DeviceSeatsScreen({super.key});

  @override
  State<DeviceSeatsScreen> createState() => _DeviceSeatsScreenState();
}

class _DeviceSeatsScreenState extends State<DeviceSeatsScreen> {
  SubscriptionApi get _api => sl<SubscriptionApi>();

  bool _loading = true;
  bool _busy = false;
  SeatSummary? _summary;
  SeatResult? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final summary = await _api.deviceSeats();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _summary = summary;
      if (summary == null) {
        _error = 'Couldn\'t load the devices on this plan.';
      }
    });
  }

  Future<void> _createCode() async {
    setState(() => _busy = true);
    final result = await _api.createDeviceCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result?.ok == true) _code = result;
    });
    if (result != null && !result.ok) _say(result.message);
  }

  Future<void> _revoke(DeviceSeat seat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface2,
        title: Text(seat.isSelf ? 'Leave this plan?' : 'Remove this device?'),
        content: Text(
          seat.isSelf
              ? '${seat.displayName} goes back to the paywall until it joins a '
                    'plan again.'
              : '${seat.displayName} loses access at its next check.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(seat.isSelf ? 'Leave' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final ok = await _api.revokeDeviceSeat(seat.fingerprint);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _say('Could not remove that device. Try again.');
      return;
    }
    _code = null;
    await _load();
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.surface2,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Devices on this plan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                if (_error != null) _notice(_error!),
                if (_summary != null) ..._body(_summary!),
              ],
            ),
    );
  }

  List<Widget> _body(SeatSummary summary) {
    final seats = summary.seats;
    final owner = seats.where((s) => s.isSelf).firstOrNull;
    return [
      if (summary.isSeat)
        _notice(
          'This device is on a shared plan. The person who pays controls the '
          'devices on it.',
        ),
      const SizedBox(height: 4),
      Row(
        children: [
          Expanded(
            child: Text(
              '${summary.seatsUsed} of ${summary.seatLimit} devices',
              style: AppText.title.copyWith(color: Colors.white),
            ),
          ),
          if (!summary.isSeat && summary.seatsLeft > 0)
            FilledButton.icon(
              onPressed: _busy ? null : _createCode,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(_code == null ? 'Add a device' : 'New code'),
            ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        summary.isSeat
            ? 'Your access follows the plan: it ends when the plan ends.'
            : 'A code lets one more device watch on this plan until you remove '
                  'it.',
        style: AppText.caption.copyWith(color: AppColors.textTertiary),
      ),
      if (_code != null) ...[const SizedBox(height: 16), _codePanel(_code!)],
      const SizedBox(height: 18),
      for (final seat in seats) _seatTile(seat, summary),
      if (!summary.isSeat && summary.seatsLeft == 0 && seats.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Text(
            'Every device on this plan is in use. Remove one to make room.',
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
        ),
      if (summary.isSeat && owner != null)
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: OutlinedButton(
            onPressed: _busy ? null : () => _revoke(owner),
            child: const Text('Leave this plan'),
          ),
        ),
    ];
  }

  Widget _seatTile(DeviceSeat seat, SeatSummary summary) {
    final canRemove = !summary.isSeat && !seat.isSelf;
    return Card(
      color: AppColors.surface2,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          seat.isSelf ? Icons.smartphone_rounded : Icons.devices_other_rounded,
          color: seat.isSelf ? AppColors.accent : AppColors.textSecondary,
        ),
        title: Text(
          seat.displayName,
          style: AppText.body.copyWith(color: Colors.white),
        ),
        subtitle: Text(
          seat.isSelf ? 'This device' : _subtitleFor(seat),
          style: AppText.caption.copyWith(color: AppColors.textTertiary),
        ),
        trailing: canRemove
            ? IconButton(
                tooltip: 'Remove',
                onPressed: _busy ? null : () => _revoke(seat),
                icon: const Icon(Icons.link_off_rounded),
              )
            : null,
      ),
    );
  }

  String _subtitleFor(DeviceSeat seat) {
    final seen = seat.lastSeenAt;
    if (seen == null) return 'Linked device';
    final d = DateTime.now().difference(seen);
    if (d.inMinutes < 1) return 'Active now';
    if (d.inMinutes < 60) return 'Active ${d.inMinutes}m ago';
    if (d.inHours < 24) return 'Active ${d.inHours}h ago';
    return 'Active ${d.inDays}d ago';
  }

  Widget _codePanel(SeatResult code) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter this on the other device',
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  code.code ?? '',
                  style: AppText.title.copyWith(
                    color: Colors.white,
                    fontSize: 30,
                    letterSpacing: 8,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy code',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code.code ?? ''));
                  if (mounted) _say('Code copied');
                },
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Valid for 10 minutes, one device. On the other device: Subscribe '
            '→ "On someone\'s plan? Enter their code".',
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _notice(String text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
