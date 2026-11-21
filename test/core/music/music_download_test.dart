import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/music/music_download.dart';
import 'package:watch_app/core/music/music_models.dart';

/// Serves [bytes] to every request, so the file path and the naming are the
/// only things under test — the transport is not.
class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);

  final List<int> bytes;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['audio/mp4'],
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

MusicTrack _track({String? artist = 'AC/DC?'}) => MusicTrack(
  id: 't1',
  title: 'Back in Black: live',
  sourceId: 'jiosaavn',
  artist: artist,
);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('music_download_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('writes the track to a sanitised name in the music folder', () async {
    final target = Directory('${dir.path}/music');
    final dio = Dio()..httpClientAdapter = _BytesAdapter(List.filled(64, 7));

    final file = await MusicDownload(dio, directory: target).save(
      _track(),
      'https://cdn.example.test/song.m4a',
    );

    expect(file.existsSync(), isTrue);
    expect(file.parent.path, target.path);
    expect(file.path, endsWith('.m4a'));
    final name = file.uri.pathSegments.last;
    expect(name, 'AC DC - Back in Black live.m4a');
    expect(await file.length(), 64);
  });

  test('creates the folder when it does not exist yet', () async {
    final target = Directory('${dir.path}/nested/music');
    final dio = Dio()..httpClientAdapter = _BytesAdapter(const [1, 2, 3]);
    expect(target.existsSync(), isFalse);

    final file = await MusicDownload(dio, directory: target).save(
      _track(),
      'https://cdn.example.test/song.m4a',
    );

    expect(target.existsSync(), isTrue);
    expect(file.existsSync(), isTrue);
  });

  test('an unknown artist is named Unknown rather than left blank', () async {
    final dio = Dio()..httpClientAdapter = _BytesAdapter(const [1]);
    final file = await MusicDownload(dio, directory: dir).save(
      _track(artist: null),
      'https://cdn.example.test/song.m4a',
    );
    expect(file.uri.pathSegments.last, 'Unknown - Back in Black live.m4a');
  });

  test('reports progress against the server length', () async {
    final dio = Dio()..httpClientAdapter = _BytesAdapter(List.filled(512, 3));
    final seen = <int>[];
    await MusicDownload(dio, directory: dir).save(
      _track(),
      'https://cdn.example.test/song.m4a',
      onProgress: (received, total) => seen.add(total),
    );
    expect(seen, isNotEmpty);
    expect(seen.last, 512);
  });
}
