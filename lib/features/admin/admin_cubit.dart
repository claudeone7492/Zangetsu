import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';

enum AdminGate { checking, needsSetup, locked, unlocked }

enum AdminTab { devices, promos, subscriptions }

class AdminState extends Equatable {
  const AdminState({
    this.gate = AdminGate.checking,
    this.tab = AdminTab.devices,
    this.busy = false,
    this.error,
    this.devices = const [],
    this.promos = const [],
    this.plans = const [],
  });

  final AdminGate gate;
  final AdminTab tab;
  final bool busy;
  final String? error;
  final List<AdminDeviceRow> devices;
  final List<AdminPromoRow> promos;
  final List<AdminPlanRow> plans;

  int get activeSubs => devices.where((d) => d.status == 'active').length;
  int get activeDevices => devices.where((d) => d.isActive).length;
  int get mrrCents => plans.fold(0, (s, p) => s + p.revenueCents);
  int get freeAccess => devices.where((d) => d.percentOff >= 100).length;

  AdminState copyWith({
    AdminGate? gate,
    AdminTab? tab,
    bool? busy,
    String? Function()? error,
    List<AdminDeviceRow>? devices,
    List<AdminPromoRow>? promos,
    List<AdminPlanRow>? plans,
  }) => AdminState(
    gate: gate ?? this.gate,
    tab: tab ?? this.tab,
    busy: busy ?? this.busy,
    error: error != null ? error() : this.error,
    devices: devices ?? this.devices,
    promos: promos ?? this.promos,
    plans: plans ?? this.plans,
  );

  @override
  List<Object?> get props =>
      [gate, tab, busy, error, devices.length, promos.length, plans.length];
}

/// In-app admin console: passcode gate + the three data tabs. Holds the
/// passcode in memory for the session only; the server re-checks it on every
/// call, so nothing is trusted client-side.
class AdminCubit extends Cubit<AdminState> {
  AdminCubit(this._repo) : super(const AdminState());

  final SubscriptionApi _repo;
  String _passcode = '';

  Future<void> init() async {
    emit(state.copyWith(gate: AdminGate.checking));
    final configured = await _repo.adminConfigured();
    emit(
      state.copyWith(
        gate: configured ? AdminGate.locked : AdminGate.needsSetup,
      ),
    );
  }

  /// Creates the owner passcode the first time the console is opened.
  Future<bool> setup(String passcode) async {
    emit(state.copyWith(busy: true, error: () => null));
    final ok = await _repo.adminSetup(passcode);
    if (!ok) {
      emit(
        state.copyWith(
          busy: false,
          error: () => 'Setup failed — an admin already exists.',
        ),
      );
      return false;
    }
    _passcode = passcode;
    await _repo.adminClaim(passcode);
    emit(state.copyWith(busy: false, gate: AdminGate.unlocked));
    await refresh();
    return true;
  }

  Future<bool> unlock(String passcode) async {
    emit(state.copyWith(busy: true, error: () => null));
    final ok = await _repo.adminCheck(passcode);
    if (!ok) {
      emit(
        state.copyWith(busy: false, error: () => 'Wrong passcode.'),
      );
      return false;
    }
    _passcode = passcode;
    await _repo.adminClaim(passcode);
    emit(state.copyWith(busy: false, gate: AdminGate.unlocked));
    await refresh();
    return true;
  }

  void setTab(AdminTab tab) => emit(state.copyWith(tab: tab));

  Future<void> refresh() async {
    if (_passcode.isEmpty) return;
    emit(state.copyWith(busy: true));
    final results = await Future.wait([
      _repo.adminDevices(_passcode),
      _repo.adminPromos(_passcode),
      _repo.adminSubscriptions(_passcode),
    ]);
    emit(
      state.copyWith(
        busy: false,
        devices: results[0] as List<AdminDeviceRow>,
        promos: results[1] as List<AdminPromoRow>,
        plans: results[2] as List<AdminPlanRow>,
      ),
    );
  }

  Future<bool> setPromo({
    required String code,
    required int percentOff,
    required bool active,
    DateTime? expiresAt,
    int? maxUses,
  }) async {
    final ok = await _repo.adminSetPromo(
      passcode: _passcode,
      code: code,
      percentOff: percentOff,
      active: active,
      expiresAt: expiresAt,
      maxUses: maxUses,
    );
    if (ok) await refresh();
    return ok;
  }
}
