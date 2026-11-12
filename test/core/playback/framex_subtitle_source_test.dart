import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/framex_subtitle_source.dart';

/// Answers the FrameX endpoints from canned bodies, so the parse and failover
/// logic runs without a network.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter({
    this.stream,
    this.subsEndpoint,
    this.subtitleBytes,
    this.failHosts = const {},
  });

  /// The JSON body for `/api/stream`; null makes the host fail.
  final Map<String, dynamic>? stream;

  /// The JSON body for the standalone `/api/subtitles` endpoint.
  final Map<String, dynamic>? subsEndpoint;

  /// The bytes served for a subtitle fetch.
  final List<int>? subtitleBytes;

  /// Hosts that should throw instead of answering, to exercise failover.
  final Set<String> failHosts;

  final List<String> requested = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final url = options.uri.toString();
    requested.add(url);
    for (final host in failHosts) {
      if (url.startsWith(host)) {
        throw DioException(requestOptions: options, message: 'host down');
      }
    }
    if (url.contains('/api/stream')) {
      return ResponseBody.fromString(
        jsonEncode(stream ?? const {'subtitles': []}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (url.contains('/api/subtitles') && !url.contains('/proxy')) {
      return ResponseBody.fromString(
        jsonEncode(subsEndpoint ?? const {'subtitles': []}),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    if (url.contains('/api/search')) {
      return ResponseBody.fromString(
        jsonEncode(const {
          'results': [
            {'id': '603', 'title': 'The Matrix', 'type': 'movie', 'year': '1999'},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    return ResponseBody.fromBytes(
      subtitleBytes ?? utf8.encode('WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n'),
      200,
      headers: {
        Headers.contentTypeHeader: ['text/vtt'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_FakeAdapter adapter) =>
    Dio(BaseOptions(baseUrl: 'https://api.framextv.tech'))
      ..httpClientAdapter = adapter;

void main() {
  group('FrameXSubtitleSource.subtitlesFor', () {
    test('parses the subtitles list, deduping by url', () async {
      final adapter = _FakeAdapter(
        stream: {
          'subtitles': [
            {
              'url': 'https://rezesubs.com/subs/movie/x/english.vtt',
              'label': 'WEB-DL',
              'language': 'English',
              'lang': 'en',
            },
            {
              'url': 'https://rezesubs.com/subs/movie/x/english.vtt',
              'label': 'duplicate',
            },
            {'url': 'not-a-url', 'label': 'bad'},
          ],
        },
      );
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      final subs = await source.subtitlesFor('603');
      expect(subs.length, 1);
      expect(subs.first.label, 'WEB-DL');
      expect(subs.first.language, 'English');
      expect(subs.first.displayName, 'WEB-DL');
    });

    test('includes season and episode for a tv title', () async {
      final adapter = _FakeAdapter();
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      await source.subtitlesFor('1399', type: 'tv', season: 2, episode: 5);
      expect(adapter.requested.first, contains('season=2'));
      expect(adapter.requested.first, contains('episode=5'));
    });

    test('falls back to the standalone endpoint when the stream has none',
        () async {
      final adapter = _FakeAdapter(
        stream: const {'subtitles': []},
        subsEndpoint: {
          'subtitles': [
            {'url': 'https://x/y.vtt', 'language': 'English', 'source': 'opensubtitles'},
          ],
        },
      );
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      final subs = await source.subtitlesFor('603');
      expect(subs.length, 1);
      expect(subs.first.source, 'opensubtitles');
      expect(adapter.requested.any((u) => u.contains('/api/subtitles?')), isTrue);
    });

    test('does not hit the standalone endpoint when the stream has subtitles',
        () async {
      final adapter = _FakeAdapter(
        stream: {
          'subtitles': [
            {'url': 'https://x/stream.vtt', 'language': 'English'},
          ],
        },
      );
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      final subs = await source.subtitlesFor('603');
      expect(subs.length, 1);
      expect(adapter.requested.any((u) => u.contains('/api/subtitles?')), isFalse);
    });

    test('returns empty rather than throwing on a malformed body', () async {
      final adapter = _FakeAdapter(stream: {'unexpected': true});
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      expect(await source.subtitlesFor('603'), isEmpty);
    });

    test('returns empty for an empty id', () async {
      final adapter = _FakeAdapter();
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      expect(await source.subtitlesFor('   '), isEmpty);
      expect(adapter.requested, isEmpty);
    });

    test('fails over to a second host when the first is down', () async {
      final adapter = _FakeAdapter(
        stream: {
          'subtitles': [
            {'url': 'https://x/y.vtt', 'language': 'English'},
          ],
        },
        failHosts: {'https://api.framextv.tech'},
      );
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      final subs = await source.subtitlesFor('603');
      expect(subs.length, 1);
      expect(adapter.requested.any((u) => u.startsWith('https://api.framextv.cc')), isTrue);
    });
  });

  group('FrameXSubtitleSource.downloadText', () {
    test('decodes bytes and normalises to VTT', () async {
      final adapter = _FakeAdapter(
        subtitleBytes: utf8.encode(
          '1\n00:00:01,000 --> 00:00:02,000\nHello\n',
        ),
      );
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      final text = await source.downloadText(
        'https://rezesubs.com/subs/movie/x/english.srt',
      );
      expect(text, isNotNull);
      expect(text, startsWith('WEBVTT'));
      expect(text, contains('00:00:01.000 --> 00:00:02.000'));
    });

    test('returns null for an HTML error page', () async {
      final adapter = _FakeAdapter(
        subtitleBytes: utf8.encode('<html><body>404</body></html>'),
      );
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      expect(
        await source.downloadText('https://x/y.vtt'),
        isNull,
      );
    });

    test('returns null for an empty url', () async {
      final adapter = _FakeAdapter();
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      expect(await source.downloadText(''), isNull);
    });
  });

  group('FrameXSubtitleSource.searchTitles', () {
    test('parses catalogue results', () async {
      final adapter = _FakeAdapter();
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      final titles = await source.searchTitles('The Matrix');
      expect(titles.length, 1);
      expect(titles.first.id, '603');
      expect(titles.first.title, 'The Matrix');
    });

    test('is empty for a blank query', () async {
      final adapter = _FakeAdapter();
      final source = FrameXSubtitleSource(dio: _dioWith(adapter));
      expect(await source.searchTitles('  '), isEmpty);
      expect(adapter.requested, isEmpty);
    });
  });
}
