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
Future<bool> showPaywall(BuildContext context, {String? reason}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => BlocProvider(
      create: (_) => SubscriptionCubit(sl())..load(),
      child: PaywallSheet(reason: reason),
    ),
  );
  return result ?? false;
}

/// The subscription card: tier list, promo input, live total, trial CTA.
class PaywallSheet extends StatefulWidget {
  const PaywallSheet({super.key, this.reason});

  final String? reason;

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
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
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
            const SizedBox(height: 14),
            Text(
              widget.reason ?? 'Choose your plan. Stream without limits.',
              style: AppText.title,
            ),
            const SizedBox(height: 6),
            Text(
              'Cancel anytime. First 14 days free on Standard & Premium.',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 18),
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
    final rows = <Widget>[
      _SummaryRow(
        label: 'Plan',
        value: '${state.selected?.label ?? '—'} · monthly',
      ),
      _SummaryRow(
        label: 'List price',
        value: money(state.listCents),
      ),
      _SummaryRow(
        label: 'Launch offer · ${state.discountPct}% off',
        value: '−${money(state.listCents - state.offerCents)}',
        accent: true,
      ),
    ];
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
        label: 'Total / month',
        value: money(state.totalCents),
        total: true,
      ),
    );

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
        : 'Continue to payment · ${money(state.totalCents)}/mo';

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
                        text: '/mo',
                        style: AppText.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
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
