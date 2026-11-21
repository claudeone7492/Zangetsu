import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The `zangetsu/parity` channel.
///
/// Two seams that need Android: a frame grab that keeps the subtitle overlay
/// (mpv's own screenshot only has the picture), and the foreground service
/// that keeps a long in-process job alive while the app is backgrounded.
class ParityNative {
  const ParityNative._();

  static const MethodChannel _channel = MethodChannel('zangetsu/parity');

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static int _workDepth = 0;
  static String _workLabel = '';

  /// Copies the window — video frame plus whatever Flutter draws over it —
  /// into Pictures/Zangetsu. Returns the saved path, or null when the platform
  /// cannot do it (the caller falls back to the raw-frame screenshot).
  static Future<String?> captureWindow({String? name}) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('captureWindow', {
        'name': name,
      });
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Keeps the process alive while a long job runs. Reference counted: the
  /// service stops when the last caller finishes, not on the first.
  static Future<void> beginWork(String label) async {
    if (!isSupported) return;
    _workDepth++;
    _workLabel = label;
    if (_workDepth > 1) return;
    try {
      await _channel.invokeMethod<void>('startWork', {'label': label});
    } on PlatformException {
      _workDepth = 0;
    } on MissingPluginException {
      _workDepth = 0;
    }
  }

  static Future<void> endWork() async {
    if (!isSupported || _workDepth == 0) return;
    _workDepth--;
    if (_workDepth > 0) return;
    _workLabel = '';
    try {
      await _channel.invokeMethod<void>('stopWork');
    } on PlatformException {
      // The service may already be gone; nothing to recover.
    } on MissingPluginException {
      // A build without the channel.
    }
  }

  /// Label of the job currently holding the service, for diagnostics.
  static String get workLabel => _workLabel;

  /// Voices the platform engine can speak with no network — the offline
  /// narration path. Nothing is bundled, so this is whatever the user has
  /// downloaded in system settings; empty means only hosted voices can speak.
  static Future<List<String>> voicePacks() async {
    if (!isSupported) return const [];
    try {
      final ids = await _channel.invokeMethod<List<Object?>>('voicePacks');
      return ids?.whereType<String>().toList() ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Opens the system screen where offline voice packs are downloaded.
  static Future<void> openTtsSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('ttsSettings');
    } on PlatformException {
      // Nothing to open on this build.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Whether TDLib is linked into this build. It is not today; the seam asks
  /// the runtime rather than asserting, so a build that links it starts
  /// reporting true with no Dart change.
  static Future<bool> tdlibAvailable() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('tdlib') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
