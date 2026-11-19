import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../playback/subtitle_exporter.dart';

/// Turns a stretch of audio into timed caption cues.
///
/// This is the reverse of AI Dub: dub reads an existing caption aloud, while
/// this produces the caption from the soundtrack itself. That is the only way
/// to caption a source that ships no subtitles at all, which is common for the
/// older catalogue.
///
/// A hosted Whisper endpoint is used rather than a bundled model: the app
/// already speaks HTTP for translation, a local `whisper.cpp` would add tens of
/// megabytes of native code and a second build system, and transcription is an
/// occasional action rather than something on the playback path.
///
/// The interface exists so the engine can be swapped — a local model, a
/// different vendor — without touching the player. Everything below this line is
/// testable Dart; only [HttpVoiceTranscriber] talks to the network.
abstract class VoiceTranscriber {
  /// Whether a transcription can be attempted at all (an endpoint and key are
  /// configured). Callers use this to hide the action rather than fail late.
  bool get isConfigured;

  /// Transcribes [audio] and returns cues sorted by start time.
  ///
  /// [language] is an ISO-639-1 hint; null lets the engine detect it. Progress
  /// is reported 0..1 when the endpoint supports it — many do not, in which case
  /// only the final 1.0 arrives.
  ///
  /// Throws [TranscriptionException] with a message fit to show the viewer.
  Future<List<SubtitleCue>> transcribe(
    TranscriptionRequest request, {
    void Function(double)? onProgress,
  });
}

/// What to transcribe: the audio, and how to name it.
class TranscriptionRequest {
  const TranscriptionRequest({
    required this.audio,
    required this.fileName,
    this.language,
    this.prompt,
  });

  /// The audio bytes to send. Whisper accepts mp3, mp4, m4a, wav, webm and more,
  /// so the caller may hand over the media file itself as long as the container
  /// carries an audio track.
  final Uint8List audio;

  /// Filename sent with the upload. The extension is what tells the endpoint how
  /// to decode [audio], so it must match the real format.
  final String fileName;

  final String? language;

  /// Optional vocabulary hint — a show title, character names — that biases
  /// spelling toward what the viewer expects to read.
  final String? prompt;
}

/// A transcription failure with a message safe to surface in the UI.
class TranscriptionException implements Exception {
  const TranscriptionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A hosted, OpenAI-compatible `/audio/transcriptions` client.
///
/// "Compatible" is the useful part: the same request shape is served by OpenAI,
/// Groq, and a self-hosted faster-whisper behind an OpenAI shim, so one client
/// covers them all and the user points it at whichever they have. The endpoint
/// and key are settings, not constants, because a bundled key would be shared
/// and rate-limited for everyone.
class HttpVoiceTranscriber implements VoiceTranscriber {
  HttpVoiceTranscriber({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    Dio? dio,
    this.timeout = const Duration(minutes: 5),
  }) : _dio = dio ?? Dio();

  /// Full URL of the transcription endpoint, e.g.
  /// `https://api.openai.com/v1/audio/transcriptions`.
  final String endpoint;

  final String apiKey;

  /// Model name the endpoint expects (`whisper-1`, `whisper-large-v3`, …).
  final String model;

  final Dio _dio;

  /// Transcription is slow — a full episode can take minutes on a hosted model —
  /// so the timeout is generous rather than tuned for an interactive call.
  final Duration timeout;

