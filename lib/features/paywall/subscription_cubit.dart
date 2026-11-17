import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/subscription/geo_pricing.dart';
import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';

/// Where the user is in the subscribe flow.
enum PaywallStage { loading, ready, activating, error }

/// Paywall + subscription state.
///
/// There is one product: a premium subscription at the standard price. Every
/// plan carries a LIST price (already set to African purchasing-power levels,
/// in USD); the card quotes that price, and a promo takes its percentage off
/// it. 100% promos are free access and never reach a payment step.
///
/// [discountPct] stays a field so an admin-set launch discount could be fed in
/// later, but the client no longer invents one: the price shown is the price
/// charged, so the card can never quote less than the server captures.
class SubscriptionState extends Equatable {
  const SubscriptionState({
    this.stage = PaywallStage.loading,
    this.plans = const [],
    this.identity,
    this.selectedKey,
    this.promo,
    this.message,
    this.promoRejected = false,
    this.discountPct = 0,
    this.geoQuote,
  });

  final PaywallStage stage;
  final List<SubscriptionPlan> plans;
  final DeviceIdentity? identity;
  final String? selectedKey;
  final PromoResult? promo;

  /// Transient user-facing line under the promo field (success or rejection).
  final String? message;
  final bool promoRejected;

  /// Launch-offer percentage off list, read from `subscription_config`.
  /// Defaults to 0: the card quotes the list price unless an admin discount is
  /// explicitly applied, and a config fetch that failed never over-promises.
  final int discountPct;

  /// Approximate local-currency price, when the device is on African rails.
  final GeoQuote? geoQuote;

  SubscriptionPlan? get selected {
    final key = selectedKey;
    if (key == null) return null;
    for (final p in plans) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// First-time device: eligible for the free-trial button.
  bool get trialEligible =>
      identity != null && !identity!.trialUsed && !identity!.isActive;

  /// List price in cents.
  int get listCents => selected?.priceCents ?? 0;

  /// Launch-offer price (list minus [discountPct]).
  int get offerCents =>
      (listCents * (100 - discountPct) / 100).round();

  /// Price after the promo, floored at 0.
  int get totalCents {
    final off = promo?.percentOff ?? 0;
    if (promo?.isFree == true) return 0;
    return (offerCents * (100 - off) / 100).round();
  }

  /// What the user actually pays: the promo-adjusted [totalCents].
  ///
  /// This is the single figure the plan card, the summary and the CTA all
  /// quote, so a promo can never show one price on the card and charge another
  /// at checkout. The server re-derives it from the promo row and is the
  /// authority; this only mirrors it for display.
  int get payableCents => totalCents;

  bool get isFreeAccess => promo?.isFree == true || totalCents == 0;

  /// Approximate price in the device's local currency, shown under the offer
  /// price. Null when the device is not on African rails or no rate is known.
  String? get geoApprox => geoQuote?.format(payableCents / 100);

    SubscriptionState copyWith({
    PaywallStage? stage,
    List<SubscriptionPlan>? plans,
    DeviceIdentity? identity,
    String? selectedKey,
    PromoResult? Function()? promo,
    String? Function()? message,
    bool? promoRejected,
    int? discountPct,
    GeoQuote? geoQuote,
  }) => SubscriptionState(
    stage: stage ?? this.stage,
    plans: plans ?? this.plans,
    identity: identity ?? this.identity,
    selectedKey: selectedKey ?? this.selectedKey,
    promo: promo != null ? promo() : this.promo,
    message: message != null ? message() : this.message,
    promoRejected: promoRejected ?? this.promoRejected,
    discountPct: discountPct ?? this.discountPct,
    geoQuote: geoQuote ?? this.geoQuote,
  );

  @override
  List<Object?> get props => [
    stage,
    plans.length,
    identity?.sessionId,
    identity?.trialUsed,
    // Entitlement fields matter: a payment settles without changing the
    // session id, and without these the state compares equal and the rebuild
    // is dropped, leaving the paywall up after a successful charge.
    identity?.entitled,
    identity?.showPaywall,
    identity?.status,
    identity?.daysLeft,
    selectedKey,
    promo?.code,
    message,
    promoRejected,
    discountPct,
    geoQuote?.currency,
    geoQuote?.rate,
  ];
}

/// Drives the paywall: loads plans + identity, computes the live total, and
/// performs trial activation / promo redemption.
class SubscriptionCubit extends Cubit<SubscriptionState> {
  SubscriptionCubit(this._repo) : super(const SubscriptionState());

  final SubscriptionApi _repo;

