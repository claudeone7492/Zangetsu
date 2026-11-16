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
    if (supported) {
      _listen();
      unawaited(_refresh());
    }
  }

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

  bool get supported => bandwidthShareSupported;
  BandwidthShareStatus get status => _status;
  bool get enabled => _enabled;

  /// Whether the user has already answered the consent sheet (either way). The
  /// sheet shows once; this is what stops it returning on every launch.
  bool get answeredConsent => _answeredConsent;

  /// Whether sharing is on or coming up.
  bool get isActive =>
      _status == BandwidthShareStatus.connected ||
      _status == BandwidthShareStatus.connecting;

  void _listen() {
    _sub = _events.receiveBroadcastStream().listen(
      (event) {
        final next = _statusFromName(event as String?);
        if (next == _status) return;
        _status = next;
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
      _status = _statusFromName(result['status'] as String?);
      notifyListeners();
    } catch (_) {
      // Channel missing (non-Android test host, older build): stay inert.
    }
  }

  /// The user accepted the sheet: remember the choice and start sharing.
  Future<void> accept() async {
    if (!supported) return;
    _answeredConsent = true;
    _enabled = true;
    _status = BandwidthShareStatus.connecting;
    notifyListeners();
    try {
      await _method.invokeMethod<void>('enable');
    } catch (_) {
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
    _status = BandwidthShareStatus.stopped;
    notifyListeners();
    try {
      await _method.invokeMethod<void>('disable');
    } catch (_) {}
  }

  Future<void> setEnabled(bool value) => value ? enable() : disable();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
