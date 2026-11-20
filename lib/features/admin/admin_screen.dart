import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'admin_cubit.dart';
import '../../l10n/l10n.dart';

/// Opens the in-app admin console. There is no server account: the operator
/// sets a passcode on first use and signs in with it thereafter.
Future<void> showAdminConsole(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute(builder: (_) => const AdminScreen()));

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => AdminCubit(sl())..init(),
    child: const _AdminView(),
  );
}

class _AdminView extends StatelessWidget {
  const _AdminView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: Text(context.l10n.adminTitle, style: AppText.title),
      ),
      body: BlocBuilder<AdminCubit, AdminState>(
        builder: (context, state) {
          switch (state.gate) {
            case AdminGate.checking:
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2.4),
              );
            case AdminGate.needsSetup:
              return _Gate(
                title: 'Create admin passcode',
                cta: 'Create passcode',
                onSubmit: (p) => context.read<AdminCubit>().setup(p),
              );
            case AdminGate.locked:
              return _Gate(
                title: 'Enter admin passcode',
                cta: 'Unlock',
                onSubmit: (p) => context.read<AdminCubit>().unlock(p),
              );
            case AdminGate.unlocked:
              return const _Console();
          }
        },
      ),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate({required this.title, required this.cta, required this.onSubmit});

  final String title;
  final String cta;
  final Future<bool> Function(String) onSubmit;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminCubit>().state;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.lock_outline, color: AppColors.accent, size: 40),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: AppText.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              obscureText: true,
              style: AppText.body.copyWith(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Passcode',
                hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.hairline),
                ),
              ),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 10),
              Text(
                state.error!,
                style: AppText.caption.copyWith(color: AppColors.accent),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: state.busy
                    ? null
                    : () => widget.onSubmit(_controller.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  widget.cta,
                  style: AppText.button.copyWith(color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Console extends StatelessWidget {
  const _Console();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    final state = context.watch<AdminCubit>().state;
    return Column(
      children: [
        _Kpis(state: state),
        _Tabs(
          tab: state.tab,
          onChanged: cubit.setTab,
          onRefresh: cubit.refresh,
          busy: state.busy,
        ),
        const Divider(height: 1, color: AppColors.hairline),
        Expanded(
          child: switch (state.tab) {
            AdminTab.devices => _DevicesTable(rows: state.devices),
            AdminTab.promos => _PromosTable(
              rows: state.promos,
              onEdit: (row) => _editPromo(context, row),
              onToggle: (row) => cubit.setPromo(
                code: row.code,
                percentOff: row.percentOff,
                active: !row.active,
                expiresAt: row.expiresAt,
                maxUses: row.maxUses,
              ),
            ),
            AdminTab.subscriptions => _SubsTable(rows: state.plans),
          },
        ),
      ],
    );
  }

  Future<void> _editPromo(BuildContext context, AdminPromoRow row) async {
    final cubit = context.read<AdminCubit>();
    final percent = TextEditingController(text: '${row.percentOff}');
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(row.code, style: AppText.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: percent,
              keyboardType: TextInputType.number,
              style: AppText.body.copyWith(color: Colors.white),
              decoration: const InputDecoration(labelText: '% off'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  row.expiresAt == null
                      ? 'No expiry'
                      : 'Expires ${row.expiresAt!.toIso8601String().substring(0, 10)}',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 3),
                      ),
                      initialDate:
                          row.expiresAt ??
                          DateTime.now().add(const Duration(days: 30)),
                    );
                    if (picked != null && context.mounted) {
                      Navigator.of(context).pop(true);
                      await cubit.setPromo(
                        code: row.code,
                        percentOff:
                            int.tryParse(percent.text) ?? row.percentOff,
                        active: row.active,
                        expiresAt: picked,
                        maxUses: row.maxUses,
                      );
                    }
                  },
                  child: Text(
                    context.l10n.adminChangeExpiry,
                    style: AppText.caption.copyWith(color: AppColors.accent),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
    if (result == true) {
      await cubit.setPromo(
        code: row.code,
        percentOff: int.tryParse(percent.text) ?? row.percentOff,
        active: row.active,
        expiresAt: row.expiresAt,
        maxUses: row.maxUses,
      );
    }
    percent.dispose();
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.state});
  final AdminState state;

  @override
  Widget build(BuildContext context) {
    final mrr = money(state.mrrCents);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          _Kpi(label: 'Devices', value: '${state.devices.length}'),
          _Kpi(label: 'Active now', value: '${state.activeDevices}'),
          _Kpi(label: 'Active subs', value: '${state.activeSubs}'),
          _Kpi(label: 'MRR', value: mrr),
          _Kpi(label: 'Free access', value: '${state.freeAccess}'),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 4),
          Text(value, style: AppText.headline),
        ],
      ),
    ),
  );
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.tab,
    required this.onChanged,
    required this.onRefresh,
    required this.busy,
  });

  final AdminTab tab;
  final ValueChanged<AdminTab> onChanged;
  final VoidCallback onRefresh;
  final bool busy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Row(
      children: [
        for (final t in AdminTab.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(_label(t)),
              selected: t == tab,
              onSelected: (_) => onChanged(t),
              backgroundColor: AppColors.surface,
              selectedColor: AppColors.accentSoft,
              labelStyle: AppText.caption.copyWith(
                color: t == tab ? AppColors.accent : AppColors.textSecondary,
              ),
              side: BorderSide(color: AppColors.hairline),
            ),
          ),
        const Spacer(),
        if (busy)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh, size: 20),
            color: AppColors.textSecondary,
          ),
      ],
    ),
  );

  static String _label(AdminTab t) => switch (t) {
    AdminTab.devices => 'Devices & Users',
    AdminTab.promos => 'Promo Codes',
    AdminTab.subscriptions => 'Subscriptions',
  };
}

