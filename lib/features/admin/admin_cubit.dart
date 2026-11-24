import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/subscription/subscription_models.dart';
import '../../core/subscription/subscription_repository.dart';

enum AdminGate { checking, needsSetup, locked, unlocked }

enum AdminTab { overview, devices, plans, promos, admins, redemptions, audit }

class AdminState extends Equatable {
  const AdminState({
    this.gate = AdminGate.checking,
    this.tab = AdminTab.overview,
    this.busy = false,
    this.error,
    this.devices = const [],
    this.promos = const [],
    this.plans = const [],
    this.overview = const AdminOverview(),
    this.planConfigs = const [],
    this.admins = const [],
    this.audit = const [],
    this.redemptions = const [],
    this.config = const {},
  });

  final AdminGate gate;
  final AdminTab tab;
  final bool busy;
  final String? error;
  final List<AdminDeviceRow> devices;
  final List<AdminPromoRow> promos;
  final List<AdminPlanRow> plans;
  final AdminOverview overview;
  final List<AdminPlanConfig> planConfigs;
  final List<AdminAccountRow> admins;
  final List<AdminAuditRow> audit;
  final List<AdminRedemptionRow> redemptions;
  final Map<String, dynamic> config;

  int get activeSubs => overview.activeSubs > 0
      ? overview.activeSubs
      : devices.where((d) => d.status == 'active').length;
  int get activeDevices => devices.where((d) => d.isActive).length;
  int get mrrCents => overview.mrrCents > 0
      ? overview.mrrCents
      : plans.fold(0, (s, p) => s + p.revenueCents);
  int get freeAccess => devices.where((d) => d.percentOff >= 100).length;
  int get launchDiscountPct =>
      (config['launch_discount_pct'] as num?)?.toInt() ?? 0;
  String get displayCurrency =>
      (config['display_currency'] as String?) ?? 'USD';

  AdminState copyWith({
    AdminGate? gate,
    AdminTab? tab,
    bool? busy,
    String? Function()? error,
    List<AdminDeviceRow>? devices,
    List<AdminPromoRow>? promos,
    List<AdminPlanRow>? plans,
    AdminOverview? overview,
    List<AdminPlanConfig>? planConfigs,
    List<AdminAccountRow>? admins,
    List<AdminAuditRow>? audit,
    List<AdminRedemptionRow>? redemptions,
    Map<String, dynamic>? config,
  }) => AdminState(
    gate: gate ?? this.gate,
    tab: tab ?? this.tab,
    busy: busy ?? this.busy,
    error: error != null ? error() : this.error,
    devices: devices ?? this.devices,
    promos: promos ?? this.promos,
    plans: plans ?? this.plans,
    overview: overview ?? this.overview,
    planConfigs: planConfigs ?? this.planConfigs,
    admins: admins ?? this.admins,
    audit: audit ?? this.audit,
    redemptions: redemptions ?? this.redemptions,
    config: config ?? this.config,
  );

  @override
  List<Object?> get props => [
    gate,
    tab,
    busy,
    error,
    devices.length,
    promos.length,
    plans.length,
    overview.devices,
    overview.activeSubs,
    overview.mrrCents,
    planConfigs.length,
    admins.length,
    audit.length,
    redemptions.length,
    config['launch_discount_pct'],
    config['display_currency'],
  ];
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

  /// Creates the owner login the first time the console is opened.
  Future<bool> setup(String email, String password) async {
    emit(state.copyWith(busy: true, error: () => null));
    final ok = await _repo.adminRegister(email, password);
    if (!ok) {
      emit(
        state.copyWith(
          busy: false,
          error: () => 'Setup failed — an admin already exists.',
        ),
      );
      return false;
    }
    _passcode = password;
    await _repo.adminClaim(password);
    emit(state.copyWith(busy: false, gate: AdminGate.unlocked));
    await refresh();
    return true;
  }

  Future<bool> unlock(String email, String password) async {
    emit(state.copyWith(busy: true, error: () => null));
    final ok = await _repo.adminLogin(email, password);
    if (!ok) {
      emit(
        state.copyWith(busy: false, error: () => 'Wrong email or password.'),
      );
      return false;
    }
    _passcode = password;
    await _repo.adminClaim(password);
    emit(state.copyWith(busy: false, gate: AdminGate.unlocked));
    await refresh();
    return true;
  }

  void setTab(AdminTab tab) => emit(state.copyWith(tab: tab));

  /// Drop the in-memory passcode and return to the sign-in gate.
  void lock() {
    _passcode = '';
    emit(const AdminState(gate: AdminGate.locked));
  }

