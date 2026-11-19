import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A voice the device's speech engine can use.
class DubVoice {
  const DubVoice({
    required this.name,
    required this.locale,
    this.isNetwork = false,
  });

  final String name;

  /// BCP-47 tag, e.g. `en-GB`.
  final String locale;

  /// Network voices sound better but need data and add latency; shown so the
  /// picker can say so.
  final bool isNetwork;

  String get label => '$name ($locale)';
}

/// The narration engine behind AI Dub.
///
/// An interface, not a concrete class, for two reasons: the platform channel
/// cannot run in a widget test, and D2's neural voices are a *different*
/// engine with the same contract. Everything above this line is pure Dart and
/// testable; only this boundary touches the platform.
abstract class DubEngine {
  /// Whether the device has a speech engine at all.
  Future<bool> isAvailable();

  /// Voices installed on the device, best first.
  Future<List<DubVoice>> voices();

  /// Speak [text], replacing anything already speaking.
  ///
  /// Returns a future that completes when speech finishes (or is interrupted),
  /// so a caller can chain cues if it ever needs to.
  Future<void> speak(
    String text, {
    String? voice,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  });

  /// Stop immediately. Safe to call when nothing is speaking.
  Future<void> stop();

  void dispose();
}

/// The system TTS engine, driven over a platform channel.
///
/// The channel is owned by this app (see `MainActivity`/`AppDelegate`), not by
/// a third-party plugin: `flutter_tts` would add a dependency for four calls,
/// and the app already ships native code for the engines it hosts.
///
/// Every method degrades to a no-op when the channel is missing, so the app
/// still runs on a platform that has not implemented it yet (desktop, tests).
class PlatformDubEngine implements DubEngine {
  PlatformDubEngine({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('zangetsu/dub_tts');

  final MethodChannel _channel;
  bool _unavailable = false;

  @override
  Future<bool> isAvailable() async {
    if (_unavailable) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      _unavailable = true;
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<List<DubVoice>> voices() async {
    if (_unavailable) return const [];
    try {
      final raw = await _channel.invokeListMethod<dynamic>('voices');
      if (raw == null) return const [];
      return [
        for (final entry in raw)
          if (entry is Map)
            DubVoice(
              name: '${entry['name'] ?? 'Voice'}',
              locale: '${entry['locale'] ?? ''}',
              isNetwork: entry['network'] == true,
            ),
      ];
    } on MissingPluginException {
      _unavailable = true;
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  @override
  Future<void> speak(
    String text, {
    String? voice,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    if (_unavailable || text.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': text,
        'voice': voice,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
      });
    } on MissingPluginException {
      _unavailable = true;
    } on PlatformException catch (e) {
      debugPrint('[dub] speak failed: ${e.message}');
    }
  }

  @override
  Future<void> stop() async {
    if (_unavailable) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      _unavailable = true;
    } on PlatformException {
      // Nothing was speaking, or the engine is gone; either way we are stopped.
    }
  }

  @override
  void dispose() {
    unawaited(stop());
  }
}
