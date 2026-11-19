import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/dub/transcription_audio_source.dart';
import 'package:watch_app/core/dub/voice_transcriber.dart';

/// A Dio whose every request is answered by [respond], so the real request
/// building and response parsing run without a socket.
Dio _dioAnswering(
  Response<dynamic> Function(RequestOptions options) respond, {
  void Function(RequestOptions options)? capture,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        capture?.call(options);
        handler.resolve(respond(options));
      },
    ),
  );
  return dio;
}

const _verboseJson = '''
{
  "text": "Hello there. General Kenobi.",
  "segments": [
    {"id": 1, "start": 0.0, "end": 1.5, "text": " Hello there."},
    {"id": 0, "start": 2.25, "end": 4.0, "text": " General Kenobi. "}
  ]
}
''';

void main() {
  group('HttpVoiceTranscriber.parseCues', () {
    test('reads segments into cues sorted by start time', () {
      final cues = HttpVoiceTranscriber.parseCues(_verboseJson);
      expect(cues, hasLength(2));
      expect(cues.first.text, 'Hello there.');
      expect(cues.first.startMillis, 0);
      expect(cues.first.endMillis, 1500);
      expect(cues.last.text, 'General Kenobi.');
      expect(cues.last.startMillis, 2250);
      expect(cues.last.endMillis, 4000);
    });

    test('sorts out-of-order segments', () {
      final cues = HttpVoiceTranscriber.parseCues('''
{"segments":[
  {"start": 9.0, "end": 10.0, "text": "second"},
  {"start": 1.0, "end": 2.0, "text": "first"}
]}''');
      expect(cues.map((c) => c.text), ['first', 'second']);
    });

    test('gives a zero-length segment a readable duration', () {
      final cues = HttpVoiceTranscriber.parseCues(
        '{"segments":[{"start":5.0,"end":5.0,"text":"ping"}]}',
      );
      expect(cues.single.startMillis, 5000);
      expect(cues.single.endMillis, greaterThan(5000));
    });

    test('falls back to the flat text when there are no segments', () {
      final cues = HttpVoiceTranscriber.parseCues(
        '{"text":"A whole paragraph with no timings."}',
      );
      expect(cues.single.text, 'A whole paragraph with no timings.');
      expect(cues.single.startMillis, 0);
      expect(cues.single.endMillis, greaterThan(0));
    });

    test('drops segments with blank text', () {
      final cues = HttpVoiceTranscriber.parseCues(
        '{"segments":[{"start":0.0,"end":1.0,"text":"   "}]}',
      );
      expect(cues, isEmpty);
    });

    test('returns nothing for a non-JSON body', () {
      expect(HttpVoiceTranscriber.parseCues('<html>gateway</html>'), isEmpty);
      expect(HttpVoiceTranscriber.parseCues(''), isEmpty);
      expect(HttpVoiceTranscriber.parseCues('not json at all'), isEmpty);
    });
  });

  group('HttpVoiceTranscriber.transcribe', () {
    test('posts a multipart upload carrying the file and model', () async {
      RequestOptions? seen;
      final transcriber = HttpVoiceTranscriber(
        endpoint: 'https://example.test/v1/audio/transcriptions',
        apiKey: 'secret-key',
        model: 'whisper-1',
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: _verboseJson,
          ),
          capture: (o) => seen = o,
        ),
      );

      final cues = await transcriber.transcribe(
        TranscriptionRequest(
          audio: Uint8List.fromList([1, 2, 3, 4]),
          fileName: 'episode.mp4',
          language: 'ja',
        ),
      );

      expect(cues, hasLength(2));
      expect(seen!.method, 'POST');
      expect(seen!.uri.toString(), 'https://example.test/v1/audio/transcriptions');
      expect(seen!.headers['Authorization'], 'Bearer secret-key');

      final form = seen!.data as FormData;
      final fields = {for (final e in form.fields) e.key: e.value};
      expect(fields['model'], 'whisper-1');
      expect(fields['response_format'], 'verbose_json');
      expect(fields['language'], 'ja');
      expect(form.files, hasLength(1));
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'episode.mp4');
    });

    test('omits the language when none is given', () async {
      RequestOptions? seen;
      final transcriber = HttpVoiceTranscriber(
        endpoint: 'https://example.test/t',
        apiKey: 'k',
        model: 'm',
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: _verboseJson,
          ),
          capture: (o) => seen = o,
        ),
      );
      await transcriber.transcribe(
        TranscriptionRequest(
          audio: Uint8List.fromList([1]),
          fileName: 'a.mp3',
        ),
      );
      final fields = {
        for (final e in (seen!.data as FormData).fields) e.key: e.value,
      };
      expect(fields.containsKey('language'), isFalse);
    });

    test('surfaces the server message on a rejected key', () async {
      final transcriber = HttpVoiceTranscriber(
        endpoint: 'https://example.test/t',
        apiKey: 'bad',
        model: 'm',
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 401,
            data: jsonEncode({
              'error': {'message': 'Incorrect API key provided'},
            }),
          ),
        ),
      );

      await expectLater(
        transcriber.transcribe(
          TranscriptionRequest(
            audio: Uint8List.fromList([1]),
            fileName: 'a.mp3',
          ),
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.message,
            'message',
            allOf(contains('rejected'), contains('Incorrect API key')),
          ),
        ),
      );
    });

    test('refuses to run without configuration', () async {
      final transcriber = HttpVoiceTranscriber(
        endpoint: '',
        apiKey: '',
        model: '',
      );
      expect(transcriber.isConfigured, isFalse);
      await expectLater(
        transcriber.transcribe(
          TranscriptionRequest(
            audio: Uint8List.fromList([1]),
            fileName: 'a.mp3',
          ),
        ),
        throwsA(isA<TranscriptionException>()),
      );
    });

    test('refuses empty audio', () async {
      final transcriber = HttpVoiceTranscriber(
        endpoint: 'https://example.test/t',
        apiKey: 'k',
        model: 'm',
      );
      await expectLater(
        transcriber.transcribe(
          TranscriptionRequest(audio: Uint8List(0), fileName: 'a.mp3'),
        ),
        throwsA(isA<TranscriptionException>()),
      );
    });

    test('rejects a response that carries no speech', () async {
      final transcriber = HttpVoiceTranscriber(
        endpoint: 'https://example.test/t',
        apiKey: 'k',
        model: 'm',
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: '{"text":""}',
          ),
        ),
      );
      await expectLater(
        transcriber.transcribe(
          TranscriptionRequest(
            audio: Uint8List.fromList([1]),
            fileName: 'a.mp3',
          ),
        ),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('no speech'),
          ),
        ),
      );
    });

    test('reports progress ending at 1', () async {
      final transcriber = HttpVoiceTranscriber(
        endpoint: 'https://example.test/t',
        apiKey: 'k',
        model: 'm',
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: _verboseJson,
          ),
        ),
      );
      final progress = <double>[];
      await transcriber.transcribe(
        TranscriptionRequest(
          audio: Uint8List.fromList([1]),
          fileName: 'a.mp3',
        ),
        onProgress: progress.add,
      );
      expect(progress.last, 1.0);
    });
  });

  group('TranscriptionAudioSource', () {
    test('accepts direct media URLs and rejects playlists', () {
      expect(
        TranscriptionAudioSource.isDirectMediaUrl('https://h/a/ep1.mp4'),
        isTrue,
      );
      expect(
        TranscriptionAudioSource.isDirectMediaUrl(
          'https://h/a/ep1.mp4?token=abc',
        ),
        isTrue,
      );
      expect(
        TranscriptionAudioSource.isDirectMediaUrl('https://h/a/master.m3u8'),
        isFalse,
      );
      expect(
        TranscriptionAudioSource.isDirectMediaUrl('https://h/a/index.M3U8?x=1'),
        isFalse,
      );
      expect(
        TranscriptionAudioSource.isDirectMediaUrl('https://h/stream/no-ext'),
        isFalse,
      );
    });

    test('takes the filename from the path, ignoring the query', () {
      expect(
        TranscriptionAudioSource.fileNameFor('https://h/a/ep1.mp4?sig=xyz'),
        'ep1.mp4',
      );
      expect(
        TranscriptionAudioSource.fileNameFor('https://h/no-extension'),
        'audio.mp3',
      );
    });

    test('refuses an HLS source with a message the viewer can act on', () async {
      final source = TranscriptionAudioSource(
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: <int>[1, 2, 3],
          ),
        ),
      );
      await expectLater(
        source.resolve('https://h/a/master.m3u8'),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('segments'),
          ),
        ),
      );
    });

    test('downloads a direct URL and returns the bytes', () async {
      final source = TranscriptionAudioSource(
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: <int>[10, 20, 30],
          ),
        ),
      );
      final bytes = await source.resolve('https://h/a/ep1.mp4');
      expect(bytes, [10, 20, 30]);
    });

    test('reports a failed download', () async {
      final source = TranscriptionAudioSource(
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 404,
            data: <int>[],
          ),
        ),
      );
      await expectLater(
        source.resolve('https://h/a/ep1.mp4'),
        throwsA(isA<TranscriptionException>()),
      );
    });

    test('rejects a download larger than the cap', () async {
      final source = TranscriptionAudioSource(
        maxBytes: 2,
        dio: _dioAnswering(
          (options) => Response<dynamic>(
            requestOptions: options,
            statusCode: 200,
            data: <int>[1, 2, 3],
          ),
        ),
      );
      await expectLater(
        source.resolve('https://h/a/ep1.mp4'),
        throwsA(
          isA<TranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('rejects an empty source URL', () async {
      final source = TranscriptionAudioSource();
      await expectLater(
        source.resolve('   '),
        throwsA(isA<TranscriptionException>()),
      );
    });
  });
}
