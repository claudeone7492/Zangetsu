import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../download/hls_downloader.dart';
import 'dvr_store.dart';

/// Drives DVR capture: watches the schedule and records what is on.
///
/// Live TV has no seekable timeline to download from — a channel is a rolling
/// HLS window — so "recording" means reading the live playlist at the moment
/// the airing starts and capturing from there. That is exactly what
/// [HlsDownloader] does for a VOD URL, so capture reuses it rather than growing
/// a second segment pipeline.
///
/// The loop is a plain [Timer] on purpose: this is foreground capture, started
/// when the app opens the schedule. Background capture needs a native service
/// and is out of scope here — an app that claims to record in the background
/// and doesn't is worse than one that records while open.
class DvrCaptureService {
  DvrCaptureService({
    required DvrStore store,
    required Dio dio,
    String Function()? outputDirectory,
    this.tick = const Duration(seconds: 20),
  }) : _store = store,
       _dio = dio,
       _outputDirectory = outputDirectory ?? _defaultOutputDirectory,
       _downloader = HlsDownloader(dio);

  /// Recordings live under the app's documents directory beside the other
  /// saved media, so they land where the user already looks.
  static String _defaultOutputDirectory() => '';

  Future<String> _resolveOutputDirectory() async {
    final configured = _outputDirectory();
    if (configured.isNotEmpty) return configured;
    final docs = await getApplicationDocumentsDirectory();
    return '${docs.path}/recordings';
  }

  final DvrStore _store;
  final Dio _dio;
  final String Function() _outputDirectory;
  final HlsDownloader _downloader;
  final Duration tick;

  Timer? _timer;
  final Set<String> _running = {};
  final Map<String, double> _progress = {};

  /// Entry id → 0..1 for the recordings in flight. The UI reads this to draw a
  /// progress bar on the schedule row.
  Map<String, double> get progress => Map.unmodifiable(_progress);
  bool isRecording(String id) => _running.contains(id);

  /// Begin watching. Idempotent, so a screen can call it on every build.
  void start() {
    _timer ??= Timer.periodic(tick, (_) => _poll());
    _poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Start any capture whose window is open and that isn't already running.
  ///
  /// Runs on a timer rather than a one-shot schedule because the app may have
  /// been closed when the airing began: a recording whose start has passed but
  /// whose window is still open is still worth capturing from "now".
  Future<void> _poll() async {
    for (final entry in _store.dueForCapture()) {
      if (_running.contains(entry.id)) continue;
      unawaited(_capture(entry));
    }
  }

  Future<void> _capture(DvrEntry entry) async {
    if (!_running.add(entry.id)) return;
    _progress[entry.id] = 0;
    try {
      final dir = Directory(await _resolveOutputDirectory());
      await dir.create(recursive: true);
      final safeTitle = _safeFileName(
        '${entry.channelName} - ${entry.title}'.trim(),
      );
      final stamp = entry.start.toLocal();
      final name =
          '${safeTitle}_${stamp.year}'
          '${stamp.month.toString().padLeft(2, '0')}'
          '${stamp.day.toString().padLeft(2, '0')}_'
          '${stamp.hour.toString().padLeft(2, '0')}'
          '${stamp.minute.toString().padLeft(2, '0')}.ts';

      // Stop the capture at the airing's end even though the downloader runs to
      // completion: the playlist only holds what has aired so far, so this
      // bounds the wait rather than truncating a finished file.
      var canceled = false;
      final deadline = entry.captureStop;
      final guard = Timer(
        deadline.difference(DateTime.now().toUtc()).isNegative
            ? Duration.zero
            : deadline.difference(DateTime.now().toUtc()),
        () => canceled = true,
      );

      try {
        final error = await _downloader.download(
          url: entry.streamUrl,
          headers: const {},
          outputPath: '${dir.path}/$name',
          preferredQuality: 'best',
          onProgress: (p) => _progress[entry.id] = p,
          canceled: () => canceled,
        );
        if (error != null) {
          debugPrint('[dvr] capture failed for ${entry.id}: $error');
        }
      } finally {
        guard.cancel();
      }
    } catch (e) {
      debugPrint('[dvr] capture threw for ${entry.id}: $e');
    } finally {
      _running.remove(entry.id);
      _progress.remove(entry.id);
    }
  }

  /// Resolve a channel's playable URL so a guide booking can become a
  /// recording. Returns null when the provider gives nothing back.
  Future<String?> resolveStream(String sourceId, String itemUrl) async {
    try {
      final res = await _dio.get<dynamic>(
        itemUrl,
        options: Options(validateStatus: (c) => c != null && c < 400),
      );
      final data = res.data;
      if (data is String && data.contains('://')) return data;
    } catch (e) {
      debugPrint('[dvr] stream resolve failed for $itemUrl: $e');
    }
    return null;
  }

  /// Strip characters that break a filename on Android, iOS or a FAT SD card.
  static String _safeFileName(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'recording';
    return cleaned.length > 80 ? cleaned.substring(0, 80) : cleaned;
  }
}
