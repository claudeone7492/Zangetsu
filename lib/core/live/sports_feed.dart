import '../app_config.dart';
import '../models/media_item.dart';
import '../repository/source_repository.dart';
import 'sports_catalog.dart';

/// The sport the Sports destination is kept to. Every sports source carries a
/// dozen sports; the Sports screen is deliberately soccer (football) only, and
/// each source normalises its own vocabulary onto this slug
/// ([MediaItem.liveSport]), so the filter never matches league names.
const String kLiveSportsSport = 'soccer';

/// Fallback bucket for a soccer fixture whose title and metadata name no
/// league. Keeping these visible (rather than dropping them) means the Sports
/// screen never hides a live match just because a provider was vague.
const SportsLeague kOtherFootballLeague = SportsLeague(
  id: 'other-football',
  name: 'Other Football',
  emoji: '⚽',
  priority: 90,
);

/// One league row on the Sports screen.
class SportsSection {
  const SportsSection({required this.league, required this.items});

  final SportsLeague league;
  final List<MediaItem> items;

  int get liveCount => items.where(SportsFeed.isLive).length;
  bool get hasLive => liveCount > 0;
}

/// The live-sports feed shared by Live TV and the dedicated Sports screen.
///
/// Fixtures come from every installed sports provider's optional `getLive`
/// extension. The merge is best-effort: a missing source, a dead endpoint or a
/// fixture list older than the `liveSport` field contributes nothing rather
/// than sinking the page.
class SportsFeed {
  const SportsFeed._();

  static const Duration timeout = Duration(seconds: 10);

  static bool isLive(MediaItem item) =>
      (item.liveBadge ?? '').toUpperCase() == 'LIVE';

  static bool isFinished(MediaItem item) =>
      (item.liveBadge ?? '').toUpperCase() == 'FT';

  /// Every soccer fixture the installed sports sources publish, merged in
  /// [kLiveSportsSourceIds] order and ranked live → upcoming → finished.
  ///
  /// [playableOnly] preflights every in-play fixture through
  /// [SourceRepository.liveSources] and drops the ones no source can resolve.
  /// A provider can list a match as live while its stream endpoint returns
  /// nothing (or the broadcast has moved), and showing that row only sends the
  /// viewer into "No playable sources for this episode". Scheduled and finished
  /// rows are left alone: they never open the player.
  static Future<List<MediaItem>> fetch(
    SourceRepository repo, {
    bool playableOnly = false,
  }) async {
    final installed = kLiveSportsSourceIds.where(repo.hasSource).toList();
    if (installed.isEmpty) return const [];

    final perSource = await Future.wait([
      for (final id in installed)
        repo
            .live(sourceId: id)
            .timeout(timeout)
            .catchError((_) => const <MediaItem>[]),
    ]);

    final merged = <MediaItem>[];
    final seen = <String>{};
    for (final list in perSource) {
      for (final item in list) {
        if (item.liveSport != kLiveSportsSport) continue;
        if (item.liveUnplayable) continue;
        // Linear channels are not fixtures; they belong in Live TV, never in
        // the match centre's league sections.
        if (item.genres.any((g) => g.toLowerCase() == 'football channels')) {
          continue;
        }
        // The same fixture is usually carried by several sources. Keep the
        // first (highest-priority source) so the match centre does not show
        // duplicate rows for one game.
        if (!seen.add(_dedupeKey(item))) continue;
        merged.add(item);
      }
    }

    // Decorate-sort-undecorate: List.sort is not stable, and the sources'
    // order should survive ties.
    final indexed = merged.asMap().entries.toList();
    indexed.sort((a, b) {
      final byRank = rank(a.value).compareTo(rank(b.value));
      return byRank != 0 ? byRank : a.key.compareTo(b.key);
    });
    final sorted = [for (final entry in indexed) entry.value];
    return playableOnly ? _keepPlayable(repo, sorted) : sorted;
  }

  /// Resolve every in-play fixture and keep only those with at least one
  /// source. The work is capped at [_playableWorkers] at a time so a busy
  /// Saturday does not open dozens of provider requests at once, and each
  /// fixture is bounded by [_playableTimeout] so one dead endpoint cannot hold
  /// the whole page.
  static Future<List<MediaItem>> _keepPlayable(
    SourceRepository repo,
    List<MediaItem> items,
  ) async {
    final live = <int, MediaItem>{
      for (var i = 0; i < items.length; i++)
        if (isLive(items[i])) i: items[i],
    };
    if (live.isEmpty) return items;

    final entries = live.entries.toList();
    final playable = <int, bool>{};
    var next = 0;

    Future<void> worker() async {
      while (next < entries.length) {
        final entry = entries[next++];
        try {
          final sources = await repo
              .liveSources(
                entry.value.url,
                sourceId: entry.value.sourceId,
                title: entry.value.title,
              )
              .timeout(_playableTimeout);
          playable[entry.key] = sources.isNotEmpty;
        } catch (_) {
          playable[entry.key] = false;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < _playableWorkers && i < entries.length; i++) worker(),
    ]);

    return [
      for (var i = 0; i < items.length; i++)
        if (!live.containsKey(i) || playable[i] == true) items[i],
    ];
  }

  // A Saturday card can carry 15+ live fixtures. Four workers at 15s each made
  // the page feel stuck; the provider lists are cached now, so twelve workers
  // at four seconds keeps a normal card under one wave and a busy card under
  // two.
  static const int _playableWorkers = 12;
  static const Duration _playableTimeout = Duration(seconds: 4);