  @override
  bool get isConfigured =>
      endpoint.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  @override
  Future<List<SubtitleCue>> transcribe(
    TranscriptionRequest request, {
    void Function(double)? onProgress,
  }) async {
    if (!isConfigured) {
      throw const TranscriptionException(
        'Add a transcription endpoint and key in Settings',
      );
    }
    if (request.audio.isEmpty) {
      throw const TranscriptionException('There is no audio to transcribe');
    }

    // `verbose_json` is what carries timestamps; the default JSON response is
    // one flat paragraph and cannot become cues.
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        request.audio,
        filename: request.fileName,
      ),
      'model': model,
      'response_format': 'verbose_json',
      'timestamp_granularities[]': 'segment',
      if (request.language != null && request.language!.isNotEmpty)
        'language': request.language,
      if (request.prompt != null && request.prompt!.isNotEmpty)
        'prompt': request.prompt,
    });

    Response<dynamic> response;
    try {
      response = await _dio.post<dynamic>(
        endpoint,
        data: form,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          connectTimeout: const Duration(seconds: 30),
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (_) => true,
          // Keep the body as text so a non-JSON error page still yields a
          // readable message instead of a parse failure.
          responseType: ResponseType.plain,
        ),
        onSendProgress: (sent, total) {
          // Upload progress is the only progress a plain HTTP call can report;
          // it stops at 0.5 so the bar never claims to be finished while the
          // model is still working.
          if (total > 0) onProgress?.call((sent / total) * 0.5);
        },
      );
    } on DioException catch (e) {
      throw TranscriptionException(_transportMessage(e));
    }

    final body = response.data?.toString() ?? '';
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw TranscriptionException(_statusMessage(status, body));
    }
    final cues = parseCues(body);
    if (cues.isEmpty) {
      throw const TranscriptionException('The service returned no speech');
    }
    onProgress?.call(1);
    return cues;
  }

  /// Reads the cue list out of a `verbose_json` body.
  ///
  /// Tolerant on purpose: some servers return `segments`, others only `text`,
  /// and a shim may omit the top-level wrapper. A body with no timestamps still
  /// yields one cue spanning the whole clip, because a caption with a rough
  /// timing is far more useful than no caption at all.
  static List<SubtitleCue> parseCues(String body) {
    final raw = body.trim();
    if (raw.isEmpty || raw.startsWith('<')) return const [];

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! Map) return const [];

    final segments = decoded['segments'];
    final cues = <SubtitleCue>[];
    if (segments is List) {
      for (final entry in segments) {
        if (entry is! Map) continue;
        final text = '${entry['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        final start = _secondsToMillis(entry['start']);
        final end = _secondsToMillis(entry['end']);
        if (start == null) continue;
        cues.add(
          SubtitleCue(
            startMillis: start,
            // A zero-length cue is invisible; give it a readable minimum.
            endMillis: (end != null && end > start) ? end : start + 2000,
            text: text,
          ),
        );
      }
    }
    if (cues.isNotEmpty) return _sorted(cues);

    // No segments: fall back to the flat text as a single cue.
    final text = '${decoded['text'] ?? ''}'.trim();
    if (text.isEmpty) return const [];
    return [
      SubtitleCue(startMillis: 0, endMillis: 60000, text: text),
    ];
  }

  static List<SubtitleCue> _sorted(List<SubtitleCue> cues) =>
      [...cues]..sort((a, b) => a.startMillis.compareTo(b.startMillis));

  /// Segment times arrive as floating-point seconds.
  static int? _secondsToMillis(Object? value) {
    final seconds = value is num
        ? value.toDouble()
        : double.tryParse('${value ?? ''}');
    if (seconds == null || !seconds.isFinite || seconds < 0) return null;
    return (seconds * 1000).round();
  }

  static String _transportMessage(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout =>
      'The transcription service timed out',
    DioExceptionType.connectionError =>
      'Couldn\'t reach the transcription service',
    DioExceptionType.cancel => 'Transcription cancelled',
    _ => 'Transcription failed',
  };

  /// Maps an HTTP failure onto something the viewer can act on, preferring the
  /// server's own message when it is short enough to be one.
  static String _statusMessage(int status, String body) {
    final detail = _errorDetail(body);
    final base = switch (status) {
      401 || 403 => 'The transcription key was rejected',
      404 => 'The transcription endpoint was not found',
      413 => 'The audio file is too large to transcribe',
      429 => 'The transcription service is rate limited',
      _ => 'Transcription failed (HTTP $status)',
    };
    return detail == null ? base : '$base: $detail';
  }

  /// Pulls `error.message` out of a JSON error body, or returns null when the
  /// body is not a short JSON error.
  static String? _errorDetail(String body) {
    final raw = body.trim();
    if (raw.isEmpty || !raw.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      final message = error is Map ? error['message'] : error;
      final text = message?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return text.length > 200 ? '${text.substring(0, 200)}…' : text;
    } on FormatException {
      return null;
    }
  }
}