  Future<void> refresh() async {
    if (_passcode.isEmpty) return;
    emit(state.copyWith(busy: true, error: () => null));
    final results = await Future.wait<Object?>([
      _repo.adminDevices(_passcode),
      _repo.adminPromos(_passcode),
      _repo.adminSubscriptions(_passcode),
      _repo.adminOverview(_passcode),
      _repo.adminPlans(_passcode),
      _repo.adminAdmins(_passcode),
      _repo.adminAudit(_passcode),
      _repo.adminRedemptions(_passcode),
      _repo.adminConfig(_passcode),
    ]);
    emit(
      state.copyWith(
        busy: false,
        devices: results[0] as List<AdminDeviceRow>,
        promos: results[1] as List<AdminPromoRow>,
        plans: results[2] as List<AdminPlanRow>,
        overview: (results[3] as AdminOverview?) ?? const AdminOverview(),
        planConfigs: results[4] as List<AdminPlanConfig>,
        admins: results[5] as List<AdminAccountRow>,
        audit: results[6] as List<AdminAuditRow>,
        redemptions: results[7] as List<AdminRedemptionRow>,
        config: (results[8] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  Future<bool> setPromo({
    required String code,
    required int percentOff,
    required bool active,
    DateTime? expiresAt,
    int? maxUses,
  }) => _mutate(
    () => _repo.adminSetPromo(
      passcode: _passcode,
      code: code,
      percentOff: percentOff,
      active: active,
      expiresAt: expiresAt,
      maxUses: maxUses,
    ),
    error: 'Could not save this promo.',
  );

  Future<bool> setDeviceBlocked(
    String fingerprint, {
    required bool blocked,
    String? note,
  }) => _mutate(
    () => _repo.adminSetDeviceBlocked(
      passcode: _passcode,
      fingerprint: fingerprint,
      blocked: blocked,
      note: note,
    ),
    error: 'Could not update this device.',
  );

  Future<bool> grantSubscription(
    String fingerprint, {
    int days = 30,
    String planKey = 'stream_standard',
    String? note,
  }) => _mutate(
    () => _repo.adminGrantSubscription(
      passcode: _passcode,
      fingerprint: fingerprint,
      days: days,
      planKey: planKey,
      note: note,
    ),
    error: 'Could not grant this subscription.',
  );

  Future<bool> revokeSubscription(String fingerprint, {String? reason}) =>
      _mutate(
        () => _repo.adminRevokeSubscription(
          passcode: _passcode,
          fingerprint: fingerprint,
          reason: reason,
        ),
        error: 'Could not revoke this subscription.',
      );

  Future<bool> revokeSeat({
    required String ownerFingerprint,
    required String seatFingerprint,
  }) => _mutate(
    () => _repo.adminRevokeSeat(
      passcode: _passcode,
      ownerFingerprint: ownerFingerprint,
      seatFingerprint: seatFingerprint,
    ),
    error: 'Could not remove this seat.',
  );

  Future<bool> updatePlan({
    required String key,
    required int priceCents,
    bool? active,
  }) => _mutate(
    () => _repo.adminUpdatePlan(
      passcode: _passcode,
      key: key,
      priceCents: priceCents,
      active: active,
    ),
    error: 'Could not update this plan.',
  );

  Future<bool> updateConfig({
    int? launchDiscountPct,
    String? displayCurrency,
  }) => _mutate(
    () => _repo.adminUpdateConfig(
      passcode: _passcode,
      launchDiscountPct: launchDiscountPct,
      displayCurrency: displayCurrency,
    ),
    error: 'Could not save the paywall config.',
  );

  Future<bool> deletePromo(String code) => _mutate(
    () => _repo.adminDeletePromo(passcode: _passcode, code: code),
    error: 'Could not delete this promo.',
  );

  Future<bool> createAdmin(String email, String password) => _mutate(
    () => _repo.adminCreateAdmin(
      passcode: _passcode,
      email: email,
      password: password,
    ),
    error: 'Could not create this admin.',
  );

  Future<bool> setAdminActive(String email, bool active) => _mutate(
    () => _repo.adminSetAdminActive(
      passcode: _passcode,
      email: email,
      active: active,
    ),
    error: 'Could not update this admin.',
  );

  Future<bool> changePassword(String newPassword) async {
    emit(state.copyWith(busy: true, error: () => null));
    final ok = await _repo.adminChangePassword(
      passcode: _passcode,
      newPassword: newPassword,
    );
    if (!ok) {
      emit(
        state.copyWith(
          busy: false,
          error: () => 'Could not change the password.',
        ),
      );
      return false;
    }
    _passcode = newPassword;
    await refresh();
    return true;
  }

  Future<bool> _mutate(
    Future<bool> Function() action, {
    required String error,
  }) async {
    emit(state.copyWith(busy: true, error: () => null));
    final ok = await action();
    if (!ok) {
      emit(state.copyWith(busy: false, error: () => error));
      return false;
    }
    await refresh();
    return true;
  }
}
