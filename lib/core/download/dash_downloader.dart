import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'dash_manifest.dart';

/// Result of a DASH download: the local temp files to mux, or a reason it
/// failed.
///
/// DASH usually splits an episode into a video track and a separate audio
/// track, each an fMP4 written to its own file. [videoPath] is non-null on
/// success unless the manifest carried audio only; [audioPath] is null when the
/// manifest had a single muxed track.
class DashDownloadResult {
  const DashDownloadResult._({this.videoPath, this.audioPath, this.error});

  const DashDownloadResult.ok({String? videoPath, String? audioPath})
    : this._(videoPath: videoPath, audioPath: audioPath);

  const DashDownloadResult.failed(String error) : this._(error: error);

  final String? videoPath;
  final String? audioPath;
  final String? error;

  bool get isOk => error == null;
  bool get hasAudio => audioPath != null;
}

/// Downloads an MPEG-DASH (`.mpd`) stream to local fMP4 track files by
/// fetching the init segment and every media segment of the selected video and
/// audio tracks, then concatenating each track in order.
///
/// Muxing the two tracks into one playable file is the caller's job (a native
/// MediaMuxer / AVFoundation step) — this only produces the raw track files.
/// DASH segments are fetched with the same bounded parallelism and retry budget
/// as [HlsDownloader]; CENC-encrypted manifests are rejected up front (see
/// [parseDashManifest]) rather than downloaded into unplayable bytes.
class DashDownloader {
  DashDownloader(this._dio);

  final Dio _dio;

  static const int _concurrency = 4;
  static const int _maxAhead = 32;
  static const int _segmentAttempts = 3;
  static const Duration _segmentRetryDelay = Duration(milliseconds: 400);

  /// Downloads [mpdUrl] to local track files beside [outputPath]. Returns
  /// [DashDownloadResult.ok] with the written paths, or
  /// [DashDownloadResult.failed] with a short reason. Any partial files are
  /// removed on failure.
  Future<DashDownloadResult> download({
    required String url,
    required Map<String, String> headers,
    required String outputPath,
    required String preferredQuality,
    required void Function(double progress) onProgress,
    required bool Function() canceled,
    int? connections,
  }) async {
    final concurrency = (connections ?? _concurrency).clamp(1, _concurrency * 4);

    final mpd = await _fetchText(url, headers);
    if (mpd == null) return const DashDownloadResult.failed('manifest unreachable');
    final manifest = parseDashManifest(mpd, url, quality: preferredQuality);
    if (manifest == null || manifest.isEmpty) {
      return const DashDownloadResult.failed('no downloadable DASH track');
    }

    // Progress is split across the tracks actually present, weighted by segment
    // count so a long video track doesn't jump to 90% while audio is untouched.
    final video = manifest.video;
    final audio = manifest.audio;
    final videoSegs = video?.segmentUrls.length ?? 0;
    final audioSegs = audio?.segmentUrls.length ?? 0;
    final totalSegs = videoSegs + audioSegs;
    if (totalSegs == 0) {
      return const DashDownloadResult.failed('empty DASH manifest');
    }

    var doneSegs = 0;
    void bump() {
      doneSegs++;
      onProgress(doneSegs / totalSegs);
    }

    final videoPath = video == null ? null : '$outputPath.v.mp4';
    final audioPath = audio == null ? null : '$outputPath.a.mp4';
    final written = <String>[];

    Future<String?> fetchTrack(DashTrack? track, String? path) async {
      if (track == null || path == null) return null;
      final file = File(path);
      await file.parent.create(recursive: true);
      written.add(path);
      final sink = file.openWrite();
      try {
        if (track.initUrl != null) {
          final init = await _fetchBytes(track.initUrl!, headers);
          if (init == null) return 'init segment fetch failed';
          sink.add(init);
        }
        final fail = await _downloadSegments(
          track.segmentUrls,
          headers,
          sink,
          concurrency: concurrency,
          canceled: canceled,
          onSegment: bump,
        );
        if (fail != null) return fail;
      } finally {
        await sink.flush();
        await sink.close();
      }
      return null;
    }

    final results = await Future.wait([
      fetchTrack(video, videoPath),
      fetchTrack(audio, audioPath),
    ]);
    for (final r in results) {
      if (r != null) {
        await _cleanup(written);
        return DashDownloadResult.failed(r);
      }
    }
    if (canceled()) {
      await _cleanup(written);
      return const DashDownloadResult.failed('canceled');
    }
    return DashDownloadResult.ok(videoPath: videoPath, audioPath: audioPath);
  }

  /// Fetches [segments] with bounded parallelism, writing strictly in order so
  /// the concatenated fMP4 keeps a valid moof/mdat sequence.
  Future<String?> _downloadSegments(
    List<String> segments,
    Map<String, String> headers,
    IOSink sink, {
    required int concurrency,
    required bool Function() canceled,
    required void Function() onSegment,
  }) async {
    final pending = <int, Uint8List>{};
    final total = segments.length;
    var nextIndex = 0;
    var nextWrite = 0;
    var failed = false;
    String? failReason;

    Future<void> worker() async {
      while (true) {
        if (failed || canceled()) return;
        while (nextIndex - nextWrite > _maxAhead && !failed && !canceled()) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        if (failed || canceled()) return;
        final i = nextIndex++;
        if (i >= total) return;
        final bytes = await _fetchBytes(segments[i], headers);
        if (bytes == null) {
          failed = true;
          failReason ??= 'segment ${i + 1}/$total unreachable';
          return;
        }
        pending[i] = bytes;
        while (pending.containsKey(nextWrite)) {
          sink.add(pending.remove(nextWrite)!);
          nextWrite++;
          onSegment();
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    if (failed || canceled() || nextWrite < total) {
      if (canceled()) return 'canceled';
      return failReason ?? 'incomplete ($nextWrite/$total segments)';
    }
    return null;
  }

  Future<void> _cleanup(List<String> paths) async {
    for (final p in paths) {
      try {
        final f = File(p);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<String?> _fetchText(String url, Map<String, String> headers) async {
    try {
      final r = await _dio.getUri<String>(
        Uri.parse(url),
        options: Options(
          responseType: ResponseType.plain,
          headers: headers,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      return r.statusCode == 200 ? r.data : null;
    } catch (_) {
      return null;
    }
  }

  /// Fetches one segment, retrying a transient failure but not a 4xx.
  Future<Uint8List?> _fetchBytes(
    String url,
    Map<String, String> headers,
  ) async {
    for (var attempt = 1; attempt <= _segmentAttempts; attempt++) {
      try {
        final r = await _dio.getUri<List<int>>(
          Uri.parse(url),
          options: Options(
            responseType: ResponseType.bytes,
            headers: headers,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (r.statusCode == 200 && r.data != null) {
          return Uint8List.fromList(r.data!);
        }
        if (r.statusCode != null && r.statusCode! >= 400) return null;
      } catch (_) {
        // timeout / reset / DNS — a retry is exactly what these want.
      }
      if (attempt < _segmentAttempts) {
        await Future<void>.delayed(_segmentRetryDelay * attempt);
      }
    }
    return null;
  }
}
