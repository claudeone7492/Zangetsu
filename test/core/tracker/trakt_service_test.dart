import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/watch_status.dart';
import 'package:watch_app/core/tracker/trakt_service.dart';

void main() {
  group('deviceLoginFrom', () {
    test('reads the code, url and cadence', () {
      final login = TraktService.deviceLoginFrom({
        'device_code': 'dev',
        'user_code': 'UVMWAZME',
        'verification_url': 'https://auth.trakt.tv/activate',
        'expires_in': 600,
        'interval': 6,
      });
      expect(login, isNotNull);
      expect(login!.deviceCode, 'dev');
      expect(login.userCode, 'UVMWAZME');
      expect(login.verificationUrl, 'https://auth.trakt.tv/activate');
      expect(login.intervalSec, 6);
      expect(login.expiresInSec, 600);
    });

    test('rejects a response without a code', () {
      expect(TraktService.deviceLoginFrom({'user_code': 'X'}), isNull);
      expect(TraktService.deviceLoginFrom('nope'), isNull);
    });
  });

  group('historyBody', () {
    test('a movie is a single movie entry', () {
      expect(TraktService.historyBody(traktId: 7, movie: true), {
        'movies': [
          {
            'ids': {'trakt': 7},
          },
        ],
      });
    });

    test('an episode carries its season', () {
      expect(
        TraktService.historyBody(
          traktId: 7,
          movie: false,
          season: 3,
          episode: 4,
        ),
        {
          'shows': [
            {
              'ids': {'trakt': 7},
              'seasons': [
                {
                  'number': 3,
                  'episodes': [
                    {'number': 4},
                  ],
                },
              ],
            },
          ],
        },
      );
    });

    test('missing season/episode default to 1', () {
      final body = TraktService.historyBody(traktId: 7, movie: false);
      final show = (body!['shows'] as List).single as Map;
      final season = (show['seasons'] as List).single as Map;
      expect(season['number'], 1);
      expect((season['episodes'] as List).single, {'number': 1});
    });
  });

  group('parseList', () {
    test('maps watched movies, shows and the watchlist', () {
      final items = TraktService.parseList(
        watchedMovies: [
          {
            'last_watched_at': '2024-01-02T03:04:05.000Z',
            'movie': {
              'title': 'Heat',
              'year': 1995,
              'ids': {'trakt': 1, 'tmdb': 949, 'imdb': 'tt0113277'},
              'images': {
                'poster': {'full': 'https://x/heat.jpg'},
              },
            },
          },
        ],
        watchedShows: [
          {
            'last_watched_at': '2024-02-03T00:00:00.000Z',
            'show': {
              'title': 'The Wire',
              'year': 2002,
              'aired_episodes': 60,
              'ids': {'trakt': 2, 'tmdb': 1438},
            },
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1, 'plays': 1},
                  {'number': 2, 'plays': 1},
                  {'number': 3, 'plays': 0},
                ],
              },
            ],
          },
        ],
        watchlist: [
          {
            'listed_at': '2024-03-04T00:00:00.000Z',
            'show': {
              'title': 'Andor',
              'year': 2022,
              'aired_episodes': 12,
              'ids': {'trakt': 3, 'tmdb': 83867},
            },
          },
        ],
      );

      expect(items, hasLength(3));
      final movie = items.first;
      expect(movie.status, WatchStatus.completed);
      expect(movie.item.title, 'Heat');
      expect(movie.item.tmdbId, 949);
      expect(movie.item.cover, 'https://x/heat.jpg');
      expect(movie.tmdbIsTv, isFalse);

      final show = items[1];
      expect(show.status, WatchStatus.watching);
      expect(show.progress, 2);
      expect(show.totalEpisodes, 60);
      expect(show.tmdbIsTv, isTrue);
      expect(show.item.tmdbId, 1438);

      final planned = items[2];
      expect(planned.status, WatchStatus.planning);
      expect(planned.item.title, 'Andor');
    });

    test('accepts the list-of-relative-urls poster shape', () {
      final items = TraktService.parseList(
        watchedMovies: [
          {
            'movie': {
              'title': 'Heat',
              'ids': {'trakt': 1},
              'images': {
                'poster': ['media.trakt.tv/movies/1/medium/poster.webp'],
              },
            },
          },
        ],
      );
      expect(
        items.single.item.cover,
        'https://media.trakt.tv/movies/1/medium/poster.webp',
      );
    });

    test('a fully watched show is completed', () {
      final items = TraktService.parseList(
        watchedShows: [
          {
            'show': {
              'title': 'Short',
              'aired_episodes': 2,
              'ids': {'trakt': 9},
            },
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1, 'plays': 1},
                  {'number': 2, 'plays': 2},
                ],
              },
            ],
          },
        ],
      );
      expect(items.single.status, WatchStatus.completed);
      expect(items.single.progress, 2);
    });

    test('dedupes a title that is both watched and watchlisted', () {
      final show = {
        'title': 'Dup',
        'aired_episodes': 1,
        'ids': {'trakt': 4},
      };
      final items = TraktService.parseList(
        watchedShows: [
          {
            'show': show,
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {'number': 1, 'plays': 1},
                ],
              },
            ],
          },
        ],
        watchlist: [
          {'show': show},
        ],
      );
      expect(items, hasLength(1));
      expect(items.single.status, WatchStatus.completed);
    });
  });
}
