import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/dub/http_tts_service.dart';
import 'package:watch_app/core/dub/neural_dub_engine.dart';

/// A Dio whose requests are answered in-process, so the real request building
/// and response handling run without a socket.
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

/// A minimal MPEG frame header followed by filler, which is what the endpoint
/// returns.
Uint8List _mp3([int length = 32]) {
  final bytes = Uint8List(length);
  bytes[0] = 0xFF;
  bytes[1] = 0xFB;
  return bytes;
}

void main() {
  group('HttpTtsService.splitForRequest', () {
    test('keeps a short line as one part', () {
      expect(HttpTtsService.splitForRequest('Hello there.'), ['Hello there.']);
    });

    test('collapses whitespace before measuring', () {
      final parts = HttpTtsService.splitForRequest('  Hello \n\n  there.  ');
      expect(parts, ['Hello there.']);
    });

    test('returns nothing for blank input', () {
      expect(HttpTtsService.splitForRequest('   '), isEmpty);
      expect(HttpTtsService.splitForRequest(''), isEmpty);
    });

    test('splits on a sentence boundary when one fits', () {
      final text = '${'a' * 140}. ${'b' * 140}.';
      final parts = HttpTtsService.splitForRequest(text);
      expect(parts, hasLength(2));
      expect(parts.first, endsWith('.'));
      expect(parts.every((p) => p.length <= HttpTtsService.maxCharsPerRequest),
          isTrue);
    });

    test('keeps the sentence delimiter with the part it ends', () {
      final text = 'First sentence here. Second sentence here.';
      final parts = HttpTtsService.splitForRequest(text, limit: 21);
      expect(parts.first, 'First sentence here.');
    });

    test('falls back to a word boundary when no sentence fits', () {
      final text = List.filled(40, 'word').join(' ');
      final parts = HttpTtsService.splitForRequest(text, limit: 30);
      expect(parts, isNotEmpty);
      for (final part in parts) {
        expect(part.length, lessThanOrEqualTo(30));
        // A word boundary cut never leaves a partial word.
        expect(part.split(' ').every((w) => w == 'word'), isTrue);
      }
    });

    test('cuts mid-token when a single word exceeds the limit', () {
      final parts = HttpTtsService.splitForRequest('x' * 450, limit: 200);
      expect(parts, hasLength(3));
      expect(parts.map((p) => p.length).reduce((a, b) => a + b), 450);
    });

    test('never exceeds the limit for long prose', () {
      final text = List.generate(
        60,
        (i) => 'This is sentence number $i, and it has a few words.',
      ).join(' ');
      final parts = HttpTtsService.splitForRequest(text);
      expect(parts, isNotEmpty);
      for (final part in parts) {
        expect(part.length, lessThanOrEqualTo(HttpTtsService.maxCharsPerRequest));
        expect(part, isNotEmpty);
      }
    });

    test('loses no words when splitting', () {
      final text = List.filled(80, 'alpha beta gamma').join(' ');
      final parts = HttpTtsService.splitForRequest(text);
      final rejoined = parts.join(' ').replaceAll(RegExp(r'\s+'), ' ');
      expect(rejoined, text);
    });
  });

  group('HttpTtsService.voices', () {
    test('every catalogue entry is a language the endpoint speaks', () {
      expect(HttpTtsService.voices, isNotEmpty);
      for (final v in HttpTtsService.voices) {
        expect(v.iso.trim(), isNotEmpty);
        expect(v.label.trim(), isNotEmpty);
        expect(HttpTtsService.supports(v.iso), isTrue);
      }
    });

    test('supports a language by its bare code', () {
      expect(HttpTtsService.supports('zh'), isTrue);
      expect(HttpTtsService.supports('xx'), isFalse);
    });
  });

  group('HttpTtsService.synthesize', () {
    test('sends the text, language and client id', () async {
      RequestOptions? seen;
      final service = HttpTtsService(
        dio: _dioAnswering(
          (_) => Response<List<int>>(
            requestOptions: RequestOptions(),
            statusCode: 200,
            data: _mp3(),
          ),
          capture: (o) => seen = o,
        ),
      );

      final clips = await service.synthesize('Hello there.', language: 'fr');

      expect(clips, hasLength(1));
      expect(clips.single, _mp3());
      expect(seen!.queryParameters['q'], 'Hello there.');
      expect(seen!.queryParameters['tl'], 'fr');
      expect(seen!.queryParameters['client'], 'tw-ob');
    });

    test('issues one request per part for a long line', () async {
      final sent = <String>[];
      final service = HttpTtsService(
        dio: _dioAnswering(
          (o) {
            sent.add(o.queryParameters['q'] as String);
            return Response<List<int>>(
              requestOptions: RequestOptions(),
              statusCode: 200,
              data: _mp3(),
            );
          },
        ),
      );

      final clips = await service.synthesize(
        '${'a' * 150}. ${'b' * 150}.',
        language: 'en',
      );

      expect(clips, hasLength(2));
      expect(sent, hasLength(2));
      expect(sent.every((t) => t.length <= HttpTtsService.maxCharsPerRequest),
          isTrue);
    });

    test('throws for a line with nothing to speak', () async {
      final service = HttpTtsService(dio: _dioAnswering((_) => throw StateError('no request expected')));
      await expectLater(
        service.synthesize('   ', language: 'en'),
        throwsA(isA<TtsException>()),
      );
    });

    test('falls back to English for an unknown language', () async {
      RequestOptions? seen;
      final service = HttpTtsService(
        dio: _dioAnswering(
          (_) => Response<List<int>>(
            requestOptions: RequestOptions(),
            statusCode: 200,
            data: _mp3(),
          ),
          capture: (o) => seen = o,
        ),
      );

      await service.synthesize('Hello.', language: 'xx');
      expect(seen!.queryParameters['tl'], 'en');
    });

    test('rejects an HTML body served with a 200', () async {
      final service = HttpTtsService(
        dio: _dioAnswering(
          (_) => Response<List<int>>(
            requestOptions: RequestOptions(),
            statusCode: 200,
            // '<' is not an MPEG frame sync.
            data: Uint8List.fromList('<html>Error 400</html>'.codeUnits),
          ),
        ),
      );

      await expectLater(
        service.synthesize('Hello.', language: 'en'),
        throwsA(isA<TtsException>()),
      );
    });

    test('rejects an empty body', () async {
      final service = HttpTtsService(
        dio: _dioAnswering(
          (_) => Response<List<int>>(
            requestOptions: RequestOptions(),
            statusCode: 200,
            data: <int>[],
          ),
        ),
      );

      await expectLater(
        service.synthesize('Hello.', language: 'en'),
        throwsA(isA<TtsException>()),
      );
    });

    test('turns a 400 into a message about the line', () async {
      final service = HttpTtsService(
        dio: _dioAnswering(
          (_) => Response<List<int>>(
            requestOptions: RequestOptions(),
            statusCode: 400,
          ),
        ),
      );

      await expectLater(
        service.synthesize('Hello.', language: 'en'),
        throwsA(
          isA<TtsException>().having(
            (e) => e.message,
            'message',
            contains('rejected'),
          ),
        ),
      );
    });

    test('turns a timeout into a message the viewer can act on', () async {
      final service = HttpTtsService(
        dio: _dioAnswering(
          (o) => throw DioException(
            requestOptions: o,
            type: DioExceptionType.receiveTimeout,
          ),
        ),
      );

      await expectLater(
        service.synthesize('Hello.', language: 'en'),
        throwsA(
          isA<TtsException>().having(
            (e) => e.message,
            'message',
            contains('too long'),
          ),
        ),
      );
    });
  });

  group('NeuralDubEngine', () {
    test('writes the clips to playable files and clears them on dispose',
        () async {
      final engine = NeuralDubEngine(
        service: HttpTtsService(
          dio: _dioAnswering(
            (_) => Response<List<int>>(
              requestOptions: RequestOptions(),
              statusCode: 200,
              data: _mp3(64),
            ),
          ),
        ),
      );

      // The player is left uncreated: this asserts the file handoff, which is
      // what mpv actually needs, without a media backend in a unit test.
      final dir = await Directory.systemTemp.createTemp('dub_test_');
      addTearDown(() async {
        if (dir.existsSync()) await dir.delete(recursive: true);
      });

      final files = await engine.writeClipsForTest([
        _mp3(64),
        _mp3(64),
      ]);
      expect(files, hasLength(2));
      for (final file in files) {
        expect(file.existsSync(), isTrue);
        final bytes = await file.readAsBytes();
        expect(bytes, hasLength(64));
        expect(bytes[0], 0xFF);
        expect(bytes[1], 0xFB);
      }

      engine.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(files.first.existsSync(), isFalse);
    });


    test('offers the hosted catalogue as voices', () async {
      final engine = NeuralDubEngine(
        service: HttpTtsService(dio: _dioAnswering((_) => Response<List<int>>(
          requestOptions: RequestOptions(), statusCode: 200, data: _mp3()))),
      );
      final voices = await engine.voices();
      expect(voices, hasLength(HttpTtsService.voices.length));
      expect(voices.every((v) => v.isNetwork), isTrue);
      engine.dispose();
    });

    test('is available without a device voice', () async {
      final engine = NeuralDubEngine(
        service: HttpTtsService(dio: _dioAnswering((_) => Response<List<int>>(
          requestOptions: RequestOptions(), statusCode: 200, data: _mp3()))),
      );
      expect(await engine.isAvailable(), isTrue);
      engine.dispose();
    });
  });
}
