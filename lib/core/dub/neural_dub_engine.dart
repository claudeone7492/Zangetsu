import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

import 'dub_engine.dart';
import 'http_tts_service.dart';

/// Plays [HttpTtsService]'s clips, so a neural voice can stand in for the
/// device's TTS engine behind the same [DubEngine] contract.
///
/// Two things make this more than a thin wrapper:
///
///  * **A line can be several clips.** The endpoint caps a request at 200
///    characters, so a long caption arrives as several MP3s. They are handed to
///    the player as a playlist, which plays them back to back with no gap —
///    playing them one at a time would put an audible seam mid-sentence.
///  * **The next line interrupts the current one.** [speak] stops whatever is
///    playing, exactly as the system engine does: narration that lags behind the
///    picture is worse than narration that is cut off.
///
/// The player is created lazily and reused, because constructing a media player
/// is expensive and dub speaks on almost every tick of a busy scene.
class NeuralDubEngine implements DubEngine {
  NeuralDubEngine({HttpTtsService? service, Player? player})
    : _service = service ?? HttpTtsService(),
      _player = player;

  final HttpTtsService _service;
  Player? _player;

  /// Completes the pending [speak] when playback ends or is replaced, so a
  /// caller awaiting a line is never left hanging.
  Completer<void>? _done;

  /// Bumped on every [speak]/[stop]; a late completion from an older line must
  /// not clear the state of the one that replaced it.
  int _generation = 0;

  /// Temp directory holding the current line's clips.
  Directory? _clipDir;

  /// Directories a previous line wrote to, awaiting removal.
  final List<Directory> _staleClipDirs = [];

  /// Language the clips are synthesized in. Set from the dub language so the
  /// voice matches what the viewer asked to hear.
  String _language = 'en';

  /// Overrides the synthesized language (e.g. from `DubPrefs.language`).
  set language(String value) {
    if (value.trim().isEmpty) return;
    _language = value.trim();
  }

  Player get _ensurePlayer {
    final existing = _player;
    if (existing != null) return existing;
    final created = Player();
    created.stream.completed.listen((completed) {
      if (completed) _finish();
    });
    _player = created;
    return created;
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<List<DubVoice>> voices() async => [
    for (final v in HttpTtsService.voices)
      DubVoice(
        name: v.label,
        locale: v.iso,
        isNetwork: true,
        labelKey: v.labelKey,
      ),
  ];

  @override
  Future<void> speak(
    String text, {
    String? voice,
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Cut the previous line first: two clips at once is never what is wanted.
    _finish();

    final generation = ++_generation;
    final done = Completer<void>();
    _done = done;

    // A voice passed by the caller is a language tag from our catalogue, so it
    // wins over the ambient language.
    final language = (voice != null && HttpTtsService.supports(voice))
        ? voice
        : _language;

    final List<Uint8List> clips;
    try {
      clips = await _service.synthesize(trimmed, language: language);
    } on TtsException catch (e) {
      debugPrint('[dub] neural synth failed: ${e.message}');
      if (_isCurrent(generation)) _finish();
      return;
    }
    if (!_isCurrent(generation)) return;

    try {
      final files = await _writeClips(clips);
      if (!_isCurrent(generation)) return;
      final player = _ensurePlayer;
      await player.setVolume(volume.clamp(0.0, 1.0) * 100);
      // Rate is applied here rather than requested from the endpoint, which
      // ignores a speed parameter.
      await player.setRate(rate.clamp(0.5, 2.0));
      await player.open(
        Playlist([for (final file in files) Media(file.uri.toString())]),
      );
      // The player has moved to the new playlist, so the old files are free.
      unawaited(_clearStaleClips());
    } catch (e) {
      debugPrint('[dub] neural playback failed: $e');
      if (_isCurrent(generation)) _finish();
      return;
    }

    await done.future;
  }

  /// Writes the clips to files and returns them.
  ///
  /// mpv is handed a path, not a data URI, and a clip can be a hundred kilobytes
  /// — far too much to push through a command line.
  ///
  /// The previous directory is not removed here: the player may still be reading
  /// from it until the new playlist is opened. It is kept in [_staleClipDirs]
  /// and removed once playback has moved on.
  Future<List<File>> _writeClips(List<Uint8List> clips) async {
    final dir = await Directory.systemTemp.createTemp('zangetsu_dub_');
    final previous = _clipDir;
    _clipDir = dir;
    if (previous != null) _staleClipDirs.add(previous);

    final files = <File>[];
    for (var i = 0; i < clips.length; i++) {
      final file = File('${dir.path}/part$i.mp3');
      await file.writeAsBytes(clips[i], flush: true);
      files.add(file);
    }
    return files;
  }

  /// Exposed so the file handoff — what mpv actually needs — can be asserted
  /// without a media backend in a unit test.
  @visibleForTesting
  Future<List<File>> writeClipsForTest(List<Uint8List> clips) =>
      _writeClips(clips);

  /// Removes directories the player has finished with. Best effort: a file the
  /// player still holds open simply stays until the next attempt.
  Future<void> _clearStaleClips() async {
    if (_staleClipDirs.isEmpty) return;
    final stale = _staleClipDirs.toList();
    _staleClipDirs.clear();
    for (final dir in stale) {
      try {
        if (dir.existsSync()) await dir.delete(recursive: true);
      } catch (e) {
        debugPrint('[dub] could not clear clips: $e');
      }
    }
  }

  Future<void> _clearClips() async {
    final current = _clipDir;
    _clipDir = null;
    if (current != null) _staleClipDirs.add(current);
    await _clearStaleClips();
  }

  bool _isCurrent(int generation) => generation == _generation;

  void _finish() {
    _generation++;
    final done = _done;
    _done = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  @override
  Future<void> stop() async {
    _finish();
    // The player may still be reading the file, so the directory is left for
    // the next line or dispose to remove.
    try {
      await _player?.stop();
    } catch (_) {
      // Already stopped, or the player was never created.
    }
  }

  @override
  void dispose() {
    _finish();
    final player = _player;
    _player = null;
    unawaited(player?.dispose());
    unawaited(_clearClips());
  }
}
