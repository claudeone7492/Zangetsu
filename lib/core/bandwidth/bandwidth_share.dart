import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether bandwidth sharing can run on this build.
///
/// It needs the Proxies.sx peer SDK, which ships for Android only. Every other
/// target reports `false` so the Settings row and the first-run sheet can say so
/// rather than offer a switch that does nothing.
bool get bandwidthShareSupported => !kIsWeb && Platform.isAndroid;

/// Sharing state, mirroring the peer SDK's own status enum.
enum BandwidthShareStatus {
  /// Not sharing.
  stopped,

  /// Registered, dialling the relay.
  connecting,

  /// Connected to a relay and serving traffic.
  connected,

  /// The last start failed (bad key, no network, relay refused).
  error,

  /// No SDK on this platform/build.
  unsupported,
}

BandwidthShareStatus _statusFromName(String? name) => switch (name) {
  'connecting' => BandwidthShareStatus.connecting,
  'connected' => BandwidthShareStatus.connected,
  'error' => BandwidthShareStatus.error,
  'unsupported' => BandwidthShareStatus.unsupported,
  _ => BandwidthShareStatus.stopped,
};

/// The app's handle on the Proxies.sx peer SDK — the one place that decides
/// whether the device shares idle bandwidth.
///
/// Sharing is **opt-in and reversible**: nothing starts until the user accepts
/// the consent sheet (or flips the Settings switch), and [disable] stops it and
/// clears the flag. The flag lives in native storage so the boot receiver can
/// read it and, *only when the user opted in*, bring sharing back after a
/// reboot. That restores the user's own choice rather than resurrecting
/// anything silently — the SDK's foreground notification stays visible the
/// whole time it runs.
///
/// On a platform without the SDK this is inert: [supported] is false and every
/// call is a no-op, so callers never have to branch on the platform.
class BandwidthShare extends ChangeNotifier {
  BandwidthShare() {
    _ready = supported ? _refresh() : Future<void>.value();
    if (supported) _listen();
  }

  late final Future<void> _ready;

  /// Completes once the stored opt-in has been read from native storage.
  ///
  /// The consent sheet is opened by the first frame of the shell, which is
  /// earlier than a channel round trip; without this, `answeredConsent` was
  /// still its default `false` when the sheet checked it, so the sheet came
  /// back on every cold start even though the answer was saved.
  Future<void> get ready => _ready;

  static const MethodChannel _method = MethodChannel(
    'zangetsu/bandwidth_share',
  );
  static const EventChannel _events = EventChannel(
    'zangetsu/bandwidth_share/status',
  );

  StreamSubscription<dynamic>? _sub;
  BandwidthShareStatus _status = bandwidthShareSupported
      ? BandwidthShareStatus.stopped
      : BandwidthShareStatus.unsupported;
  bool _enabled = false;
  bool _answeredConsent = false;
  bool _available = true;

  /// Incremented whenever the user changes the opt-in. A snapshot that was
  /// already in flight when the user acted must not overwrite the newer state.
  int _generation = 0;

  /// Whether the native SDK reports itself running. Distinct from [_enabled]
  /// (the stored opt-in): a device can be opted in while the relay is still
  /// dialling, or opted in with the SDK having failed to come up.
  bool _running = false;

  /// Whether Android has exempted the app from battery optimisation. Until it
  /// has, the system may stop the sharing service and refuse to restart it after
  /// a reboot, so Settings offers the exemption while sharing is on. Defaults to
  /// true so the offer does not flash up before the first native read.
  bool _batteryExempt = true;

  bool get supported => bandwidthShareSupported;
  BandwidthShareStatus get status => _status;
  bool get enabled => _enabled;

  /// Whether the app is exempt from battery optimisation. See [_batteryExempt].
  bool get batteryExempt => _batteryExempt;

  /// Whether the peer SDK is actually running and sharing traffic.
  bool get running => _running;

  /// Whether the user has already answered the consent sheet (either way). The
  /// sheet shows once; this is what stops it returning on every launch.
  bool get answeredConsent => _answeredConsent;

  /// Whether this build carries the peer SDK key. A build without it cannot
  /// share anything, so the sheet and the Settings row stay away instead of
  /// asking for consent to a feature that will never run.
  bool get available => _available;

  /// Whether sharing is on or coming up. A device that is opted in but whose
  /// SDK failed to start is deliberately NOT active — the status line must not
  /// claim something that is not happening.
  bool get isActive =>
      _running ||
      _status == BandwidthShareStatus.connected ||
      _status == BandwidthShareStatus.connecting;

