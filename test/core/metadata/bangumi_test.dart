import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/bangumi.dart';

void main() {
  late HttpServer server;
  late String base;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v0/search/subjects') {
        await request.drain<void>();
        response.write('''
{"data":[
  {"id":42,"name":"Test Anime","name_cn":"测试动画","date":"2020-01-01","eps":12},
  {"id":43,"name":"劇場版 Test Anime","name_cn":"","date":"2021-01-01","eps":1}
]}''');
      } else if (request.uri.path == '/v0/episodes') {
        response.write('''
{"total":2,"data":[
  {"sort":1,"name":"Pilot","name_cn":"","airdate":"2020-01-01"},
  {"sort":2,"name":"Second","name_cn":"第二集","airdate":"2020-01-08"}
]}''');
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  setUp(Bangumi.clearCache);
  tearDownAll(() => server.close(force: true));

  test('generic episode names are recognised', () {
    expect(Bangumi.isGenericName('Episode 12'), isTrue);
    expect(Bangumi.isGenericName('第12集'), isTrue);
    expect(Bangumi.isGenericName('12'), isTrue);
    expect(Bangumi.isGenericName('The Beginning'), isFalse);
  });

  test('reads a subject episode list and prefers the Chinese name', () async {
    final episodes = await Bangumi(
      Dio(),
      base: base,
    ).episodes(title: 'Test Anime');
    expect(episodes, isNotNull);
    expect(episodes, hasLength(2));
    expect(episodes!.first.name, 'Pilot');
    expect(episodes[1].name, '第二集');
    expect(episodes[1].airDate, '2020-01-08');
  });

  test('a movie-only candidate is not merged into the series', () async {
    server.close(force: true);
    final movieServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    movieServer.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      if (request.uri.path == '/v0/search/subjects') {
        await request.drain<void>();
        response.write(
          '{"data":[{"id":7,"name":"劇場版 Only","name_cn":"","date":"2021-01-01"}]}',
        );
      } else {
        response.write('{"total":0,"data":[]}');
      }
      await response.close();
    });
    final episodes = await Bangumi(
      Dio(),
      base: 'http://127.0.0.1:${movieServer.port}',
    ).episodes(title: 'Only');
    expect(episodes, isNull);
    await movieServer.close(force: true);
  });
}
