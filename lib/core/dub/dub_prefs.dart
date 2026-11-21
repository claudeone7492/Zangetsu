import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'voice_scan.dart';

/// Settings for AI Dub — reading the current subtitle cue aloud.
///
/// Deliberately separate from `PlaybackPrefs`: that box is already the largest
/// in the app and dub is a self-contained feature, so it gets its own box and
/// the backup drift guard gets one clear decision instead of a scattering of
/// keys in a box nobody associates with narration.
class DubPrefs extends ChangeNotifier {
  DubPrefs._(this._box);

  final Box _box;

  static const String boxName = 'dub_prefs';

  static Future<DubPrefs> open() async {
    final box = await openBoxSafely<dynamic>(boxName);
    return DubPrefs._(box);
  }

  /// Off by default: narrating over a programme is a strong effect nobody
  /// should discover by accident on first play.
  bool get enabled => _box.get('enabled', defaultValue: false) as bool;

  Future<void> setEnabled(bool value) async {
    await _box.put('enabled', value);
    notifyListeners();
  }

  /// Speaking rate. 0.5–2.0 is the range every TTS engine honours; going wider
  /// makes some engines clamp and others chipmunk.
  double get rate =>
      (_box.get('rate', defaultValue: 1.0) as num).toDouble().clamp(0.5, 2.0);

  Future<void> setRate(double value) async {
    await _box.put('rate', value.clamp(0.5, 2.0));
    notifyListeners();
  }

  double get pitch =>
      (_box.get('pitch', defaultValue: 1.0) as num).toDouble().clamp(0.5, 2.0);

  Future<void> setPitch(double value) async {
    await _box.put('pitch', value.clamp(0.5, 2.0));
    notifyListeners();
  }

  /// Dub loudness relative to the programme. Above 1.0 the narration wins over
  /// the mix, which is the point when the original dialogue is what you are
  /// trying to replace.
  double get volume =>
      (_box.get('volume', defaultValue: 1.0) as num).toDouble().clamp(0.0, 1.0);

  Future<void> setVolume(double value) async {
    await _box.put('volume', value.clamp(0.0, 1.0));
    notifyListeners();
  }

  /// BCP-47 tag of the chosen voice, or null for the engine's default.
  String? get voice => _box.get('voice') as String?;

  Future<void> setVoice(String? value) async {
    if (value == null || value.isEmpty) {
      await _box.delete('voice');
    } else {
      await _box.put('voice', value);
    }
    notifyListeners();
  }

  /// The language the narration is spoken in, when the cue text needs
  /// translating first. Null means "speak the cue as written".
  String? get language => _box.get('language') as String?;

  Future<void> setLanguage(String? value) async {
    if (value == null || value.isEmpty) {
      await _box.delete('language');
    } else {
      await _box.put('language', value);
    }
    notifyListeners();
  }

  /// How many seconds ahead of the cue to start speaking. Speech does not start
  /// instantly, so a small lead is what makes the narration land with the
  /// picture instead of after it.
  double get leadSeconds =>
      (_box.get('leadSeconds', defaultValue: 0.25) as num)
          .toDouble()
          .clamp(0.0, 3.0);

  Future<void> setLeadSeconds(double value) async {
    await _box.put('leadSeconds', value.clamp(0.0, 3.0));
    notifyListeners();
  }

  /// Skip cues that are pure stage direction ("[CROWD CHEERING]"). Off means
  /// they are narrated too, which is occasionally what you want for audio-only
  /// viewing.
  bool get skipSoundEffects =>
      _box.get('skipSoundEffects', defaultValue: true) as bool;

  Future<void> setSkipSoundEffects(bool value) async {
    await _box.put('skipSoundEffects', value);
    notifyListeners();
  }

  // ── Speech-to-subtitle (D4) ───────────────────────────────────────────────
  //
  // The transcription endpoint is user-supplied. A bundled key would be shared
  // by every install and rate-limited for all of them, so the same rule as the
  // OpenSubtitles key applies: the viewer brings their own.

  /// Default endpoint. Prefilled because the request shape is the OpenAI one
  /// and most compatible services use the same path, so the common case is
  /// pasting a key and nothing else.
  static const String defaultTranscriptionEndpoint =
      'https://api.openai.com/v1/audio/transcriptions';

  String get transcriptionEndpoint {
    final value = _box.get('transcriptionEndpoint');
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : defaultTranscriptionEndpoint;
  }

