import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/di/injector.dart';
import '../../core/subscription/geo_pricing.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import 'join_plan_dialog.dart';
import 'korapay_checkout.dart';
import 'subscription_cubit.dart';
import '../../l10n/l10n.dart';

/// Opens the subscription card as a frosted modal. Resolves true when the user
/// unlocked access (trial started, free promo, or a completed payment).
///
/// The card is modal by default: it cannot be swiped away, tapped away, or
/// popped with Back. A caller that is only showing the plans (not gating
/// content) can opt into dismissal explicitly.
Future<bool> showPaywall(
  BuildContext context, {
  String? reason,
  VoidCallback? onUnlocked,
  bool dismissible = false,
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
        child: PaywallSheet(
          reason: reason,
          onUnlocked: onUnlocked,
          canClose: dismissible,
        ),
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
  const PaywallSheet({
    super.key,
    this.reason,
    this.onUnlocked,
    this.canClose = false,
  });

  final String? reason;

  /// Shows the close control. Off by default so the card cannot be dismissed
  /// before the device is entitled.
  final bool canClose;

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
            // Glass: a light sheen at the top fading into a mostly-transparent
            // body, with a bright top hairline. The blurred artwork behind the
            // modal must read through the card, so the fill stays well under
            // half-opaque instead of covering it with a solid panel.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                AppColors.surface.withValues(alpha: 0.34),
                AppColors.bg.withValues(alpha: 0.42),
              ],
              stops: const [0.0, 0.28, 1.0],
            ),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
            ),
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
            SizedBox(
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.hairline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (widget.canClose)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: IconButton(
                        key: const ValueKey('paywall-close'),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _hero(state),
            const SizedBox(height: 20),
            _benefits(),
            const SizedBox(height: 20),
            for (final plan in state.plans) ...[
              _PlanCard(
                plan: plan,
                selected: plan.key == state.selectedKey,
                payableCents: state.payableCents,
                geoQuote: state.geoQuote,
                onTap: () => cubit.selectPlan(plan.key),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            _promoField(context, state, cubit),
            _joinPlanLink(context, cubit),
            const SizedBox(height: 16),
            _summary(state),
            const SizedBox(height: 16),
            _cta(context, state, cubit, busy: busy),
            const SizedBox(height: 12),
            Center(
              child: Text(
                context.l10n.paywallPayWithKorapay,
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                context.l10n.paywallSecuredInApp,
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
        if (identity != null &&
            identity.daysLeft > 0 &&
            !identity.entitled) ...[
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
                  hintText: context.l10n.paywallPromoHint,
                  hintStyle: AppText.body.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
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
                child: Text(context.l10n.apply, style: AppText.button),
              ),
            ),
          ],
        ),
        if (state.message != null && state.promoRejected) ...[
          const SizedBox(height: 8),
          _promoNoticePill(state.message!),
        ],
      ],
    );
  }

  Widget _promoNoticePill(String message) {
    final expired = message.toLowerCase().contains('expired');
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('promo-notice-pill'),
        padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.18),
              AppColors.surface.withValues(alpha: 0.55),
            ],
          ),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.18),
              ),
              child: Icon(
                expired ? Icons.timer_off_rounded : Icons.error_outline_rounded,
                size: 14,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The guest's way in: a second device joins the plan it is already paying
  /// for instead of buying its own.
  Widget _joinPlanLink(BuildContext context, SubscriptionCubit cubit) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: () => _joinWithCode(context, cubit),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          "On someone's plan? Enter their code",
          style: AppText.caption.copyWith(
            color: AppColors.textSecondary,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }

  Future<void> _joinWithCode(
    BuildContext context,
    SubscriptionCubit cubit,
  ) async {
    final code = await showJoinPlanDialog(context);
    if (code == null || !context.mounted) return;

    final result = await cubit.linkDevice(code);
    if (!context.mounted) return;
    if (result == null) {
      _snack(context, 'Could not reach the server. Try again.');
      return;
    }
    if (!result.ok) {
      _snack(context, result.message);
      return;
    }
    if (await cubit.refreshEntitlement() && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
            style: AppText.body.copyWith(color: Colors.white),
          ),
        ),
      );
  }

  Widget _summary(SubscriptionState state) {
    final plan = state.selected;
    final hasOffer = state.discountPct > 0;
    final rows = <Widget>[
      _SummaryRow(
        label: context.l10n.paywallPlan,
        value:
            '${plan?.label ?? kPremiumPlanLabel} · '
            '${periodWord(plan?.periodDays ?? 30)}',
      ),
      _SummaryRow(
        label: context.l10n.paywallPrice,
        value: money(state.listCents),
      ),
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
              ? context.l10n.freeAccess
              : 'Promo · ${state.promo!.percentOff}% off',
          value: '−${money(state.offerCents - state.totalCents)}',
          accent: true,
        ),
      );
    }
    rows.add(
      _SummaryRow(
        label: context.l10n.paywallTotal,
        value: money(state.totalCents),
        total: true,
      ),
    );

    final saved = state.listCents - state.totalCents;
    if (saved > 0) {
      rows.add(
        _SummaryRow(
          label: context.l10n.paywallYouSave,
          value: money(saved),
          accent: true,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
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
        ? 'Start ${state.selected?.trialDays ?? 14} days free trial'
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
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(context.l10n.paywallCheckoutUnavailable),
          ),
        );
      return;
    }

    final returned = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => KoraPayCheckout(checkoutUrl: url),
        fullscreenDialog: true,
      ),
    );
    if (!context.mounted) return;

    // The WebView returning only means the user came back. Entitlement is
    // re-read from the server, which the webhook settles independently. Poll
    // briefly after a redirect or a manual close, because the webhook can
    // arrive just after the browser lands on the success URL.
    var unlocked = await cubit.refreshEntitlement();
    final attempts = switch (returned) {
      true => 5,
      null => 3,
      _ => 0,
    };
    for (var attempt = 0; attempt < attempts && !unlocked; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!context.mounted) return;
      unlocked = await cubit.refreshEntitlement();
    }
    if (unlocked && context.mounted) Navigator.of(context).pop(true);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.payableCents,
    required this.geoQuote,
    required this.onTap,
  });

  final SubscriptionPlan plan;
  final bool selected;

  /// Live promo-adjusted amount, the same figure the summary and CTA quote.
  final int payableCents;
  final GeoQuote? geoQuote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onOffer = payableCents < plan.priceCents;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : Colors.white.withValues(alpha: 0.12),
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
                    text: money(payableCents),
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
                    '≈ ${geoQuote!.format(payableCents / 100)}',
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
                : style.copyWith(
                    color: accent ? AppColors.accent : Colors.white,
                  ),
          ),
        ],
      ),
    );
  }
}
