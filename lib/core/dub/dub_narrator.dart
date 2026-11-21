import 'dart:async';

import 'package:flutter/foundation.dart';

import '../playback/subtitle_cue_text.dart';
import 'dub_engine.dart';
import 'dub_prefs.dart';
import 'dub_scheduler.dart';
import 'srt_parser.dart';

/// Runs AI Dub for one playback session: load a subtitle file, follow the
/// player's position, and speak each cue once.
///
/// Owns no UI and no player: the screen pushes positions in and reads state
/// out, which keeps the timing logic testable with a fake engine.
class DubNarrator extends ChangeNotifier {
  DubNarrator({
    required this.prefs,
    required DubEngine engine,
    Future<String?> Function(String text, String language)? translate,
  }) : _engine = engine,
       _translate = translate {
    // Turning dub off must cut the line that is playing, and a change of rate,
    // pitch, or voice should apply to the next line without the player having
    // to notice. Following the prefs keeps that logic in one place.
    prefs.addListener(onEnabledChanged);
  }

  final DubPrefs prefs;
  final DubEngine _engine;

  /// Optional text→text translation, so a dub can speak a language the
  /// subtitles are not written in. Null means "speak the cue as written".
  final Future<String?> Function(String text, String language)? _translate;

  DubScheduler? _scheduler;
  String? _loadedKey;
  bool _loading = false;
  String? _error;

  /// Text of the line being spoken, for the UI to show what is being narrated.
  String? _speaking;
  String? get speaking => _speaking;

  /// Why the last load failed, if it did. Null when fine.
  String? get error => _error;

  bool get isReady => _scheduler != null && !_scheduler!.isEmpty;
  bool get isLoading => _loading;
  int get cueCount => _scheduler?.cues.length ?? 0;

  /// The subtitle file currently loaded, so a repeated call is a no-op.
  String? get loadedKey => _loadedKey;

  /// Load [srt] for [key] (a URL or a file path). Idempotent: calling again
  /// with the same key and the same text does nothing, which matters because
  /// the player rebuilds often.
  Future<void> load(String key, String srt) async {
    if (_loading) return;
    if (_loadedKey == key && _scheduler != null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final cues = SrtParser.parse(srt);
      if (cues.isEmpty) {
        _scheduler = null;
        _loadedKey = key;
        _error = 'No readable cues in this subtitle track.';
        return;
      }
      _scheduler = DubScheduler(
        cues: cues,
        lead: Duration(
          milliseconds: (prefs.leadSeconds * 1000).round(),
        ),
      );
      _loadedKey = key;
    } catch (e) {
      _scheduler = null;
      _error = 'Could not read this subtitle track.';
      debugPrint('[dub] load failed: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Tell the narrator where playback is. Speaks a cue if one is due.
  ///
  /// Returns when the line has been handed to the engine (after any
  /// translation). Callers on a player tick can ignore the future; tests and
  /// anything that needs to know speech actually started can await it.
  Future<void> onPosition(Duration position) async {
    if (!prefs.enabled || _scheduler == null) return;
    final cue = _scheduler!.dueAt(position);
    if (cue == null) return;
    await _speakCue(cue.text, cue.start.inMilliseconds);
  }

  /// Drop the loaded track — the viewer turned subtitles off, or picked a track
  /// with no readable text. Without this the previous track's cues stay live and
  /// the dub keeps narrating the language that is no longer on screen.
  void clear() {
    if (_scheduler == null && _loadedKey == null && _error == null) return;
    _scheduler = null;
    _loadedKey = null;
    _error = null;
    _setSpeaking(null);
    unawaited(_engine.stop());
    notifyListeners();
  }

  /// A seek happened: re-anchor so skipped lines are not read in a burst and
  /// earlier lines can be heard again.
  void onSeek(Duration position) {
    _scheduler?.seekTo(position);
    unawaited(_engine.stop());
    _setSpeaking(null);
  }

  /// Playback paused or stopped: cut the current line rather than letting it
  /// finish over a frozen frame.
  void onPause() {
    unawaited(_engine.stop());
    _setSpeaking(null);
  }

  /// The user turned dub on/off mid-session.
  void onEnabledChanged() {
    if (!prefs.enabled) {
      unawaited(_engine.stop());
      _setSpeaking(null);
    }
  }

  Future<void> _speakCue(String text, int startMillis) async {
    // Stage directions are not dialogue. [SubtitleCueText] already knows how to
    // recognise them, so the same rule the translator uses applies here.
    if (prefs.skipSoundEffects && SubtitleCueText.isUntranslatable(
      SubtitleCueText.strip(text),
    )) {
      return;
    }
    var spoken = text;
    final language = prefs.language;
    if (language != null && _translate != null) {
      try {
        spoken = await _translate(text, language) ?? text;
      } catch (_) {
        // Translation is a nicety: speak the original rather than nothing.
      }
    }
    if (!prefs.enabled) return;
    _setSpeaking(spoken);
    // A detected speaker can have its own voice. Neural voices are picked by
    // language rather than by name, so the mapping only applies to the device
    // engine.
    final speaker = prefs.voiceScan.speakerAt(startMillis);
    final perSpeaker = prefs.usesNeuralVoice
        ? null
        : prefs.voiceForSpeaker(speaker);
    await _engine.speak(
      spoken,
      voice: perSpeaker ?? prefs.voice,
      rate: prefs.rate,
      pitch: prefs.pitch,
      volume: prefs.volume,
    );
  }

  void _setSpeaking(String? value) {
    if (_speaking == value) return;
    _speaking = value;
    notifyListeners();
  }

  @override
  void dispose() {
    prefs.removeListener(onEnabledChanged);
    // The engine is injected and shared (it is a singleton in the injector), so
    // disposing it here would leave the next player session with a dead engine.
    // Stopping is all this narrator owns.
    unawaited(_engine.stop());
    super.dispose();
  }
}