class _DevicesTable extends StatelessWidget {
  const _DevicesTable({required this.rows});
  final List<AdminDeviceRow> rows;

  @override
  Widget build(BuildContext context) => _Table(
    columns: const [
      'Fingerprint',
      'Platform',
      'Plan',
      'Promo',
      '% off',
      'Paid/mo',
      'Status',
      'Active',
      'Seen',
      'Watch',
    ],
    rows: [
      for (final r in rows)
        [
          _short(r.fingerprint),
          r.platform ?? '—',
          r.plan ?? '—',
          r.promo ?? '—',
          '${r.percentOff}%',
          money(r.paidCents),
          r.status,
          r.isActive ? 'active' : 'idle',
          r.lastSeenLabel.isEmpty ? '—' : r.lastSeenLabel,
          '${r.watch}',
        ],
    ],
  );

  static String _short(String fp) => fp.length <= 12
      ? fp
      : '${fp.substring(0, 6)}…${fp.substring(fp.length - 4)}';
}

class _PromosTable extends StatelessWidget {
  const _PromosTable({
    required this.rows,
    required this.onEdit,
    required this.onToggle,
  });

  final List<AdminPromoRow> rows;
  final ValueChanged<AdminPromoRow> onEdit;
  final ValueChanged<AdminPromoRow> onToggle;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      for (final r in rows)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.code, style: AppText.headline),
                    const SizedBox(height: 2),
                    Text(
                      '${r.percentOff}% off · used ${r.usedCount}'
                      '${r.maxUses == null ? '' : ' / ${r.maxUses}'}'
                      '${r.expiresAt == null ? '' : ' · exp ${r.expiresAt!.toIso8601String().substring(0, 10)}'}',
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onEdit(r),
                icon: const Icon(Icons.edit, size: 18),
                color: AppColors.textSecondary,
              ),
              Switch(
                value: r.active,
                onChanged: (_) => onToggle(r),
                activeThumbColor: AppColors.accent,
              ),
            ],
          ),
        ),
    ],
  );
}

class _SubsTable extends StatelessWidget {
  const _SubsTable({required this.rows});
  final List<AdminPlanRow> rows;

  @override
  Widget build(BuildContext context) => _Table(
    columns: const ['Plan', 'Subscribers', 'Price', 'Revenue/mo'],
    rows: [
      for (final r in rows)
        [
          r.plan,
          '${r.subscribers}',
          money(r.priceCents),
          money(r.revenueCents),
        ],
    ],
  );
}

class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows});
  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(AppColors.surface),
        columns: [
          for (final c in columns)
            DataColumn(
              label: Text(
                c,
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
        ],
        rows: [
          for (final r in rows)
            DataRow(
              cells: [
                for (final cell in r)
                  DataCell(Text(cell, style: AppText.caption)),
              ],
            ),
        ],
      ),
    ),
  );
}
