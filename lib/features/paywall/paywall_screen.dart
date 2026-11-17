import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/subscription/geo_pricing.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'korapay_checkout.dart';
import 'subscription_cubit.dart';

/// Opens the subscription card as a frosted modal. Resolves true when the user
/// unlocked access (trial started, free promo, or a completed payment).
///
/// [dismissible] false makes the card modal: used by the launch gate, which
/// must not be swiped away before the device is entitled. The in-app entry
/// points leave it true so a browsing user can back out.
Future<bool> showPaywall(
  BuildContext context, {
  String? reason,
  VoidCallback? onUnlocked,
  bool dismissible = true,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) {
      final sheet = BlocProvider(
        create: (_) => SubscriptionCubit(sl())..load(),
        child: PaywallSheet(reason: reason, onUnlocked: onUnlocked),
      );
      if (dismissible) return sheet;
      return PopScope(canPop: false, child: sheet);
    },
  );
  final unlocked = result ?? false;
  if (unlocked) onUnlocked?.call();
  return unlocked;
}

/// The subscription card: the premium tier, promo input, live total, trial CTA.
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key, this.reason, this.onUnlocked});

  final String? reason;

  /// Called once the user unlocks access (trial, free promo or paid), in
  /// addition to the modal resolving true. Lets a host that cannot await the
  /// result — the launch gate — react to the unlock.
  final VoidCallback? onUnlocked;

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  final _promo = TextEditingController();

  @override
  void dispose() {
    _promo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF20212A).withValues(alpha: 0.72),
                const Color(0xFF16161C).withValues(alpha: 0.80),
              ],
            ),
            border: Border(top: BorderSide(color: AppColors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: BlocConsumer<SubscriptionCubit, SubscriptionState>(
              listener: (context, state) {
                if (state.message != null && !state.promoRejected) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        backgroundColor: AppColors.surface2,
                        behavior: SnackBarBehavior.floating,
                        content: Text(
                          state.message!,
                          style: AppText.body.copyWith(color: Colors.white),
                        ),
                      ),
                    );
                }
              },
              builder: (context, state) {
                if (state.stage == PaywallStage.loading) {
                  return const SizedBox(
                    height: 260,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  );
                }
                return _body(context, state);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, SubscriptionState state) {
    final cubit = context.read<SubscriptionCubit>();
    final busy = state.stage == PaywallStage.activating;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _hero(state),
            const SizedBox(height: 20),
            _benefits(),
            const SizedBox(height: 20),
            for (final plan in state.plans) ...[
              _PlanCard(
                plan: plan,
                selected: plan.key == state.selectedKey,
                discountPct: state.discountPct,
                geoQuote: state.geoQuote,
                onTap: () => cubit.selectPlan(plan.key),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            _promoField(context, state, cubit),
            const SizedBox(height: 16),
            _summary(state),
            const SizedBox(height: 16),
            _cta(context, state, cubit, busy: busy),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Pay with KoraPay · card, transfer, USSD',
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Secured in-app · no redirect',
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The headline: a warm, benefit-led pitch rather than a state name. The
  /// reason line comes from whoever triggered the gate, so a viewer who tapped
  /// a locked title reads why they landed here.
  Widget _hero(SubscriptionState state) {
    final identity = state.identity;
    final trialLeft = state.trialEligible;
    final days = state.selected?.trialDays ?? 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.discountPct > 0) ...[
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Launch offer · ${state.discountPct}% off',
                  style: AppText.caption.copyWith(color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Text(
          widget.reason ?? 'Unlock everything on Zangetsu',
          style: AppText.title,
        ),
        const SizedBox(height: 8),
        Text(
          trialLeft
              ? 'Start your $days-day free trial and watch every drama, short '
                    'and live match — no card needed to begin.'
              : 'Keep watching every drama, short and live match, on any device.',
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        if (identity != null && identity.daysLeft > 0 && !identity.entitled) ...[
          const SizedBox(height: 8),
          Text(
            'Your access ended ${identity.daysLeft} day'
            '${identity.daysLeft == 1 ? '' : 's'} ago.',
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }

  /// Three plain-language benefits, so the card sells the outcome rather than
  /// listing tiers with no context.
  Widget _benefits() {
    const items = <(IconData, String, String)>[
      (
        Icons.play_circle_outline,
        'Every drama, unlocked',
        'Full seasons and the drama shorts feed',
      ),
      (
        Icons.bolt_outlined,
        'Live matches as they happen',
        'Soccer streams resolved the moment you tap',
      ),
      (
        Icons.devices_outlined,
        'Any device, offline too',
        'Phone, TV and tablet — download and watch',
      ),
    ];
    return Column(
      children: [
        for (final (icon, title, sub) in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 19, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppText.body),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _promoField(
    BuildContext context,
    SubscriptionState state,
    SubscriptionCubit cubit,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promo,
                textInputAction: TextInputAction.done,
                onSubmitted: cubit.applyPromo,
                style: AppText.body.copyWith(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Have a promo code?',
                  hintStyle: AppText.body.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: AppColors.bg.withValues(alpha: 0.5),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.hairline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.accent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: () => cubit.applyPromo(_promo.text),
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: Text('Apply', style: AppText.button),
              ),
            ),
          ],
        ),
        if (state.message != null && state.promoRejected) ...[
          const SizedBox(height: 8),
          Text(
            state.message!,
            style: AppText.caption.copyWith(color: AppColors.accent),
          ),
        ],
      ],
    );
  }

  Widget _summary(SubscriptionState state) {
    final plan = state.selected;
    final hasOffer = state.discountPct > 0;
    final rows = <Widget>[
      _SummaryRow(
        label: 'Plan',
        value: '${plan?.label ?? kPremiumPlanLabel} · '
            '${periodWord(plan?.periodDays ?? 30)}',
      ),
      _SummaryRow(label: 'Price', value: money(state.listCents)),
    ];
    if (hasOffer) {
      rows.add(
        _SummaryRow(
          label: 'Launch offer · ${state.discountPct}% off',
          value: '−${money(state.listCents - state.offerCents)}',
          accent: true,
        ),
      );
    }
    if (state.promo != null) {
      rows.add(
        _SummaryRow(
          label: state.promo!.isFree
              ? 'Free access'
              : 'Promo · ${state.promo!.percentOff}% off',
          value:
              '−${money(state.offerCents - state.totalCents)}',
          accent: true,
        ),
      );
    }
    rows.add(
      _SummaryRow(
        label: 'Total',
        value: money(state.totalCents),
        total: true,
      ),
    );

    final saved = state.listCents - state.totalCents;
    if (saved > 0) {
      rows.add(
        _SummaryRow(
          label: 'You save',
          value: money(saved),
          accent: true,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(children: rows),
    );
  }

  Widget _cta(
    BuildContext context,
    SubscriptionState state,
    SubscriptionCubit cubit, {
    required bool busy,
  }) {
    final label = state.isFreeAccess
        ? 'Activate free access'
        : state.trialEligible
        ? 'Activate free trial'
        : 'Continue to payment · ${money(state.totalCents)}'
              '${periodSuffix(state.selected?.periodDays ?? 30)}';

    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: busy
            ? null
            : () async {
                if (state.trialEligible && !state.isFreeAccess) {
                  final ok = await cubit.startTrial();
                  if (ok && context.mounted) Navigator.of(context).pop(true);
                  return;
                }
                await _pay(context, cubit);
              },
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.black,
                ),
              )
            : Text(label, style: AppText.button.copyWith(color: Colors.black)),
      ),
    );
  }

  /// Runs the paid path: start the checkout server-side, then either finish
  /// (a free promo already granted access) or open the Korapay WebView and
  /// re-check entitlement on the way back.
  Future<void> _pay(BuildContext context, SubscriptionCubit cubit) async {
    final result = await cubit.beginCheckout();
    if (!context.mounted || result == null || !result.ok) return;

    if (result.free) {
      Navigator.of(context).pop(true);
      return;
    }

    final url = result.checkoutUrl;
    if (url == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Checkout is unavailable right now.'),
          ),
        );
      return;
    }

    final paid = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KoraPayCheckout(checkoutUrl: url),
        fullscreenDialog: true,
      ),
    );
    if (!context.mounted) return;

    // The WebView returning only means the user came back. Entitlement is
    // re-read from the server, which the webhook settles independently.
    if (paid == true && await cubit.refreshEntitlement()) {
      if (context.mounted) Navigator.of(context).pop(true);
    }
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.discountPct,
    required this.onTap,
    this.geoQuote,
  });

  final SubscriptionPlan plan;
  final bool selected;
  final int discountPct;
  final GeoQuote? geoQuote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final offer = (plan.priceCents * (100 - discountPct) / 100).round();
    final onOffer = offer < plan.priceCents;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : AppColors.surface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _Radio(selected: selected),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.label, style: AppText.headline),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      for (final f in plan.features)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              f,
                              style: AppText.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                RichText(
                  text: TextSpan(
                    text: money(offer),
                    style: AppText.headline.copyWith(color: Colors.white),
                    children: [
                      TextSpan(
                        text: periodSuffix(plan.periodDays),
                        style: AppText.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onOffer)
                  Text(
                    money(plan.priceCents),
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                if (geoQuote != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '≈ ${geoQuote!.format(offer / 100)}',
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: selected ? AppColors.accent : AppColors.textTertiary,
        width: 2,
      ),
    ),
    child: selected
        ? Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent,
              ),
            ),
          )
        : null,
  );
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.accent = false,
    this.total = false,
  });

  final String label;
  final String value;
  final bool accent;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final style = total
        ? AppText.headline
        : AppText.body.copyWith(
            color: accent ? AppColors.accent : AppColors.textSecondary,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(
            value,
            style: total
                ? AppText.headline
                : style.copyWith(color: accent ? AppColors.accent : Colors.white),
          ),
        ],
      ),
    );
  }
}