  /// A key that ignores the provider's spelling of the same fixture: accents,
  /// punctuation, "v"/"vs"/"@", a league prefix, a scoreline, and the order the
  /// two teams are printed in. Without the team sort, "Liverpool vs Man Utd"
  /// and "Man Utd @ Liverpool" would both survive and the page would show the
  /// same match twice.
  static String _dedupeKey(MediaItem item) {
    var key = normalise(item.title);
    final league = leagueFor(item.title);
    if (league != null) {
      final name = normalise(league.name);
      if (name.isNotEmpty && key.startsWith(name)) {
        key = key.substring(name.length).trim();
      }
    }

    final words =
        key
            .split(' ')
            .where((w) => w.isNotEmpty)
            .where((w) => !_scoreOrNoise.hasMatch(w))
            .where((w) => !_clubPrefixes.contains(w))
            .toList()
          ..sort();
    key = words.join(' ');

    final start = item.liveStartMs;
    if (start != null) {
      final day = DateTime.fromMillisecondsSinceEpoch(start).toLocal();
      key = '$key|${day.year}-${day.month}-${day.day}';
    }
    return key;
  }

  static final RegExp _scoreOrNoise = RegExp(
    r'^(\d+|vs|v|at|live|now|ft|ht|today|tomorrow|upcoming)$',
  );

  static const Set<String> _clubPrefixes = {
    'fc',
    'afc',
    'ac',
    'cf',
    'sc',
    'as',
    'ss',
    'ssc',
    'rc',
    'cd',
    'ud',
    'ca',
    'club',
    'the',
  };

  /// Live (0) → upcoming (1) → finished (2).
  static int rank(MediaItem item) {
    if (isLive(item)) return 0;
    if (isFinished(item)) return 2;
    return 1;
  }

  /// Group [items] into league sections, live leagues first and then by the
  /// catalogue's priority. Fixtures whose league cannot be inferred land in
  /// [kOtherFootballLeague] instead of disappearing.
  static List<SportsSection> group(Iterable<MediaItem> items) {
    final buckets = <String, List<MediaItem>>{};
    final leagues = <String, SportsLeague>{};

    for (final item in items) {
      final league = _leagueFor(item) ?? kOtherFootballLeague;
      leagues[league.id] = league;
      buckets.putIfAbsent(league.id, () => []).add(item);
    }

    final sections = <SportsSection>[
      for (final entry in buckets.entries)
        SportsSection(
          league: leagues[entry.key]!,
          items: entry.value..sort(compareItems),
        ),
    ];

    sections.sort((a, b) {
      if (a.hasLive != b.hasLive) return a.hasLive ? -1 : 1;
      final byPriority = a.league.priority.compareTo(b.league.priority);
      return byPriority != 0
          ? byPriority
          : a.league.name.compareTo(b.league.name);
    });
    return sections;
  }

  /// Fixtures in the order a viewer wants them: in play, then soonest, then
  /// alphabetical, with finished matches last.
  static int compareItems(MediaItem a, MediaItem b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;

    final aStart = a.liveStartMs;
    final bStart = b.liveStartMs;
    if (aStart != null && bStart != null && aStart != bStart) {
      return aStart.compareTo(bStart);
    }
    if (aStart != null && bStart == null) return -1;
    if (aStart == null && bStart != null) return 1;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }

  static SportsLeague? _leagueFor(MediaItem item) {
    // Providers put the competition in any of these places, so try them all
    // before giving up: title, the "competition · broadcaster" line, the
    // genres/tags list, and finally the broadcaster name.
    final candidates = [
      item.title,
      item.liveInfo ?? '',
      item.genres.join(' '),
      item.description ?? '',
    ];
    SportsLeague? generic;
    for (final text in candidates) {
      final league = leagueFor(text);
      if (league == null) continue;
      // "English Football League" and "Football League One" contain the
      // generic sport name, so the catalogue's Football row would swallow
      // them before the real competition gets a chance.
      if (league.id != 'football') return league;
      generic ??= league;
    }

    // The catalogue names the big competitions; the long tail (third tiers,
    // regional cups, women's and youth leagues) is only known to the provider.
    // Keep that name as its own row instead of folding every one of them into
    // "Other Football", which would make the page look like one giant bucket.
    final raw = _rawLeague(item);
    if (raw != null) {
      final slug = normalise(raw).replaceAll(' ', '-');
      if (slug.isNotEmpty) {
        return SportsLeague(
          id: 'provider-$slug',
          name: raw,
          emoji: '⚽',
          priority: 80,
        );
      }
    }
    return generic;
  }

  /// The competition a provider printed before its extra metadata, e.g.
  /// "Ekstraklasa · 2 feeds" or "Greek Super League".
  static String? _rawLeague(MediaItem item) {
    final info = item.liveInfo;
    if (info != null && info.trim().isNotEmpty) {
      final first = info.split(RegExp(r'\s*[·|•]\s*')).first.trim();
      if (first.isNotEmpty && !_notALeague.hasMatch(first)) return first;
    }
    for (final genre in item.genres) {
      final value = genre.trim();
      if (value.isNotEmpty && !_notALeague.hasMatch(value)) return value;
    }
    return null;
  }

  static final RegExp _notALeague = RegExp(
    r'^(\d{1,2}:\d{2}|live|ft|soon|today|tomorrow|upcoming|soccer|football|football channels)$',
    caseSensitive: false,
  );
}
