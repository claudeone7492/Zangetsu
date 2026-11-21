import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

List<String> _orderedSpeakers(List<VoiceSegment> segments) {
  final seen = <String>{};
  final ordered = <String>[];
  for (final segment in segments) {
    if (seen.add(segment.speaker)) ordered.add(segment.speaker);
  }
  return ordered;
}

VoiceGender? _gender(Object? value) =>
    switch (value?.toString().trim().toLowerCase()) {
      'male' || 'm' || 'man' => VoiceGender.male,
      'female' || 'f' || 'woman' => VoiceGender.female,
      _ => null,
    };

/// Detects who is speaking, and when, so AI Dub can give each character its own
/// voice instead of reading the whole episode in one.
///
/// Hikari does this on-device (`VoiceScanRunner.kt` + `SpeakerEmbedder.kt` +
/// `VoiceCut.kt`), which needs a native speaker-embedding model and a second
/// build system. This app already reaches hosted services for translation and
/// transcription, so the first implementation is a hosted diarization call: it
/// is pure Dart, testable, and needs no native code. A local embedder can
/// replace [HttpVoiceScanner] later without touching callers.

/// The apparent gender a diarizer reports for a speaker, when it reports one.
/// Used to pick a matching voice rather than to describe the person.
enum VoiceGender { male, female }

/// One stretch of audio attributed to a single speaker.
@immutable
class VoiceSegment {
  const VoiceSegment({
    required this.startMillis,
    required this.endMillis,
    required this.speaker,
    this.gender,
  });

  final int startMillis;
  final int endMillis;

  /// Stable label for the speaker, e.g. `speaker_0`. Persisted, so it must not
  /// be translated.
  final String speaker;

  final VoiceGender? gender;

  Map<String, dynamic> toJson() => {
    'start': startMillis,
    'end': endMillis,
    'speaker': speaker,
    if (gender != null) 'gender': gender!.name,
  };

  static VoiceSegment? fromJson(Object? value) {
    if (value is! Map) return null;
    final start = value['start'];
    final end = value['end'];
    final speaker = value['speaker'];
    if (start is! num || end is! num || speaker is! String) return null;
    return VoiceSegment(
      startMillis: start.round(),
      endMillis: end.round(),
      speaker: speaker,
      gender: _gender(value['gender']),
    );
  }
}

/// A whole scan: the timed segments plus the distinct speakers in the order
/// they first spoke.
@immutable
class VoiceScanResult {
  const VoiceScanResult({required this.segments, required this.speakers});

  static const VoiceScanResult empty = VoiceScanResult(
    segments: [],
    speakers: [],
  );

  final List<VoiceSegment> segments;
  final List<String> speakers;

  bool get isEmpty => segments.isEmpty;

  /// The speaker talking at [millis], or the one who spoke last before it.
  ///
  /// A cue can start a few milliseconds before a diarizer's boundary, so
  /// falling back to the previous segment is more useful than returning null
  /// and dropping back to the default voice mid-conversation.
  String? speakerAt(int millis) {
    String? previous;
    for (final segment in segments) {
      if (millis >= segment.startMillis && millis < segment.endMillis) {
        return segment.speaker;
      }
      if (segment.startMillis <= millis) previous = segment.speaker;
    }
    return previous;
  }

  Map<String, dynamic> toJson() => {
    'segments': [for (final segment in segments) segment.toJson()],
    'speakers': speakers,
  };

  static VoiceScanResult fromJson(Object? value) {
    if (value is! Map) return empty;
    final rawSegments = value['segments'];
    final segments = <VoiceSegment>[];
    if (rawSegments is List) {
      for (final entry in rawSegments) {
        final segment = VoiceSegment.fromJson(entry);
        if (segment != null) segments.add(segment);
      }
    }
    final rawSpeakers = value['speakers'];
    final speakers = <String>[
      if (rawSpeakers is List)
        for (final entry in rawSpeakers)
          if (entry is String && entry.isNotEmpty) entry,
    ];
    if (segments.isEmpty) return empty;
    return VoiceScanResult(
      segments: List.unmodifiable(segments),
      speakers: List.unmodifiable(
        speakers.isEmpty ? _orderedSpeakers(segments) : speakers,
      ),
    );
  }
}

/// What to scan: the audio, and how to name it.
class VoiceScanRequest {
  const VoiceScanRequest({
    required this.audio,
    required this.fileName,
    this.language,
    this.speakerCount,
  });

  final Uint8List audio;

  /// Filename sent with the upload; the extension tells the endpoint how to
  /// decode [audio].
  final String fileName;

  final String? language;

  /// A hint for how many people are talking, when the caller knows it.
  final int? speakerCount;
}

/// A scan failure with a message safe to surface in the UI.
class VoiceScanException implements Exception {
  const VoiceScanException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The boundary callers depend on, so the hosted client can be swapped for a
/// local embedder later.
abstract class VoiceScanner {
  /// Whether a scan can be attempted at all (an endpoint and key are set).
  bool get isConfigured;

