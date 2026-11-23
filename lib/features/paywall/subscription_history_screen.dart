import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'paywall_screen.dart';

/// This device's plan and its own payment history.
///
/// The server scopes `device_transactions` to the device session that started
/// the checkout, so a shared-plan guest never sees the payer's card history.
/// Every charge is billed to the merchant Kora account, but the reference on
/// each row is the link back to the device that initiated it.
class SubscriptionHistoryScreen extends StatefulWidget {
  const SubscriptionHistoryScreen({super.key});

  @override
  State<SubscriptionHistoryScreen> createState() =>
      _SubscriptionHistoryScreenState();
}

class _SubscriptionHistoryScreenState extends State<SubscriptionHistoryScreen> {
  SubscriptionApi get _api => sl<SubscriptionApi>();

  bool _loading = true;
  DeviceIdentity? _identity;
  List<DeviceTransaction>? _transactions;
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
    final results = await Future.wait<Object?>([
      _api.identify(),
      _api.transactions(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _identity = results[0] as DeviceIdentity?;
      _transactions = results[1] as List<DeviceTransaction>?;
      if (_transactions == null) {
        _error = 'Could not load payments for this device. Pull to retry.';
      }
    });
  }

  Future<void> _openPlans() async {
    final unlocked = await showPaywall(context, dismissible: true);
    if (unlocked && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription & payments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  if (_error != null) _notice(_error!),
                  _planCard(),
                  const SizedBox(height: 20),
                  _sectionHeader(),
                  const SizedBox(height: 8),
                  ..._transactionsList(),
                ],
              ),
            ),
    );
  }

  Widget _planCard() {
    final identity = _identity;
    final unavailable = identity == null;
    final active = identity?.entitled == true;
    final trial = identity?.isTrial == true;
    final title = unavailable
        ? 'Plan status unavailable'
        : active
        ? kPremiumPlanLabel
        : 'No active plan';
    final subtitle = unavailable
        ? 'Could not read this device\'s plan. Pull to refresh or retry below.'
        : active
        ? _periodLine(identity)
        : 'This device has no active subscription. Choose a plan to start '
              'watching.';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: active ? AppColors.accent : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: AppText.headline)),
              if (active) _statusChip(trial ? 'Trial' : 'Active', active: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: unavailable
                ? FilledButton(onPressed: _load, child: const Text('Retry'))
                : OutlinedButton(
                    onPressed: _openPlans,
                    child: Text(active ? 'Manage plan' : 'View plans'),
                  ),
          ),
        ],
      ),
    );
  }

  String _periodLine(DeviceIdentity? identity) {
    if (identity == null) return 'Plan details are unavailable right now.';
    if (identity.isTrial) {
      return 'Free trial · ${identity.daysLeft} days left';
    }
    final end = identity.periodEnd;
    if (end == null) return 'Your plan is active on this device.';
    return 'Renews or ends on ${_date(end)}';
  }

  Widget _sectionHeader() {
    final count = _transactions?.length ?? 0;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Payments on this device',
            style: AppText.headline.copyWith(fontSize: 16),
          ),
        ),
        if (count > 0)
          Text(
            '$count',
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
      ],
    );
  }

  List<Widget> _transactionsList() {
    final transactions = _transactions;
    if (transactions == null) return const [];
    if (transactions.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            'No payments yet. Your completed and pending charges will appear '
            'here with the reference for support.',
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
        ),
      ];
    }
    return [for (final tx in transactions) _transactionTile(tx)];
  }

  Widget _transactionTile(DeviceTransaction tx) {
    final color = tx.completed
        ? AppColors.accent
        : tx.failed
        ? AppColors.textTertiary
        : AppColors.textSecondary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.settingsCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tx.title,
                  style: AppText.body.copyWith(color: Colors.white),
                ),
              ),
              Text(
                money(tx.amountCents),
                style: AppText.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _statusChip(_statusLabel(tx.status), active: tx.completed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _date(tx.createdAt),
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  tx.reference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy reference',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: tx.reference));
                  if (mounted) _say('Reference copied');
                },
                icon: const Icon(Icons.copy_rounded, size: 17),
                color: color,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String label, {required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: active ? AppColors.accentSoft : AppColors.hairline,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: active ? AppColors.accent : AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'completed' => 'Paid',
    'pending' => 'Pending',
    'failed' => 'Failed',
    'refunded' => 'Refunded',
    _ => status,
  };

  String _date(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  Widget _notice(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: AppText.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
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
}
