import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/tvdb_art.dart';

void main() {
  late HttpServer server;
  late String url;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = 'http://127.0.0.1:${server.port}/search';
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType = ContentType.json;
      await request.drain<void>();
      response.write('''
{"results":[{"hits":[
  {"type":"series","name":"Test Show","year":"2020",
   "poster":"https://art/poster.jpg","banner":"https://art/banner.jpg",
   "overviews":{"eng":"An English overview."},
   "remote_ids":[{"sourceName":"TheMovieDB.com","id":"12345"},
                 {"sourceName":"IMDB","id":"tt1234567"}]},
  {"type":"movie","name":"Test Show","year":"2020","poster":"https://art/movie.jpg"}
]}]}''');
      await response.close();
    });
  });

  setUp(TvdbArt.clearCache);
  tearDownAll(() => server.close(force: true));

  test('returns the series artwork and cross-ids', () async {
    final info = await TvdbArt(Dio(), searchUrl: url).lookup(
      title: 'Test Show',
      year: 2020,
    );
    expect(info, isNotNull);
    expect(info!.poster, 'https://art/poster.jpg');
    expect(info.banner, 'https://art/banner.jpg');
    expect(info.overview, 'An English overview.');
    expect(info.tmdbId, '12345');
    expect(info.imdbId, 'tt1234567');
  });

  test('honours the movie filter', () async {
    final info = await TvdbArt(Dio(), searchUrl: url).lookup(
      title: 'Test Show',
      year: 2020,
      isMovie: true,
    );
    expect(info?.poster, 'https://art/movie.jpg');
  });
}
