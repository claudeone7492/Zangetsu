import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/dub/voice_scan.dart';

/// A Dio whose every request is answered by [respond], so request building and
/// response parsing run without a socket.
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

HttpVoiceScanner _scanner(Dio dio) => HttpVoiceScanner(
  endpoint: 'https://example.test/v1/audio/transcriptions',
  apiKey: 'sk-test',
  model: 'diarize-1',
  dio: dio,
);

VoiceScanRequest _request({Uint8List? audio}) => VoiceScanRequest(
  audio: audio ?? Uint8List.fromList([1, 2, 3, 4]),
  fileName: 'episode.mp3',
  language: 'en',
);

void main() {
  group('HttpVoiceScanner.parseSegments', () {
    test('reads speakers in first-spoken order and sorts by start', () {
      final result = HttpVoiceScanner.parseSegments('''
{
  "segments": [
    {"start": 9.0, "end": 10.0, "speaker": "Alice", "gender": "female"},
    {"start": 1.0, "end": 2.5, "speaker": "speaker_1", "gender": "male"},
    {"start": 5.0, "end": 6.0, "speaker": "Alice"}
  ]
}''');
      expect(result.segments.map((s) => s.startMillis), [1000, 5000, 9000]);
      expect(result.segments.first.speaker, 'speaker_1');
      expect(result.segments.first.gender, VoiceGender.male);
      expect(result.segments.last.gender, VoiceGender.female);
      expect(result.speakers, ['speaker_1', 'Alice']);
    });

    test('accepts speaker_id, label and numeric ids', () {
      final result = HttpVoiceScanner.parseSegments('''
{"segments":[
  {"start":0,"end":1,"speaker_id":0},
  {"start":1,"end":2,"label":"Narrator"},
  {"start":2,"end":3,"speaker":"2"}
]}''');
      expect(result.speakers, ['speaker_0', 'Narrator', 'speaker_2']);
    });

    test('drops segments with no speaker or no start', () {
      final result = HttpVoiceScanner.parseSegments('''
{"segments":[
  {"start":0,"end":1},
  {"end":1,"speaker":"A"},
  {"start":2,"end":3,"speaker":"B"}
]}''');
      expect(result.segments, hasLength(1));
      expect(result.segments.single.speaker, 'B');
    });

    test('gives a zero-length segment a readable duration', () {
      final result = HttpVoiceScanner.parseSegments(
        '{"segments":[{"start":4.0,"end":4.0,"speaker":"A"}]}',
      );
      expect(result.segments.single.endMillis, greaterThan(4000));
    });

    test('returns empty for non-JSON, HTML, empty, or a bare object', () {
      expect(HttpVoiceScanner.parseSegments('').isEmpty, isTrue);
      expect(HttpVoiceScanner.parseSegments('<html>gateway</html>').isEmpty, isTrue);
      expect(HttpVoiceScanner.parseSegments('not json').isEmpty, isTrue);
      expect(HttpVoiceScanner.parseSegments('{"text":"hi"}').isEmpty, isTrue);
    });

    test('ignores an unknown gender rather than dropping the segment', () {
      final result = HttpVoiceScanner.parseSegments(
        '{"segments":[{"start":0,"end":1,"speaker":"A","gender":"robot"}]}',
      );
      expect(result.segments.single.speaker, 'A');
      expect(result.segments.single.gender, isNull);
    });
  });

  group('HttpVoiceScanner.scan', () {
    test('uploads the audio as a diarized_json request', () async {
      RequestOptions? seen;
      final scanner = _scanner(
        _dioAnswering(
          (_) => Response<dynamic>(
            requestOptions: RequestOptions(),
            statusCode: 200,
            data: '{"segments":[{"start":0,"end":1,"speaker":"A"}]}',
          ),
          capture: (options) => seen = options,
        ),
      );

      final result = await scanner.scan(
        VoiceScanRequest(
          audio: Uint8List.fromList([9, 8, 7]),
          fileName: 'episode.mp3',
          language: 'fr',
          speakerCount: 2,
        ),
      );

      expect(result.speakers, ['A']);
      expect(seen, isNotNull);
      expect(seen!.headers['Authorization'], 'Bearer sk-test');
      final data = seen!.data as FormData;
      final fields = {for (final e in data.fields) e.key: e.value};
      expect(fields['model'], 'diarize-1');
      expect(fields['response_format'], 'diarized_json');
      expect(fields['language'], 'fr');
      expect(fields['num_speakers'], '2');
      expect(data.files.single.key, 'file');
      expect(data.files.single.value.filename, 'episode.mp3');
    });

    test('refuses to scan without a configuration', () async {
      final scanner = HttpVoiceScanner(
        endpoint: '',
        apiKey: '',
        model: '',
        dio: _dioAnswering((_) => Response<dynamic>(requestOptions: RequestOptions())),
      );
      expect(scanner.isConfigured, isFalse);
      await expectLater(
        scanner.scan(_request()),
        throwsA(isA<VoiceScanException>()),
      );
    });

    test('refuses to scan empty audio', () async {
      final scanner = _scanner(_dioAnswering((_) => Response<dynamic>(requestOptions: RequestOptions())));
      await expectLater(
        scanner.scan(_request(audio: Uint8List(0))),
        throwsA(
          isA<VoiceScanException>().having(
            (e) => e.message,
            'message',
            contains('no audio'),
          ),
        ),
      );
    });

    test('maps status codes onto actionable messages', () async {
      for (final (status, needle) in [
        (401, 'rejected'),
        (404, 'not found'),
        (413, 'too large'),
        (429, 'rate limited'),
      ]) {
        final scanner = _scanner(
          _dioAnswering(
            (_) => Response<dynamic>(
              requestOptions: RequestOptions(),
              statusCode: status,
              data: '',
            ),
          ),
        );
        await expectLater(
          scanner.scan(_request()),
          throwsA(
            isA<VoiceScanException>().having(
              (e) => e.message,
              'message',
              contains(needle),
            ),
          ),
        );
      }
    });

    test('surfaces a short server error message', () async {
      final scanner = _scanner(
        _dioAnswering(
          (_) => Response<dynamic>(
            requestOptions: RequestOptions(),
            statusCode: 400,
            data: '{"error":{"message":"model does not support diarization"}}',
          ),
        ),
      );
      await expectLater(
        scanner.scan(_request()),
        throwsA(
          isA<VoiceScanException>().having(
            (e) => e.message,
            'message',
            contains('model does not support diarization'),
          ),
        ),
      );
    });

    test('reports a body with no speakers instead of an empty result', () async {
      final scanner = _scanner(
        _dioAnswering(
          (_) => Response<dynamic>(
            requestOptions: RequestOptions(),
            statusCode: 200,
            data: '{"text":"silence"}',
          ),
        ),
      );
      await expectLater(
        scanner.scan(_request()),
        throwsA(
          isA<VoiceScanException>().having(
            (e) => e.message,
            'message',
            contains('no speakers'),
          ),
        ),
      );
    });
  });

  group('VoiceScanResult', () {
    const result = VoiceScanResult(
      segments: [
        VoiceSegment(startMillis: 1000, endMillis: 2000, speaker: 'A'),
        VoiceSegment(startMillis: 2000, endMillis: 3000, speaker: 'B'),
      ],
      speakers: ['A', 'B'],
    );

    test('speakerAt finds the segment covering a time', () {
      expect(result.speakerAt(1500), 'A');
      expect(result.speakerAt(2500), 'B');
    });

    test('speakerAt falls back to the speaker who spoke last', () {
      expect(result.speakerAt(9000), 'B');
      expect(result.speakerAt(0), isNull);
    });

    test('round-trips through JSON', () {
      final restored = VoiceScanResult.fromJson(result.toJson());
      expect(restored.segments, hasLength(2));
      expect(restored.speakers, ['A', 'B']);
      expect(restored.segments.first.startMillis, 1000);
      expect(restored.speakerAt(2500), 'B');
    });

    test('restores speakers from segments when the list is missing', () {
      final restored = VoiceScanResult.fromJson({
        'segments': [
          {'start': 0, 'end': 1, 'speaker': 'X'},
          {'start': 1, 'end': 2, 'speaker': 'Y'},
          {'start': 2, 'end': 3, 'speaker': 'X'},
        ],
      });
      expect(restored.speakers, ['X', 'Y']);
    });

    test('an empty or malformed body restores to empty', () {
      expect(VoiceScanResult.fromJson(null).isEmpty, isTrue);
      expect(VoiceScanResult.fromJson({'segments': []}).isEmpty, isTrue);
    });
  });
}
