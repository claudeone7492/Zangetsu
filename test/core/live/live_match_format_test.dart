import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/live/live_match_format.dart';

void main() {
  group('teamSimilarity', () {
    test('folds accents and ignores club noise words', () {
      expect(teamSimilarity('Slovácko B', 'Slovacko'), 1.0);
      expect(teamSimilarity('FC Barcelona', 'Barcelona'), 1.0);
    });

    test('does not match a shared city alone', () {
      expect(
        teamSimilarity('Manchester United', 'Manchester City'),
        lessThan(1),
      );
    });
  });

  group('bestFixtureMatch', () {
    final board = [
      ['Arsenal', 'Chelsea'],
      ['Manchester United', 'Manchester City'],
      ['Israel', 'Kosovo'],
    ];

    test('matches a "Home vs Away" title to its row', () {
      expect(bestFixtureMatch('Arsenal vs Chelsea', board), 0);
      expect(bestFixtureMatch('Israel vs Kosovo', board), 2);
    });

    test('matches when the source orders the teams the other way', () {
      expect(bestFixtureMatch('Chelsea vs Arsenal', board), 0);
    });

    test('does not confuse two teams from the same city', () {
      expect(bestFixtureMatch('Manchester United vs Manchester City', board), 1);
      expect(bestFixtureMatch('Arsenal vs Tottenham', board), -1);
    });

    test('returns -1 for an empty board', () {
      expect(bestFixtureMatch('Arsenal vs Chelsea', const []), -1);
    });
  });

  group('liveMatchInfo', () {
    test('renders a running score and the clock', () {
      expect(
        liveMatchInfo(
          home: 'Arsenal',
          away: 'Chelsea',
          homeScore: 2,
          awayScore: 1,
          status: '2H',
          clock: "67'",
        ),
        "Arsenal 2-1 Chelsea \u00B7 67'",
      );
    });

    test('shows HT at half time', () {
      expect(
        liveMatchInfo(
          home: 'Arsenal',
          away: 'Chelsea',
          homeScore: 1,
          awayScore: 0,
          status: 'HT',
          clock: 'HT',
        ),
        'Arsenal 1-0 Chelsea \u00B7 HT',
      );
    });

    test('shows FT when finished', () {
      expect(
        liveMatchInfo(
          home: 'Arsenal',
          away: 'Chelsea',
          homeScore: 2,
          awayScore: 2,
          status: 'FT',
          clock: null,
        ),
        'Arsenal 2-2 Chelsea \u00B7 FT',
      );
    });

    test('says nothing before kickoff', () {
      expect(
        liveMatchInfo(
          home: 'Arsenal',
          away: 'Chelsea',
          homeScore: 0,
          awayScore: 0,
          status: '',
          clock: null,
        ),
        isNull,
      );
    });

    test('falls back to "v" when a score is missing', () {
      expect(
        liveMatchInfo(
          home: 'Arsenal',
          away: 'Chelsea',
          homeScore: null,
          awayScore: null,
          status: '1H',
          clock: "12'",
        ),
        "Arsenal v Chelsea \u00B7 12'",
      );
    });
  });

  group('hasInlineScore', () {
    test('detects a score already printed in the title', () {
      expect(hasInlineScore('Balagne 0 - 1 Montpellier'), isTrue);
      expect(hasInlineScore('LA Clippers 113-112 Oklahoma City'), isTrue);
    });

    test('is false for a scoreless fixture', () {
      expect(hasInlineScore('Israel vs Kosovo'), isFalse);
      expect(hasInlineScore('Arsenal vs Chelsea'), isFalse);
    });
  });

  group('liveCountdown', () {
    final now = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test('counts down in minutes, hours and days', () {
      expect(
        liveCountdown(now.millisecondsSinceEpoch + 12 * 60000, now),
        'in 12m',
      );
      expect(
        liveCountdown(now.millisecondsSinceEpoch + 95 * 60000, now),
        'in 1h 35m',
      );
      expect(
        liveCountdown(now.millisecondsSinceEpoch + 3 * 86400000, now),
        'in 3d',
      );
    });

    test('returns null once kickoff has passed', () {
      expect(liveCountdown(now.millisecondsSinceEpoch - 1000, now), isNull);
      expect(liveCountdown(now.millisecondsSinceEpoch, now), isNull);
    });
  });
}
