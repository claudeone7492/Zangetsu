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
        actions: [
          if (context.watch<AdminCubit>().state.gate == AdminGate.unlocked)
            IconButton(
              tooltip: 'Sign out',
              onPressed: context.read<AdminCubit>().lock,
              icon: const Icon(Icons.logout, size: 20),
            ),
        ],
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
                title: context.l10n.adminCreatePasscode,
                cta: 'Create admin login',
                onSubmit: (email, password) =>
                    context.read<AdminCubit>().setup(email, password),
              );
            case AdminGate.locked:
              return _Gate(
                title: context.l10n.adminEnterPasscode,
                cta: 'Sign in',
                onSubmit: (email, password) =>
                    context.read<AdminCubit>().unlock(email, password),
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
  final Future<bool> Function(String email, String password) onSubmit;

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  InputDecoration _field(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
    filled: true,
    fillColor: AppColors.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppColors.hairline),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AdminCubit>().state;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.admin_panel_settings_outlined,
              color: AppColors.accent,
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: AppText.title,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              style: AppText.body.copyWith(color: Colors.white),
              decoration: _field('Admin email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              obscureText: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              style: AppText.body.copyWith(color: Colors.white),
              decoration: _field(context.l10n.adminPasscode),
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
                onPressed: state.busy ? null : _submit,
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

  void _submit() {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) return;
    widget.onSubmit(email, password);
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
        if (state.error != null)
          Container(
            width: double.infinity,
            color: AppColors.accent.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              state.error!,
              style: AppText.caption.copyWith(color: AppColors.accent),
            ),
          ),
        const Divider(height: 1, color: AppColors.hairline),
        Expanded(
          child: switch (state.tab) {
            AdminTab.overview => _OverviewTab(state: state, cubit: cubit),
            AdminTab.devices => _DevicesTable(
              rows: state.devices,
              onRefreshTrial: (row) => cubit.refreshTrial(row.fingerprint),
              onGrant: (row) => _grant(context, cubit, row),
              onRevoke: (row) => _confirm(
                context,
                title: 'Revoke access?',
                body: 'Immediately end this device\'s active period.',
                cta: 'Revoke',
                onConfirm: () => cubit.revokeSubscription(row.fingerprint),
              ),
              onBlock: (row) => _block(context, cubit, row),
              onRevokeSeat: (row) => _confirm(
                context,
                title: 'Remove seat?',
                body: 'Detach this device from the plan it is riding on.',
                cta: 'Remove seat',
                onConfirm: () => cubit.revokeSeat(
                  ownerFingerprint: row.seatOwner ?? '',
                  seatFingerprint: row.fingerprint,
                ),
              ),
            ),
            AdminTab.plans => _PlansTab(
              rows: state.planConfigs,
              onEdit: (row) => _editPlan(context, cubit, row),
            ),
            AdminTab.promos => _PromosTable(
              rows: state.promos,
              onEdit: (row) => _editPromo(context, row),
              onCreate: () => _createPromo(context, cubit),
              onDelete: (row) => _confirm(
                context,
                title: 'Delete ${row.code}?',
                body:
                    'The code is deactivated; existing redemptions stay in '
                    'the audit trail.',
                cta: 'Delete',
                onConfirm: () => cubit.deletePromo(row.code),
              ),
              onToggle: (row) => cubit.setPromo(
                code: row.code,
                percentOff: row.percentOff,
                active: !row.active,
                expiresAt: row.expiresAt,
                maxUses: row.maxUses,
              ),
            ),
            AdminTab.admins => _AdminsTab(
              rows: state.admins,
              onChangePassword: () => _changePassword(context, cubit),
              onCreate: () => _createAdmin(context, cubit),
              onToggle: (row) => cubit.setAdminActive(row.email, !row.active),
            ),
            AdminTab.redemptions => _RedemptionsTab(rows: state.redemptions),
            AdminTab.audit => _AuditTab(rows: state.audit),
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

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String cta,
    required Future<bool> Function() onConfirm,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: AppText.title),
        content: Text(
          body,
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(cta),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirm();
  }

  Future<void> _grant(
    BuildContext context,
    AdminCubit cubit,
    AdminDeviceRow row,
  ) async {
    final days = TextEditingController(text: '30');
    final note = TextEditingController();
    final plans = cubit.state.planConfigs.where((p) => p.active).toList();
    var planKey = plans.isEmpty ? 'stream_standard' : plans.first.key;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Grant subscription'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (plans.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: planKey,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: [
                    for (final p in plans)
                      DropdownMenuItem(value: p.key, child: Text(p.label)),
                  ],
                  onChanged: (v) => setLocal(() => planKey = v ?? planKey),
                ),
              TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Days'),
              ),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
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
              child: const Text('Grant'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await cubit.grantSubscription(
        row.fingerprint,
        days: int.tryParse(days.text) ?? 30,
        planKey: planKey,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
    }
    days.dispose();
    note.dispose();
  }

  Future<void> _block(
    BuildContext context,
    AdminCubit cubit,
    AdminDeviceRow row,
  ) async {
    final note = TextEditingController(text: row.adminNote ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(row.blocked ? 'Unblock device?' : 'Block device?'),
        content: TextField(
          controller: note,
          decoration: const InputDecoration(labelText: 'Operator note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(row.blocked ? 'Unblock' : 'Block'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await cubit.setDeviceBlocked(
        row.fingerprint,
        blocked: !row.blocked,
        note: note.text.trim().isEmpty ? null : note.text.trim(),
      );
    }
    note.dispose();
  }

  Future<void> _editPlan(
    BuildContext context,
    AdminCubit cubit,
    AdminPlanConfig row,
  ) async {
    final price = TextEditingController(text: '${row.priceCents}');
    final trial = TextEditingController(text: '${row.trialDays}');
    var active = row.active;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(row.label, style: AppText.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Price (USD cents)',
                  helperText: '200 = \$2.00',
                ),
              ),
              TextField(
                controller: trial,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Trial days'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                value: active,
                onChanged: (v) => setLocal(() => active = v),
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
      ),
    );
    if (ok == true) {
      await cubit.updatePlan(
        key: row.key,
        priceCents: int.tryParse(price.text) ?? row.priceCents,
        trialDays: int.tryParse(trial.text),
        active: active,
      );
    }
    price.dispose();
    trial.dispose();
  }

  Future<void> _createPromo(BuildContext context, AdminCubit cubit) async {
    final code = TextEditingController();
    final percent = TextEditingController(text: '20');
    final maxUses = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New promo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Code'),
            ),
            TextField(
              controller: percent,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '% off'),
            ),
            TextField(
              controller: maxUses,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max uses (optional)',
              ),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true && code.text.trim().isNotEmpty) {
      await cubit.setPromo(
        code: code.text.trim().toUpperCase(),
        percentOff: int.tryParse(percent.text) ?? 0,
        active: true,
        maxUses: int.tryParse(maxUses.text),
      );
    }
    code.dispose();
    percent.dispose();
    maxUses.dispose();
  }

  Future<void> _createAdmin(BuildContext context, AdminCubit cubit) async {
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('New admin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password (8+ characters)',
              ),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await cubit.createAdmin(email.text.trim(), password.text);
    }
    email.dispose();
    password.dispose();
  }

  Future<void> _changePassword(BuildContext context, AdminCubit cubit) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Change my password'),
        content: TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (8+ characters)',
          ),
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
    if (ok == true) await cubit.changePassword(password.text);
    password.dispose();
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
          _Kpi(
            label: context.l10n.adminDevices,
            value: '${state.devices.length}',
          ),
          _Kpi(
            label: context.l10n.adminActiveNow,
            value: '${state.activeDevices}',
          ),
          _Kpi(
            label: context.l10n.adminActiveSubs,
            value: '${state.activeSubs}',
          ),
          _Kpi(label: context.l10n.adminMrr, value: mrr),
          _Kpi(label: context.l10n.freeAccess, value: '${state.freeAccess}'),
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
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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
                        color: t == tab
                            ? AppColors.accent
                            : AppColors.textSecondary,
                      ),
                      side: BorderSide(color: AppColors.hairline),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
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
    AdminTab.overview => 'Overview',
    AdminTab.devices => 'Devices',
    AdminTab.plans => 'Plans & Pricing',
    AdminTab.promos => 'Promos',
    AdminTab.admins => 'Admins',
    AdminTab.redemptions => 'Redemptions',
    AdminTab.audit => 'Audit',
  };
}

