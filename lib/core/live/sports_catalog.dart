/// Sports league catalogue and fixture grouping.
///
/// The streams come from the providers, but a viewer thinks in leagues and
/// competitions, not in channel names. This maps a channel's live match
/// metadata onto a league so the Sports rail can group "what's on" by
/// competition, and so a league row can be found by name.
library;

/// One league or competition a fixture can belong to.
class SportsLeague {
  const SportsLeague({
    required this.id,
    required this.name,
    this.keywords = const [],
    this.emoji = '',
    this.priority = 100,
  });

  /// Stable slug, used as the rail's key.
  final String id;
  final String name;

  /// Alternative names a provider might print — "EPL", "Premier League",
  /// "English Premier League" all mean the same row.
  final List<String> keywords;
  final String emoji;

  /// Lower sorts first. Popular competitions lead the rail; the long tail
  /// follows in provider order.
  final int priority;

  /// True when [text] names this league, by name or by any alias. Case- and
  /// punctuation-insensitive, because provider titles are hand-typed.
  bool matches(String text) {
    final hay = normalise(text);
    if (hay.isEmpty) return false;
    if (hay.contains(normalise(name))) return true;
    for (final k in keywords) {
      final needle = normalise(k);
      if (needle.isNotEmpty && hay.contains(needle)) return true;
    }
    return false;
  }
}