  /// Loads plans and this device's identity. Safe to call repeatedly.
  Future<void> load() async {
    emit(state.copyWith(stage: PaywallStage.loading));
    final results = await Future.wait([
      _repo.plans(),
      _repo.identify(),
      GeoPricing.quote(),
      _repo.config(),
    ]);
    final plans = results[0] as List<SubscriptionPlan>;
    final identity = results[1] as DeviceIdentity?;
    final geoQuote = results[2] as GeoQuote?;
    final config = results[3] as SubscriptionConfig;

    // One product: the premium subscription at the standard price. The backend
    // still carries a tiered catalogue, so collapse it to a single card rather
    // than offer a basic/standard/premium choice.
    final single = _singlePremiumPlan(plans);

    emit(
      state.copyWith(
        stage: single == null ? PaywallStage.error : PaywallStage.ready,
        plans: single == null ? const [] : [single],
        identity: identity,
        selectedKey: single?.key,
        geoQuote: geoQuote,
        discountPct: config.launchDiscountPct,
        message: () => single == null ? 'Could not load plans.' : null,
      ),
    );
  }

  /// Collapses the catalogue to the one plan the paywall sells: the standard
  /// tier at its standard price, shown as "Premium subscription". Falls back to
  /// the premium tier, then the first plan, so a catalogue that renames its keys
  /// still yields a single card.
  static SubscriptionPlan? _singlePremiumPlan(List<SubscriptionPlan> plans) {
    if (plans.isEmpty) return null;
    SubscriptionPlan pick = plans.first;
    for (final key in const ['stream_standard', 'stream_premium']) {
      final match = plans.where((p) => p.key == key);
      if (match.isNotEmpty) {
        pick = match.first;
        break;
      }
    }
    return pick.label == kPremiumPlanLabel
        ? pick
        : pick.copyWith(label: kPremiumPlanLabel);
  }

  void selectPlan(String key) {
    emit(state.copyWith(selectedKey: key, message: () => null));
  }

  /// Resolves a typed promo. Empty clears it. Unknown codes are rejected with
  /// a message — the catalogue is never revealed.
  Future<void> applyPromo(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      emit(
        state.copyWith(
          promo: () => null,
          message: () => null,
          promoRejected: false,
        ),
      );
      return;
    }

    final result = await _repo.resolvePromo(trimmed, planKey: state.selectedKey);
    if (result == null) {
      emit(
        state.copyWith(
          promo: () => null,
          message: () => 'That code is not valid or has expired.',
          promoRejected: true,
        ),
      );
      return;
    }

    final off = result.isFree ? 100 : result.percentOff;
    emit(
      state.copyWith(
        promo: () => result,
        message: () => '🎉 ${result.code} — $off% off applied.',
        promoRejected: false,
      ),
    );
  }

  void clearPromo() => emit(
    state.copyWith(promo: () => null, message: () => null, promoRejected: false),
  );

  /// Activates the free trial for a first-time device. Returns true on success.
  Future<bool> startTrial() async {
    final plan = state.selected;
    if (plan == null || !plan.hasTrial) return false;
    emit(state.copyWith(stage: PaywallStage.activating));
    final id = await _repo.startTrial(plan.key);
    if (id == null) {
      emit(
        state.copyWith(
          stage: PaywallStage.ready,
          message: () => 'This device has already used its free trial.',
          promoRejected: true,
        ),
      );
      return false;
    }
    final identity = await _repo.identify();
    emit(
      state.copyWith(
        stage: PaywallStage.ready,
        identity: identity,
        message: () => 'Trial active — ${plan.trialDays} days free.',
      ),
    );
    return true;
  }

  /// Starts a paid checkout for the selected plan.
  ///
  /// Returns the result so the caller can open the Korapay checkout. When the
  /// promo covers the whole price the server grants access immediately and
  /// [CheckoutResult.free] is true, with no checkout URL to open.
  Future<CheckoutResult?> beginCheckout() async {
    final plan = state.selected;
    if (plan == null) return null;
    emit(state.copyWith(stage: PaywallStage.activating, message: () => null));
    final result = await _repo.startCheckout(
      planKey: plan.key,
      promoCode: state.promo?.code,
    );
    if (!result.ok) {
      emit(
        state.copyWith(
          stage: PaywallStage.ready,
          message: () => 'Could not start checkout. Please try again.',
          promoRejected: true,
        ),
      );
      return result;
    }
    emit(state.copyWith(stage: PaywallStage.ready));
    return result;
  }

  /// Re-reads this device's entitlement after a payment, so the unlock reflects
  /// the server's verdict rather than the WebView's return.
  Future<bool> refreshEntitlement() async {
    final identity = await _repo.identify();
    emit(state.copyWith(identity: identity));
    return identity?.entitled ?? false;
  }

  /// Redeems the current promo (if any) against this device. Best-effort: a
  /// failure never blocks the unlock the caller already decided on.
  Future<void> commitPromo() async {
    final promo = state.promo;
    final plan = state.selected;
    if (promo == null || plan == null) return;
    await _repo.redeemPromo(
      code: promo.code,
      planKey: plan.key,
      beforeCents: state.listCents,
      afterCents: state.totalCents,
    );
  }
}