class _DevicesTable extends StatelessWidget {
  const _DevicesTable({
    required this.rows,
    required this.onRefreshTrial,
    required this.onGrant,
    required this.onRevoke,
    required this.onBlock,
    required this.onRevokeSeat,
  });

  final List<AdminDeviceRow> rows;
  final ValueChanged<AdminDeviceRow> onRefreshTrial;
  final ValueChanged<AdminDeviceRow> onGrant;
  final ValueChanged<AdminDeviceRow> onRevoke;
  final ValueChanged<AdminDeviceRow> onBlock;
  final ValueChanged<AdminDeviceRow> onRevokeSeat;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SingleChildScrollView(
      child: DataTable(
        headingRowColor: WidgetStatePropertyAll(AppColors.surface),
        columns: [
          for (final c in const [
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
            'Sharing',
            'Blocked',
            'Note',
            'Action',
          ])
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
                for (final cell in [
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
                  r.sharingLabel,
                  r.blocked ? 'yes' : 'no',
                  r.adminNote ?? '—',
                ])
                  DataCell(Text(cell, style: AppText.caption)),
                DataCell(
                  PopupMenuButton<String>(
                    tooltip: 'Device actions',
                    onSelected: (value) {
                      switch (value) {
                        case 'refresh':
                          _confirmRefresh(context, r);
                        case 'grant':
                          onGrant(r);
                        case 'revoke':
                          onRevoke(r);
                        case 'block':
                          onBlock(r);
                        case 'seat':
                          onRevokeSeat(r);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Text('Refresh 14 days'),
                      ),
                      const PopupMenuItem(
                        value: 'grant',
                        child: Text('Grant subscription'),
                      ),
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Text('Revoke access'),
                      ),
                      PopupMenuItem(
                        value: 'block',
                        child: Text(
                          r.blocked ? 'Unblock device' : 'Block device',
                        ),
                      ),
                      if (r.seatOwner != null)
                        const PopupMenuItem(
                          value: 'seat',
                          child: Text('Remove seat'),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Icon(
                        Icons.more_horiz,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Future<void> _confirmRefresh(BuildContext context, AdminDeviceRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Refresh trial?', style: AppText.title),
        content: Text(
          'Grant this device a fresh 14-day period?\n\n'
          '${_short(row.fingerprint)} · ${row.platform ?? "unknown device"}',
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Grant 14 days'),
          ),
        ],
      ),
    );
    if (ok == true) onRefreshTrial(row);
  }

  static String _short(String fp) => fp.length <= 12
      ? fp
      : '${fp.substring(0, 6)}…${fp.substring(fp.length - 4)}';
}

class _PromosTable extends StatelessWidget {
  const _PromosTable({
    required this.rows,
    required this.onEdit,
    required this.onToggle,
    required this.onCreate,
    required this.onDelete,
  });

  final List<AdminPromoRow> rows;
  final ValueChanged<AdminPromoRow> onEdit;
  final ValueChanged<AdminPromoRow> onToggle;
  final VoidCallback onCreate;
  final ValueChanged<AdminPromoRow> onDelete;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New promo'),
        ),
      ),
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
              IconButton(
                onPressed: () => onDelete(r),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.textTertiary,
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

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.state, required this.cubit});

  final AdminState state;
  final AdminCubit cubit;

  @override
  Widget build(BuildContext context) {
    final o = state.overview;
    final stats = <(String, String)>[
      ('Devices', '${o.devices}'),
      ('Active 24h', '${o.devicesActive24h}'),
      ('Active subs', '${o.activeSubs}'),
      ('Trialing', '${o.trialing}'),
      ('Expiring 7d', '${o.expiring7d}'),
      ('Blocked', '${o.blocked}'),
      ('MRR', money(o.mrrCents)),
      ('Revenue 30d', money(o.revenue30dCents)),
      ('Promos', '${o.promosActive}'),
      ('Redemptions 30d', '${o.redemptions30d}'),
      ('Admins', '${o.admins}'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, value) in stats)
              _StatChip(label: label, value: value),
          ],
        ),
        const SizedBox(height: 20),
        _Panel(
          title: 'Paywall config',
          subtitle:
              'Pricing and discounts are server-owned. Every app reads these '
              'values before it quotes a price.',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Launch discount: ${state.launchDiscountPct}% · '
                  'Currency: ${state.displayCurrency}',
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                ),
              ),
              FilledButton.tonal(
                onPressed: () => _editConfig(context),
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Panel(
          title: 'Operator security',
          subtitle: 'Rotate the password used by this console.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _changePassword(context),
              icon: const Icon(Icons.password, size: 18),
              label: const Text('Change my password'),
            ),
          ),
        ),
        if (state.error != null) ...[
          const SizedBox(height: 12),
          Text(
            state.error!,
            style: AppText.caption.copyWith(color: AppColors.accent),
          ),
        ],
      ],
    );
  }

  Future<void> _editConfig(BuildContext context) async {
    final discount = TextEditingController(text: '${state.launchDiscountPct}');
    final currency = TextEditingController(text: state.displayCurrency);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Paywall config'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: discount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Launch discount %'),
            ),
            TextField(
              controller: currency,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Display currency'),
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
    if (ok == true) {
      await cubit.updateConfig(
        launchDiscountPct: int.tryParse(discount.text),
        displayCurrency: currency.text.trim().toUpperCase(),
      );
    }
    discount.dispose();
    currency.dispose();
  }

  Future<void> _changePassword(BuildContext context) async {
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Change my password'),
        content: TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (8+ characters)',
          ),
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
    if (ok == true) await cubit.changePassword(password.text);
    password.dispose();
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.hairline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.headline),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: AppText.caption.copyWith(color: AppColors.textTertiary),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: 148,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
  );
}