/// Lowercase, strip punctuation, collapse whitespace. The one comparison the
/// whole file uses, so "Man Utd" and "man-utd" match.
String normalise(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// The catalogue, ordered by [SportsLeague.priority].
const List<SportsLeague> kSportsLeagues = [
  SportsLeague(
    id: 'football',
    name: 'Football',
    emoji: '⚽',
    priority: 0,
    keywords: ['soccer', 'footy'],
  ),
  SportsLeague(
    id: 'premier-league',
    name: 'Premier League',
    emoji: '🏴',
    priority: 1,
    keywords: ['epl', 'english premier', 'barclays'],
  ),
  SportsLeague(
    id: 'champions-league',
    name: 'Champions League',
    emoji: '🏆',
    priority: 2,
    keywords: ['uefa champions', 'ucl'],
  ),
  SportsLeague(
    id: 'la-liga',
    name: 'La Liga',
    emoji: '🇪🇸',
    priority: 3,
    keywords: ['laliga', 'spanish league'],
  ),
  SportsLeague(
    id: 'serie-a',
    name: 'Serie A',
    emoji: '🇮🇹',
    priority: 4,
    keywords: ['italian league'],
  ),
  SportsLeague(
    id: 'bundesliga',
    name: 'Bundesliga',
    emoji: '🇩🇪',
    priority: 5,
    keywords: ['german league'],
  ),
  SportsLeague(
    id: 'ligue-1',
    name: 'Ligue 1',
    emoji: '🇫🇷',
    priority: 6,
    keywords: ['french league'],
  ),
  SportsLeague(
    id: 'nba',
    name: 'NBA',
    emoji: '🏀',
    priority: 10,
    keywords: ['basketball'],
  ),
  SportsLeague(
    id: 'nfl',
    name: 'NFL',
    emoji: '🏈',
    priority: 11,
    keywords: ['american football'],
  ),
  SportsLeague(
    id: 'mlb',
    name: 'MLB',
    emoji: '⚾',
    priority: 12,
    keywords: ['baseball'],
  ),
  SportsLeague(
    id: 'nhl',
    name: 'NHL',
    emoji: '🏒',
    priority: 13,
    keywords: ['ice hockey', 'hockey'],
  ),
  SportsLeague(
    id: 'f1',
    name: 'Formula 1',
    emoji: '🏎️',
    priority: 14,
    keywords: ['formula one', 'f1', 'grand prix', 'motogp'],
  ),
  SportsLeague(
    id: 'tennis',
    name: 'Tennis',
    emoji: '🎾',
    priority: 15,
    keywords: ['atp', 'wta', 'wimbledon', 'us open', 'roland garros'],
  ),
  SportsLeague(
    id: 'cricket',
    name: 'Cricket',
    emoji: '🏏',
    priority: 16,
    keywords: ['ipl', 'test match', 't20'],
  ),
  SportsLeague(
    id: 'rugby',
    name: 'Rugby',
    emoji: '🏉',
    priority: 17,
    keywords: ['six nations', 'rugby union', 'rugby league'],
  ),
  SportsLeague(
    id: 'boxing',
    name: 'Boxing & MMA',
    emoji: '🥊',
    priority: 18,
    keywords: ['ufc', 'boxing', 'mma', 'fight night'],
  ),
  SportsLeague(
    id: 'golf',
    name: 'Golf',
    emoji: '⛳',
    priority: 19,
    keywords: ['pga', 'ryder cup', 'the open'],
  ),
  SportsLeague(
    id: 'olympics',
    name: 'Olympics',
    emoji: '🥇',
    priority: 20,
    keywords: ['olympic games', 'paralympics'],
  ),
];

/// The league a title belongs to, or null when nothing matches.
///
/// Checked most-specific first: "Premier League" also contains "football" as a
/// concept, so the ordering by priority means the named competition wins over
/// the generic sport.
SportsLeague? leagueFor(String text) {
  final hay = normalise(text);
  if (hay.isEmpty) return null;
  for (final league in kSportsLeagues) {
    if (league.matches(hay)) return league;
  }
  return null;
}

/// One fixture, as much as the provider told us.
class SportsFixture {
  const SportsFixture({
    required this.title,
    required this.league,
    this.channelName = '',
    this.channelId = '',
    this.start,
    this.isLive = false,
  });

  final String title;
  final SportsLeague league;
  final String channelName;
  final String channelId;
  final DateTime? start;
  final bool isLive;

  /// Sort key: live first, then soonest, then alphabetical.
  int compareTo(SportsFixture other) {
    if (isLive != other.isLive) return isLive ? -1 : 1;
    final a = start;
    final b = other.start;
    if (a != null && b != null && a != b) return a.compareTo(b);
    if (a != null && b == null) return -1;
    if (a == null && b != null) return 1;
    return title.toLowerCase().compareTo(other.title.toLowerCase());
  }
}

/// A league with its fixtures, ready to render as a rail.
class SportsGroup {
  const SportsGroup({required this.league, required this.fixtures});

  final SportsLeague league;
  final List<SportsFixture> fixtures;

  bool get hasLive => fixtures.any((f) => f.isLive);
}

/// Group [items] by league, dropping anything that doesn't read as sport.
///
/// Items carry a title, an optional channel, and optional start time; the
/// league is inferred from the title (and the channel, as a fallback — some
/// providers put the competition in the channel name). Groups are ordered
/// live-first, then by league priority, and fixtures within a group by
/// [SportsFixture.compareTo].
List<SportsGroup> groupFixtures(
  Iterable<({
    String title,
    String channelName,
    String channelId,
    DateTime? start,
    bool isLive,
  })>
  items,
) {
  final byLeague = <String, List<SportsFixture>>{};
  for (final item in items) {
    final league =
        leagueFor(item.title) ?? leagueFor(item.channelName);
    if (league == null) continue;
    byLeague.putIfAbsent(league.id, () => []).add(
      SportsFixture(
        title: item.title,
        league: league,
        channelName: item.channelName,
        channelId: item.channelId,
        start: item.start,
        isLive: item.isLive,
      ),
    );
  }

  final groups = <SportsGroup>[
    for (final entry in byLeague.entries)
      SportsGroup(
        league: kSportsLeagues.firstWhere((l) => l.id == entry.key),
        fixtures: entry.value..sort((a, b) => a.compareTo(b)),
      ),
  ];
  groups.sort((a, b) {
    if (a.hasLive != b.hasLive) return a.hasLive ? -1 : 1;
    return a.league.priority.compareTo(b.league.priority);
  });
  return groups;
}
