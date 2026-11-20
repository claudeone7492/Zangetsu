import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/music/jiosaavn_source.dart';
import 'package:watch_app/core/music/music_models.dart';
import 'package:watch_app/core/music/music_source.dart';

/// Serves canned JSON through the real Dio pipeline.
///
/// A fake adapter rather than a mocked `JioSaavnSource` keeps the code under
/// test real: the request is built, sent, and the response parsed exactly as in
/// production. Only the socket is replaced.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

JioSaavnSource sourceWith(FakeAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return JioSaavnSource(dio: dio);
}

/// Tracks with a known expiry, for the stream-refresh cases.
abstract final class MusicTrackStub {
  static MusicTrack fresh() => MusicTrack(
    id: 'abc123',
    title: 'Fresh',
    sourceId: 'jiosaavn',
    streamUrl: 'https://stream/fresh.mp3',
    streamExpiresAt: DateTime.now().add(const Duration(hours: 2)),
  );

  static MusicTrack stale() => MusicTrack(
    id: 'abc123',
    title: 'Stale',
    sourceId: 'jiosaavn',
    streamUrl: 'https://stream/old.mp3',
    streamExpiresAt: DateTime.now().subtract(const Duration(hours: 2)),
  );
}

/// A song shaped like the newest saavn.dev response.
Map<String, dynamic> song({
  String id = 'abc123',
  String name = 'Tum Hi Ho',
  Object? primaryArtists = 'Arijit Singh',
  Object? image,
  Object? downloadUrl,
  Object? duration = 262,
  Object? year = '2013',
  String language = 'hindi',
  int? expiresAt,
}) => {
  'id': id,
  'name': name,
  'primaryArtists': primaryArtists,
  'image': image ??
      [
        {'quality': '50x50', 'url': 'https://art/50.jpg'},
        {'quality': '500x500', 'url': 'https://art/500.jpg'},
      ],
  'downloadUrl':
      downloadUrl ??
      [
        {'quality': '96kbps', 'url': 'https://stream/96.mp3'},
        {'quality': '320kbps', 'url': 'https://stream/320.mp3'},
      ],
  'duration': duration,
  'year': year,
  'language': language,
  'album': {'name': 'Aashiqui 2'},
  'expiresAt': ?expiresAt,
};

