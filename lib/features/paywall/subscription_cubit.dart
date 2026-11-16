import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';

/// Where the user is in the subscribe flow.
enum PaywallStage { loading, ready, activating, error }

/// Paywall + subscription state.
///
/// Pricing rule: every plan has a LIST price (already set to African
/// purchasing-power levels, in USD). The launch offer takes 15% off the list,
/// then a promo takes its percentage off that. 100% promos are free access and
/// never reach a payment step.
class SubscriptionState extends Equatable {
  const SubscriptionState({
    this.stage = PaywallStage.loading,
    this.plans = const [],
    this.identity,
    this.selectedKey,
    this.promo,
    this.message,
    this.promoRejected = false,
    this.discountPct = 15,
  });

  final PaywallStage stage;
  final List<SubscriptionPlan> plans;
  final DeviceIdentity? identity;
  final String? selectedKey;
  final PromoResult? promo;

  /// Transient user-facing line under the promo field (success or rejection).
  final String? message;
  final bool promoRejected;

  /// Launch-offer percentage off list (from app_config; 15 by default).
  final int discountPct;

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

  bool get isFreeAccess => promo?.isFree == true || totalCents == 0;

    SubscriptionState copyWith({
    PaywallStage? stage,
    List<SubscriptionPlan>? plans,
    DeviceIdentity? identity,
    String? selectedKey,
    PromoResult? Function()? promo,
    String? Function()? message,
    bool? promoRejected,
    int? discountPct,
  }) => SubscriptionState(
    stage: stage ?? this.stage,
    plans: plans ?? this.plans,
    identity: identity ?? this.identity,
    selectedKey: selectedKey ?? this.selectedKey,
    promo: promo != null ? promo() : this.promo,
    message: message != null ? message() : this.message,
    promoRejected: promoRejected ?? this.promoRejected,
    discountPct: discountPct ?? this.discountPct,
  );

  @override
  List<Object?> get props => [
    stage,
    plans.length,
    identity?.sessionId,
    identity?.trialUsed,
    selectedKey,
    promo?.code,
    message,
    promoRejected,
    discountPct,
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
    ]);
    final plans = results[0] as List<SubscriptionPlan>;
    final identity = results[1] as DeviceIdentity?;

    // Default to the most popular tier (middle of the list), else the first.
    final defaultKey = state.selectedKey ??
        (plans.isNotEmpty
            ? plans[plans.length ~/ 2].key
            : null);

    emit(
      state.copyWith(
        stage: plans.isEmpty ? PaywallStage.error : PaywallStage.ready,
        plans: plans,
        identity: identity,
        selectedKey: defaultKey,
        message: () => plans.isEmpty ? 'Could not load plans.' : null,
      ),
    );
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