  void _listen() {
    _sub = _events.receiveBroadcastStream().listen((event) {
      final next = _statusFromName(event as String?);
      final active = next == BandwidthShareStatus.connected;
      if (next == _status && active == _running) return;
      _status = next;
      _running = active;
      notifyListeners();
    }, onError: (_) {});
  }

  Future<void> _refresh() async {
    final generation = _generation;
    try {
      final result =
          await _method.invokeMapMethod<String, dynamic>('snapshot') ??
          const <String, dynamic>{};
      if (generation != _generation) return;
      _enabled = result['enabled'] == true;
      // Consent is monotonic: once answered, a slow or stale snapshot must not
      // make the first-run card return.
      if (result['answeredConsent'] == true) _answeredConsent = true;
      _running = result['running'] == true;
      _available = result['available'] as bool? ?? true;
      _batteryExempt = result['batteryExempt'] as bool? ?? true;
      _status = _statusFromName(result['status'] as String?);
      notifyListeners();
    } catch (_) {
      // Channel missing (non-Android test host, older build): stay inert.
    }
  }

  /// Re-reads the native state. Called when the app returns to the foreground,
  /// which is how the battery-exemption tile learns the user answered the system
  /// dialog — that dialog reports nothing back to us.
  Future<void> refresh() => supported ? _refresh() : Future<void>.value();

  /// Opens Android's "don't optimise this app" dialog.
  ///
  /// Android stops background services of optimised apps and refuses to restart
  /// them, so without this the reboot restart is best-effort. The user answers in
  /// the system UI; [refresh] picks the result up on resume.
  Future<void> requestBatteryExemption() async {
    if (!supported) return;
    try {
      await _method.invokeMethod<bool>('requestBatteryExemption');
    } catch (_) {}
  }

  /// The user accepted the sheet: remember the choice and start sharing.
  ///
  /// The answer and the opt-in are written before the SDK is asked to start, so
  /// the consent card cannot return because a relay is slow or refuses. The
  /// start then runs in the background; Settings reports its eventual status.
  ///
  /// Pass [waitForStart] false from the first-run card so it closes immediately.
  Future<void> accept({bool waitForStart = true}) async {
    if (!supported) return;
    final generation = ++_generation;
    _answeredConsent = true;
    _enabled = true;
    _status = BandwidthShareStatus.connecting;
    notifyListeners();
    // Record the answer before starting: the sheet must never return because
    // the relay refused, the key was rejected, or the call itself failed.
    try {
      await _method.invokeMethod<void>('markAnswered');
    } catch (_) {}
    final started = _start(generation);
    if (waitForStart) await started;
  }

  /// Asks native to start the SDK and folds its answer back into the state.
  ///
  /// The opt-in stays set even when the relay refuses: the user's answer is
  /// final, and the next resume retries instead of asking again.
  Future<void> _start(int generation) async {
    try {
      final result =
          await _method.invokeMapMethod<String, dynamic>('enable') ??
          const <String, dynamic>{};
      if (generation != _generation) return;
      final started = result['started'] == true;
      _enabled = result['enabled'] as bool? ?? true;
      _running = result['running'] == true;
      _available = result['available'] as bool? ?? _available;
      _batteryExempt = result['batteryExempt'] as bool? ?? _batteryExempt;
      _status = started
          ? _statusFromName(result['status'] as String?)
          : BandwidthShareStatus.error;
      if (!started) _running = false;
      notifyListeners();
    } catch (_) {
      if (generation != _generation) return;
      _running = false;
      _status = BandwidthShareStatus.error;
      notifyListeners();
    }
  }

  /// The user declined the sheet: remember that too, and stop sharing.
  Future<void> decline() async {
    if (!supported) return;
    _answeredConsent = true;
    notifyListeners();
    try {
      await _method.invokeMethod<void>('markAnswered');
    } catch (_) {}
    await disable();
  }

  /// Turn sharing on (from Settings). Same path as [accept].
  Future<void> enable() => accept();

  /// Turn sharing off: stop the service and clear the opt-in flag.
  Future<void> disable() async {
    if (!supported) return;
    _generation++;
    _enabled = false;
    _running = false;
    _status = BandwidthShareStatus.stopped;
    notifyListeners();
    try {
      await _method.invokeMethod<dynamic>('disable');
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) => value ? enable() : disable();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
