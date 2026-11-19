import 'dart:async';

import 'dub_engine.dart';
import 'dub_prefs.dart';
import 'neural_dub_engine.dart';

/// The [DubEngine] the app actually injects: one that forwards to whichever
/// engine the viewer picked.
///
/// The alternative — swapping the registered singleton when the setting changes
/// — would leave a live [DubNarrator] holding a dead engine, and would need
/// every call site to re-resolve. Delegating keeps one instance for the life of
/// the process, so the narrator never notices the engine change under it.
class SwitchingDubEngine implements DubEngine {
  SwitchingDubEngine({
    required this.prefs,
    DubEngine? device,
    DubEngine? neural,
  }) : _device = device ?? PlatformDubEngine(),
       _neural = neural ?? NeuralDubEngine();

  final DubPrefs prefs;
  final DubEngine _device;
  final DubEngine _neural;

  /// The engine for the current setting.
  DubEngine get active => prefs.usesNeuralVoice ? _neural : _device;

  /// The hosted voice speaks whatever language the dub is in, so it has to be
  /// told before [speak] is called.
  void syncLanguage() {
    final engine = _neural;
    if (engine is NeuralDubEngine) {
      engine.language = prefs.effectiveNeuralLanguage;
    }
  }

  @override
  Future<bool> isAvailable() async {
    // A hosted voice needs no installed device voice, so the neural engine is
    // what makes dub usable on a device with none.
    if (prefs.usesNeuralVoice) return true;
    return _device.isAvailable();
  }

  @override
  Future<List<DubVoice>> voices() async {
    if (prefs.usesNeuralVoice) {
      syncLanguage();
      return _neural.voices();
    }
    return _device.voices();
  }

  @override
  Future<void> speak(
    String text, {
    String? voice,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    if (prefs.usesNeuralVoice) syncLanguage();
    // Switching engines mid-line must not leave the other one talking.
    final other = prefs.usesNeuralVoice ? _device : _neural;
    unawaited(other.stop());
    await active.speak(
      text,
      voice: voice,
      rate: rate,
      pitch: pitch,
      volume: volume,
    );
  }

  @override
  Future<void> stop() async {
    await Future.wait([_device.stop(), _neural.stop()]);
  }

  @override
  void dispose() {
    _device.dispose();
    _neural.dispose();
  }
}