  Future<void> setTranscriptionEndpoint(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _box.delete('transcriptionEndpoint');
    } else {
      await _box.put('transcriptionEndpoint', trimmed);
    }
    notifyListeners();
  }

  String get transcriptionKey =>
      (_box.get('transcriptionKey', defaultValue: '') as String).trim();

  Future<void> setTranscriptionKey(String value) async {
    await _box.put('transcriptionKey', value.trim());
    notifyListeners();
  }

  String get transcriptionModel {
    final value = _box.get('transcriptionModel');
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : 'whisper-1';
  }

  Future<void> setTranscriptionModel(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _box.delete('transcriptionModel');
    } else {
      await _box.put('transcriptionModel', trimmed);
    }
    notifyListeners();
  }

  /// Whether a transcription can be attempted.
  bool get canTranscribe => transcriptionKey.isNotEmpty;

  // ── Voice scan (D3) ───────────────────────────────────────────────────────
  //
  // Speaker detection uses the same hosted, user-supplied endpoint as D4. The
  // result is stored so the narrator can give each speaker its own voice
  // without re-scanning on every launch.

  static const String defaultVoiceScanModel = 'gpt-4o-transcribe-diarize';

  String get voiceScanEndpoint {
    final value = _box.get('voiceScanEndpoint');
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : defaultTranscriptionEndpoint;
  }

  Future<void> setVoiceScanEndpoint(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _box.delete('voiceScanEndpoint');
    } else {
      await _box.put('voiceScanEndpoint', trimmed);
    }
    notifyListeners();
  }

  String get voiceScanKey =>
      (_box.get('voiceScanKey', defaultValue: '') as String).trim();

  Future<void> setVoiceScanKey(String value) async {
    await _box.put('voiceScanKey', value.trim());
    notifyListeners();
  }

  String get voiceScanModel {
    final value = _box.get('voiceScanModel');
    return value is String && value.trim().isNotEmpty
        ? value.trim()
        : defaultVoiceScanModel;
  }

  Future<void> setVoiceScanModel(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _box.delete('voiceScanModel');
    } else {
      await _box.put('voiceScanModel', trimmed);
    }
    notifyListeners();
  }

  /// Whether a voice scan can be attempted.
  bool get canScanVoices => voiceScanKey.isNotEmpty;

  VoiceScanResult? _voiceScanCache;

  /// The last scan, or an empty result. Parsed once and cached, because the
  /// narrator reads this for every cue.
  VoiceScanResult get voiceScan {
    final cached = _voiceScanCache;
    if (cached != null) return cached;
    final raw = _box.get('voiceScan');
    var parsed = VoiceScanResult.empty;
    if (raw is String && raw.isNotEmpty) {
      try {
        parsed = VoiceScanResult.fromJson(jsonDecode(raw));
      } on FormatException {
        parsed = VoiceScanResult.empty;
      }
    }
    return _voiceScanCache = parsed;
  }

  Future<void> setVoiceScan(VoiceScanResult result) async {
    _voiceScanCache = result;
    await _box.put('voiceScan', jsonEncode(result.toJson()));
    notifyListeners();
  }

  Future<void> clearVoiceScan() async {
    _voiceScanCache = VoiceScanResult.empty;
    await _box.delete('voiceScan');
    await _box.delete('speakerVoices');
    notifyListeners();
  }

  /// Voice names chosen for each detected speaker, keyed by the speaker label
  /// from [voiceScan]. Empty means every speaker uses [voice].
  Map<String, String> get speakerVoices {
    final raw = _box.get('speakerVoices');
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is String) '${entry.key}': entry.value as String,
      };
    } on FormatException {
      return const {};
    }
  }

  Future<void> setSpeakerVoice(String speaker, String? voice) async {
    final next = Map<String, String>.from(speakerVoices);
    if (voice == null || voice.isEmpty) {
      next.remove(speaker);
    } else {
      next[speaker] = voice;
    }
    await _box.put('speakerVoices', jsonEncode(next));
    notifyListeners();
  }

  /// The voice to use for [speaker], or null to fall back to [voice].
  String? voiceForSpeaker(String? speaker) =>
      speaker == null ? null : speakerVoices[speaker];

  // ── Voice engine (D2) ─────────────────────────────────────────────────────
  //
  // Two engines satisfy the same contract: the device's own TTS, which is
  // offline and instant, and a hosted neural voice, which sounds human but
  // costs a round-trip per line. Which one is right depends on the viewer's
  // connection and patience, so it is a setting rather than a guess.

  /// `device` or `neural`. Device stays the default: it works with no network
  /// and no waiting, which is the right behaviour for a feature someone turns
  /// on mid-episode.
  String get voiceEngine {
    final value = _box.get('voiceEngine');
    return value == kDubEngineNeural ? kDubEngineNeural : kDubEngineDevice;
  }

  Future<void> setVoiceEngine(String value) async {
    await _box.put(
      'voiceEngine',
      value == kDubEngineNeural ? kDubEngineNeural : kDubEngineDevice,
    );
    notifyListeners();
  }

  bool get usesNeuralVoice => voiceEngine == kDubEngineNeural;

  /// Language the hosted voice speaks, ISO-639-1. Null follows the narration
  /// language, then English — so a dub translated into Spanish is also spoken
  /// in Spanish without a second setting to keep in step.
  String? get neuralLanguage => _box.get('neuralLanguage') as String?;

  Future<void> setNeuralLanguage(String? value) async {
    if (value == null || value.isEmpty) {
      await _box.delete('neuralLanguage');
    } else {
      await _box.put('neuralLanguage', value);
    }
    notifyListeners();
  }

  /// The language the hosted voice should actually use: the explicit choice,
  /// else the narration language, else English.
  String get effectiveNeuralLanguage {
    final explicit = neuralLanguage;
    if (explicit != null && explicit.trim().isNotEmpty) return explicit.trim();
    final narration = language;
    if (narration != null && narration.trim().isNotEmpty) return narration.trim();
    return 'en';
  }
}

/// Engine ids for [DubPrefs.voiceEngine].
const String kDubEngineDevice = 'device';
const String kDubEngineNeural = 'neural';