  /// Scans [request] and returns segments sorted by start time.
  ///
  /// Throws [VoiceScanException] with a message fit to show the viewer.
  Future<VoiceScanResult> scan(VoiceScanRequest request);
}

/// A hosted diarization client over an OpenAI-compatible
/// `/audio/transcriptions` endpoint using `response_format=diarized_json`.
///
/// The endpoint, model and key are settings rather than constants: a bundled
/// key would be shared and rate-limited for everyone. The parser is tolerant
/// because "compatible" providers disagree on field names, and a scan that
/// finds the speakers is far more useful than one that fails on a missing key.
class HttpVoiceScanner implements VoiceScanner {
  HttpVoiceScanner({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    Dio? dio,
    this.timeout = const Duration(minutes: 5),
  }) : _dio = dio ?? Dio();

  final String endpoint;
  final String apiKey;
  final String model;
  final Dio _dio;

  /// Diarizing a full episode is slow, so the timeout is generous.
  final Duration timeout;

  @override
  bool get isConfigured =>
      endpoint.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  @override
  Future<VoiceScanResult> scan(VoiceScanRequest request) async {
    if (!isConfigured) {
      throw const VoiceScanException(
        'Add a voice-scan endpoint and key in Settings',
      );
    }
    if (request.audio.isEmpty) {
      throw const VoiceScanException('There is no audio to scan');
    }

    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        request.audio,
        filename: request.fileName,
      ),
      'model': model,
      'response_format': 'diarized_json',
      'chunking_strategy': 'auto',
      if (request.language != null && request.language!.isNotEmpty)
        'language': request.language,
      if (request.speakerCount != null && request.speakerCount! > 0)
        'num_speakers': '${request.speakerCount}',
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
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (e) {
      throw VoiceScanException(_transportMessage(e));
    }

    final body = response.data?.toString() ?? '';
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw VoiceScanException(_statusMessage(status, body));
    }
    final result = parseSegments(body);
    if (result.isEmpty) {
      throw const VoiceScanException('The service found no speakers');
    }
    return result;
  }

  /// Reads the speaker list out of a `diarized_json` body.
  ///
  /// Accepts `speaker`, `speaker_id` or `label`; a numeric id becomes
  /// `speaker_<n>`, a name is kept as written. A segment without a usable
  /// speaker or start time is dropped rather than guessed at.
  static VoiceScanResult parseSegments(String body) {
    final raw = body.trim();
    if (raw.isEmpty || raw.startsWith('<')) return VoiceScanResult.empty;

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return VoiceScanResult.empty;
    }
    if (decoded is! Map) return VoiceScanResult.empty;

    final rawSegments = decoded['segments'];
    if (rawSegments is! List) return VoiceScanResult.empty;

    final segments = <VoiceSegment>[];
    for (final entry in rawSegments) {
      if (entry is! Map) continue;
      final speaker = _speakerLabel(
        entry['speaker'] ?? entry['speaker_id'] ?? entry['label'],
      );
      final start = _secondsToMillis(entry['start']);
      if (speaker == null || start == null) continue;
      final end = _secondsToMillis(entry['end']);
      segments.add(
        VoiceSegment(
          startMillis: start,
          endMillis: (end != null && end > start) ? end : start + 1000,
          speaker: speaker,
          gender: _gender(entry['gender']),
        ),
      );
    }
    if (segments.isEmpty) return VoiceScanResult.empty;
    segments.sort((a, b) => a.startMillis.compareTo(b.startMillis));
    return VoiceScanResult(
      segments: List.unmodifiable(segments),
      speakers: List.unmodifiable(_orderedSpeakers(segments)),
    );
  }

  static String? _speakerLabel(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return int.tryParse(raw) == null ? raw : 'speaker_$raw';
  }

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
      'The voice-scan service timed out',
    DioExceptionType.connectionError =>
      'Couldn\'t reach the voice-scan service',
    DioExceptionType.cancel => 'Voice scan cancelled',
    _ => 'Voice scan failed',
  };

  static String _statusMessage(int status, String body) {
    final detail = _errorDetail(body);
    final base = switch (status) {
      401 || 403 => 'The voice-scan key was rejected',
      404 => 'The voice-scan endpoint was not found',
      413 => 'The audio file is too large to scan',
      429 => 'The voice-scan service is rate limited',
      _ => 'Voice scan failed (HTTP $status)',
    };
    return detail == null ? base : '$base: $detail';
  }

  static String? _errorDetail(String body) {
    final raw = body.trim();
    if (raw.isEmpty || !raw.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final error = decoded['error'];
      final message = error is Map ? error['message'] : error;
      final text = message?.toString().trim();
      if (text == null || text.isEmpty || text.length > 160) return null;
      return text;
    } on FormatException {
      return null;
    }
  }
}