void main() {
  test('search parses the data.results envelope', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'status': 'SUCCESS',
        'data': {
          'total': 1,
          'results': [song()],
        },
      }),
    );
    final tracks = await sourceWith(adapter).search('tum hi ho');

    expect(tracks, hasLength(1));
    final track = tracks.single;
    expect(track.id, 'abc123');
    expect(track.title, 'Tum Hi Ho');
    expect(track.artist, 'Arijit Singh');
    expect(track.album, 'Aashiqui 2');
    expect(track.artwork, 'https://art/500.jpg', reason: 'highest quality wins');
    expect(track.streamUrl, 'https://stream/320.mp3');
    expect(track.duration, const Duration(seconds: 262));
    expect(track.year, 2013, reason: 'year arrives as a string');
    expect(track.language, 'hindi');
    expect(track.sourceId, 'jiosaavn');
  });

  test('search sends the query and page to the right endpoint', () async {
    final adapter = FakeAdapter((_) => json({'data': {'results': []}}));
    await sourceWith(adapter).search('  lofi  ', page: 2);

    final request = adapter.requests.single;
    expect(request.uri.path, endsWith('/api/search/songs'));
    expect(request.queryParameters['query'], 'lofi', reason: 'query is trimmed');
    expect(request.queryParameters['page'], 2);
  });

  test('a blank query is not sent to the network at all', () async {
    final adapter = FakeAdapter((_) => json({'data': {'results': []}}));
    expect(await sourceWith(adapter).search('   '), isEmpty);
    expect(adapter.requests, isEmpty);
  });

  test('HTML entities in titles and artists are decoded', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [
            song(name: 'Kabhi &amp; Kabhi', primaryArtists: 'Rock &#39;n&#39; Roll'),
          ],
        },
      }),
    );
    final track = (await sourceWith(adapter).search('q')).single;
    expect(track.title, 'Kabhi & Kabhi');
    expect(track.artist, "Rock 'n' Roll");
  });

  test('artists supplied as a list of objects are joined', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [
            song(primaryArtists: null, image: null)
              ..['artists'] = {
                'primary': [
                  {'name': 'Singer One'},
                  {'name': 'Singer Two'},
                ],
              },
          ],
        },
      }),
    );
    final track = (await sourceWith(adapter).search('q')).single;
    expect(track.artist, 'Singer One, Singer Two');
  });

  test('a legacy image map is understood', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [
            song(image: {'50x50': 'https://art/50.jpg', '500x500': 'https://art/500.jpg'}),
          ],
        },
      }),
    );
    expect((await sourceWith(adapter).search('q')).single.artwork, 'https://art/500.jpg');
  });

  test('a legacy downloadUrl map is understood', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [
            song(downloadUrl: {'320kbps': 'https://stream/320.mp3'}),
          ],
        },
      }),
    );
    expect((await sourceWith(adapter).search('q')).single.streamUrl, 'https://stream/320.mp3');
  });

  test('entries without an id or title are skipped, not fatal', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [
            {'name': 'no id'},
            {'id': 'no-title'},
            song(id: 'good'),
          ],
        },
      }),
    );
    final tracks = await sourceWith(adapter).search('q');
    expect(tracks.single.id, 'good');
  });

  test('a bare data list (by-id endpoint) is understood', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': [song(id: 'byid')],
      }),
    );
    expect((await sourceWith(adapter).search('q')).single.id, 'byid');
  });

  test('a single song object is understood', () async {
    final adapter = FakeAdapter((_) => json({'data': song(id: 'single')}));
    expect((await sourceWith(adapter).search('q')).single.id, 'single');
  });

  test('expiresAt becomes an absolute time', () async {
    final epoch = DateTime.now().add(const Duration(hours: 2)).millisecondsSinceEpoch ~/ 1000;
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [song(expiresAt: epoch)],
        },
      }),
    );
    final track = (await sourceWith(adapter).search('q')).single;
    expect(track.streamExpiresAt, isNotNull);
    expect(track.hasFreshStream, isTrue);
  });

  test('home tolerates a failing row and keeps the others', () async {
    var call = 0;
    final adapter = FakeAdapter((options) {
      call++;
      // First row 500s, the rest succeed.
      if (call == 1) {
        return ResponseBody.fromString('boom', 500);
      }
      return json({
        'data': {
          'results': [song(id: 'row-$call')],
        },
      });
    });

    final sections = await sourceWith(adapter).home();
    expect(sections, hasLength(2), reason: 'one failed row must not sink the page');
    expect(sections.every((s) => s.tracks.isNotEmpty), isTrue);
  });

  test('home rows carry the expected titles', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': {
          'results': [song()],
        },
      }),
    );
    final sections = await sourceWith(adapter).home();
    expect(sections.map((s) => s.title), ['Trending', 'New releases', 'Lo-fi']);
  });

  test('a transport failure surfaces as a MusicSourceException', () async {
    final adapter = FakeAdapter(
      (options) => throw DioException(requestOptions: options, message: 'no route'),
    );
    await expectLater(
      sourceWith(adapter).search('q'),
      throwsA(
        isA<MusicSourceException>().having(
          (e) => e.message,
          'message',
          contains('JioSaavn'),
        ),
      ),
    );
  });

  test('streamFor reuses a fresh URL without a request', () async {
    final adapter = FakeAdapter((_) => json({'data': {}}));
    final source = sourceWith(adapter);
    final track = MusicTrackStub.fresh();
    expect(await source.streamFor(track), 'https://stream/fresh.mp3');
    expect(adapter.requests, isEmpty, reason: 'a fresh URL needs no refresh');
  });

  test('streamFor refreshes a stale URL by id', () async {
    final adapter = FakeAdapter(
      (_) => json({
        'data': [song(id: 'abc123', downloadUrl: [{'quality': '320kbps', 'url': 'https://stream/new.mp3'}])],
      }),
    );
    final source = sourceWith(adapter);
    final stale = MusicTrackStub.stale();
    expect(await source.streamFor(stale), 'https://stream/new.mp3');
    expect(adapter.requests.single.uri.path, endsWith('/api/songs/abc123'));
  });

  test('streamFor keeps the old URL when the refresh fails', () async {
    final adapter = FakeAdapter(
      (options) => throw DioException(requestOptions: options, message: 'offline'),
    );
    final stale = MusicTrackStub.stale();
    expect(await sourceWith(adapter).streamFor(stale), stale.streamUrl);
  });
}
