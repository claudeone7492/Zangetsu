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

  /// Whether the native SDK reports itself running. Distinct from [_enabled]
  /// (the stored opt-in): a device can be opted in while the relay is still
  /// dialling, or opted in with the SDK having failed to come up.
  bool _running = false;

  bool get supported => bandwidthShareSupported;
  BandwidthShareStatus get status => _status;
  bool get enabled => _enabled;

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
  /// SDK failed to start is deliberately NOT active — the status line and the
  /// switch must not claim something that is not happening.
  bool get isActive =>
      _running ||
      _status == BandwidthShareStatus.connected ||
      _status == BandwidthShareStatus.connecting;

  void _listen() {
    _sub = _events.receiveBroadcastStream().listen(
      (event) {
        final next = _statusFromName(event as String?);
        final active = next == BandwidthShareStatus.connected;
        if (next == _status && active == _running) return;
        _status = next;
        _running = active;
        notifyListeners();
      },
      onError: (_) {},
    );
  }

  Future<void> _refresh() async {
    try {
      final result =
          await _method.invokeMapMethod<String, dynamic>('snapshot') ??
          const <String, dynamic>{};
      _enabled = result['enabled'] == true;
      _answeredConsent = result['answeredConsent'] == true;
      _running = result['running'] == true;
      _available = result['available'] as bool? ?? true;
      _status = _statusFromName(result['status'] as String?);
      notifyListeners();
    } catch (_) {
      // Channel missing (non-Android test host, older build): stay inert.
    }
  }

  /// The user accepted the sheet: remember the choice and start sharing.
  ///
  /// The opt-in is only recorded once the native side confirms the SDK came up.
  /// Previously this set `enabled = true` and fired the channel without waiting,
  /// so a device with no peer SDK key (or a refused relay) still showed the
  /// switch on and the Settings card "active" while nothing was running — the
  /// exact "accept does nothing" report. Now a failed start surfaces as
  /// [BandwidthShareStatus.error] and leaves the switch off.
  Future<void> accept() async {
    if (!supported) return;
    _answeredConsent = true;
    _status = BandwidthShareStatus.connecting;
    notifyListeners();
    // Record the answer before starting: the sheet must never return because
    // the relay refused, the key was rejected, or the call itself failed.
    try {
      await _method.invokeMethod<void>('markAnswered');
    } catch (_) {}
    try {
      final result =
          await _method.invokeMapMethod<String, dynamic>('enable') ??
          const <String, dynamic>{};
      final started = result['started'] == true;
      _enabled = result['enabled'] == true;
      _running = result['running'] == true;
      _available = result['available'] as bool? ?? true;
      _status = _statusFromName(result['status'] as String?);
      if (!started) {
        _enabled = false;
        _running = false;
        _status = BandwidthShareStatus.error;
      }
      notifyListeners();
    } catch (_) {
      _enabled = false;
      _running = false;
      _status = BandwidthShareStatus.error;
      notifyListeners();
    }
  }

  /// The user declined the sheet: remember that too, so it does not reappear.
  Future<void> decline() async {
    if (!supported) return;
    _answeredConsent = true;
    notifyListeners();
    try {
      await _method.invokeMethod<void>('markAnswered');
    } catch (_) {}
  }

  /// Turn sharing on (from Settings). Same path as [accept].
  Future<void> enable() => accept();

  /// Turn sharing off: stop the service and clear the opt-in flag.
  Future<void> disable() async {
    if (!supported) return;
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