class _PlansTab extends StatelessWidget {
  const _PlansTab({required this.rows, required this.onEdit});

  final List<AdminPlanConfig> rows;
  final ValueChanged<AdminPlanConfig> onEdit;

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
                    Text(r.label, style: AppText.headline),
                    const SizedBox(height: 2),
                    Text(
                      '${r.key} · ${money(r.priceCents)} · '
                      '${r.trialDays}d trial · ${r.subscribers} subscribers',
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: r.active,
                onChanged: (_) => onEdit(r),
                activeThumbColor: AppColors.accent,
              ),
              IconButton(
                onPressed: () => onEdit(r),
                icon: const Icon(Icons.edit, size: 18),
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
    ],
  );
}

class _AdminsTab extends StatelessWidget {
  const _AdminsTab({
    required this.rows,
    required this.onCreate,
    required this.onToggle,
    required this.onChangePassword,
  });

  final List<AdminAccountRow> rows;
  final VoidCallback onCreate;
  final ValueChanged<AdminAccountRow> onToggle;
  final VoidCallback onChangePassword;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton.icon(
            onPressed: onChangePassword,
            icon: const Icon(Icons.password, size: 18),
            label: const Text('My password'),
          ),
          TextButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('New admin'),
          ),
        ],
      ),
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
                    Text(r.email, style: AppText.headline),
                    const SizedBox(height: 2),
                    Text(
                      '${r.role} · '
                      '${r.lastLoginAt == null ? "never signed in" : "last in ${r.lastLoginAt!.toIso8601String().substring(0, 10)}"}',
                      style: AppText.caption.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
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

class _RedemptionsTab extends StatelessWidget {
  const _RedemptionsTab({required this.rows});

  final List<AdminRedemptionRow> rows;

  @override
  Widget build(BuildContext context) => _Table(
    columns: const [
      'Code',
      'Device',
      'Plan',
      '% off',
      'Before',
      'After',
      'When',
    ],
    rows: [
      for (final r in rows)
        [
          r.code,
          r.fingerprint.length <= 12
              ? r.fingerprint
              : r.fingerprint.substring(0, 12),
          r.planKey ?? '—',
          '${r.percentOff}%',
          money(r.amountBefore),
          money(r.amountAfter),
          r.createdAt?.toIso8601String().substring(0, 16) ?? '—',
        ],
    ],
  );
}

class _AuditTab extends StatelessWidget {
  const _AuditTab({required this.rows});

  final List<AdminAuditRow> rows;

  @override
  Widget build(BuildContext context) => _Table(
    columns: const ['Actor', 'Action', 'Target', 'When', 'Details'],
    rows: [
      for (final r in rows)
        [
          r.actor,
          r.action,
          r.target ?? '—',
          r.createdAt?.toIso8601String().substring(0, 16) ?? '—',
          r.details.isEmpty ? '—' : r.details.toString(),
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
