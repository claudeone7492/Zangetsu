import 'package:dio/dio.dart';

import '../logging/app_logger.dart';
import '../models/media_item.dart';
import 'live_match_format.dart';

/// Fills a live-sports card with what a scoreboard knows that the stream source
/// doesn't: the running score, the match clock, and half-time / full-time state.
///
/// The sports sources (StreamFree, MovieBox) list fixtures and stream them, but
/// say nothing about the score. TheSportsDB's keyless livescore feed is the
/// scoreboard here — one request per sport covers every in-play fixture, so the
/// whole rail enriches from a handful of calls rather than one per card. Results
/// are cached briefly: a rail re-sorts and re-paints far more often than a score
/// changes, and a live minute only needs to be roughly right.
///
/// Best-effort by design — a failed or slow scoreboard leaves the cards exactly
/// as the source rendered them (countdown / LIVE), never blocks the page.
class LiveMatchEnrichment {
  LiveMatchEnrichment(this._dio);

  final Dio _dio;

  static const String _base = 'https://www.thesportsdb.com/api/v1/json/123';

  /// The test key TheSportsDB publishes for development; it is unauthenticated
  /// and rate-limited, so results are cached hard and failures are swallowed.
  static const Duration _ttl = Duration(seconds: 30);

  final Map<String, _Board> _cache = {};

  /// Returns [items] with each live fixture's card enriched where a scoreboard
  /// row matches. Non-fixture items and unmatched fixtures pass through as-is.
  Future<List<MediaItem>> enrich(List<MediaItem> items) async {
    // Only cards a scoreboard can improve: a scoreless fixture title (so the
    // source hasn't already printed the score) whose league maps to a
    // scoreboard sport. MovieBox's "Home 2 - 1 Away" cards are left alone.
    final fixtures = items
        .where((m) => _sportFor(m) != null && !hasInlineScore(m.title))
        .toList(growable: false);
    if (fixtures.isEmpty) return items;

    final sports = <String>{for (final m in fixtures) _sportFor(m)!};
    final boards = <String, List<List<String>>>{};
    final rows = <String, List<Map<String, dynamic>>>{};
    await Future.wait(
      sports.map((s) async {
        final b = await _board(s);
        if (b != null) {
          boards[s] = b.rows;
          rows[s] = b.raw;
        }
      }),
    );

    final out = <MediaItem>[];
    for (final m in items) {
      final sport = _sportFor(m);
      final board = sport == null ? null : boards[sport];
      if (board == null || board.isEmpty) {
        out.add(m);
        continue;
      }
      final idx = bestFixtureMatch(m.title, board);
      if (idx < 0) {
        out.add(m);
        continue;
      }
      final row = rows[sport]![idx];
      final enriched = _apply(m, row);
      out.add(enriched ?? m);
    }
    return out;
  }

  /// Rewrites one card from a scoreboard row, or null when the row is an
  /// upcoming fixture (which the source already renders as a countdown).
  MediaItem? _apply(MediaItem m, Map<String, dynamic> row) {
    final status = (row['strStatus'] as String?)?.trim() ?? '';
    final progress = (row['strProgress'] as String?)?.trim() ?? '';
    final home = (row['strHomeTeam'] as String?)?.trim() ?? '';
    final away = (row['strAwayTeam'] as String?)?.trim() ?? '';
    final hs = int.tryParse('${row['intHomeScore']}');
    final as = int.tryParse('${row['intAwayScore']}');
    final clock = _clock(status, progress);
    final info = liveMatchInfo(
      home: home,
      away: away,
      homeScore: hs,
      awayScore: as,
      status: status,
      clock: clock,
    );
    if (info == null) return null;
    final live = kLiveStatuses.contains(status.toUpperCase());
    // A finished fixture is no longer live, so drop the live clock anchor —
    // otherwise the card keeps a countdown/ticker that no longer applies.
    return m.copyWith(
      liveBadge: live ? 'LIVE' : 'FT',
      liveInfo: info,
      clearLiveStart: !live,
    );
  }

  String? _clock(String status, String progress) {
    final s = status.toUpperCase();
    if (s == 'HT') return 'HT';
    if (s == 'FT') return null;
    if (s == '1H' || s == '2H') {
      return progress.isNotEmpty ? "$progress'" : s;
    }
    return progress.isNotEmpty ? "$progress'" : s;
  }

  /// The scoreboard's sport for a fixture, from the league the source tagged on
  /// it, or null when nothing matches a scoreboard this app can read. The map
  /// order matters: "Ice Hockey" is checked before "Hockey", "NCAA Men's
  /// Basketball" before the college-football keys, so the specific league wins.
  String? _sportFor(MediaItem m) {
    if (m.genres.isEmpty) return null;
    final tags = m.genres.map((g) => g.toLowerCase()).toList(growable: false);
    for (final e in _sportKeywords.entries) {
      for (final tag in tags) {
        if (e.value.any(tag.contains)) return e.key;
      }
    }
    return null;
  }

  /// One sport's livescore rows, cached for [_ttl]. The board keys are the
  /// fixtures the source exposes, so a non-football sport with no coverage
  /// simply returns an empty board and leaves those cards untouched.
  Future<_Board?> _board(String sport) async {
    final cached = _cache[sport];
    if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
      return cached;
    }
    try {
      final resp = await _dio.getUri<Map<String, dynamic>>(
        Uri.parse('$_base/livescore.php').replace(queryParameters: {'s': sport}),
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (c) => c != null && c < 500,
        ),
      );
      final raw = (resp.data?['livescore'] as List?) ?? const [];
      final rows = <List<String>>[];
      final maps = <Map<String, dynamic>>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final map = e.cast<String, dynamic>();
        rows.add([
          '${map['strHomeTeam'] ?? ''}',
          '${map['strAwayTeam'] ?? ''}',
        ]);
        maps.add(map);
      }
      final board = _Board(DateTime.now(), rows, maps);
      _cache[sport] = board;
      return board;
    } catch (e) {
      AppLogger.instance.log(
        '[live] scoreboard "$sport" unavailable: $e',
        level: 'W',
      );
      // Cache the miss briefly too, so a rail repaint doesn't hammer a dead
      // endpoint once per frame.
      _cache[sport] = _Board(DateTime.now(), const [], const []);
      return null;
    }
  }
}

/// League-name keyword → TheSportsDB sport. Ordered so a more specific league
/// is not shadowed by a looser one: "Ice Hockey" before "Hockey", "NCAA Men's
/// Basketball" before the college-football keys ("NCAAF" carries neither
/// "football" nor "soccer", so it needs its own entry).
const Map<String, List<String>> _sportKeywords = {
  'Ice Hockey': ['nhl', 'ice hockey', 'hockey'],
  'Basketball': ['nba', 'basketball', 'euroleague'],
  'American Football': ['nfl', 'american football', 'ncaaf', 'college football'],
  'Baseball': ['mlb', 'baseball'],
  'Soccer': [
    'soccer',
    'football',
    'premier league',
    'laliga',
    'la liga',
    'serie a',
    'bundesliga',
    'ligue 1',
    'uefa',
    'champions league',
    'europa',
    'eredivisie',
    'mls',
  ],
  'Tennis': ['tennis', 'atp', 'wta'],
  'Cricket': ['cricket', 'ipl'],
};

class _Board {
  _Board(this.at, this.rows, this.raw);
  final DateTime at;
  final List<List<String>> rows;
  final List<Map<String, dynamic>> raw;
}
