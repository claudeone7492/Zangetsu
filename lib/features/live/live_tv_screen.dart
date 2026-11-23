import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/live/dvr_store.dart';
import '../../core/live/live_playlist_store.dart';
import '../../core/live/live_parental.dart';
import '../../core/live/sports_feed.dart';
import '../../core/live/epg_store.dart';
import '../../core/live/xtream_account_store.dart';
import '../../core/live/live_match_enrichment.dart';
import '../../core/live/live_match_format.dart';
import '../../core/models/episode.dart';
import '../../core/models/home_section.dart';
import '../../core/models/media_item.dart';
import '../../core/models/video_source.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/playback/resume_store.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_back_button.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/tv/tv_poster_tile.dart';
import '../../core/tv/tv_text_field.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/row_skeleton.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';
import '../detail/detail_screen.dart';
import '../../core/live/iptv_mark_store.dart';
import 'live_manage_screens.dart';
import 'live_tv_guide_screen.dart';
import 'live_playlists_screen.dart';
import 'live_parental_screen.dart';
import 'recordings_screen.dart';
import 'sports_screen.dart';
import 'xtream_accounts_screen.dart';
import '../player/player_screen.dart';
import '../home/home_screen_tv.dart';
import '../home/provider_browse_route.dart' show openProviderExtensionItem;
import '../search/browse_source_screen.dart' show canonicalTargetFor;

/// The bundled source that carries live channels. Shipped inside the app's own
/// pack (see `bundled_pack.dart`), so this page never has to ask the user to
/// install anything.
const String kLiveTvSourceId = 'iptv';

/// The sources that carry live sports fixtures. Each exposes them through its
/// optional `getLive` extension (a `live:`-family stream per fixture). The
/// list itself lives in [kLiveSportsSourceIds] (app_config) because the source
/// repository shares it for cross-provider resolution. The sport filter and
/// league grouping live in [SportsFeed].

/// Order the channel rows are shown in. "Default" keeps the catalogue's own
/// order (usually popularity), which is the only one that means anything for
/// live TV — the two alphabetical modes are for finding a known channel fast.
enum LiveSort {
  defaultOrder('Default'),
  nameAsc('A–Z'),
  nameDesc('Z–A');

  const LiveSort(this.label);

  final String label;
}

/// Live TV — the channels the bundled IPTV source is offering, laid out as
/// category rails, with a search field over the same catalogue.
///
/// A channel is a single always-on stream, so there is no season/episode
/// picker here: tapping one opens the same Detail the rest of the app uses,
/// where the live HLS is resolved and handed to the normal player. Reading the
/// catalogue through [SourceRepository] directly (not the router) keeps this
/// page on the source catalogue even in Z Mode, where the router would send
/// browsing to AniList/TMDB instead.
///
/// Phone and TV share this one screen (and its state), so a search typed on
/// one layout is preserved on the other; only the chrome and grid differ.
/// Entries in the Live TV overflow: the secondary pages that used to be
/// reachable only by knowing where they lived.
enum _LiveMenu { manage, onDemand, sports }

class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key, this.showBack = true});

  /// False when shown as the TV rail page — the rail owns navigation there, so
  /// the page's own Back affordance is suppressed (mirrors [DownloadsScreen]).
  final bool showBack;

  /// Warms the channel + sports list before the first open, so the very first
  /// tap on Live TV paints the channels instead of a spinner. Fire-and-forget
  /// from the app boot; a failure leaves the cache empty and the screen fetches
  /// on open as usual. A no-op once the cache is already populated.
  static Future<void> preload() => _LiveTvScreenState.preload();

  @override
  State<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends State<LiveTvScreen> {
  /// The IPTV index spans several playlists; give it room before calling it
  /// failed, but not so long that a dead network leaves the page spinning.
  static const Duration _timeout = Duration(seconds: 20);

  /// Coalesce keystrokes: the IPTV index is large, so a search per character
  /// would fire a dozen sweeps for one word.
  static const Duration _searchDebounce = Duration(milliseconds: 350);

  // Deliberately smaller than the 200×168 poster card the page shipped with:
  // a live channel is a logo, not cover art, so a denser rail shows more of
  // the catalogue at a glance. 3:2 landscape matches how channel art is shot.
  static const double _phoneCardWidth = 140;
  static const double _phoneCardHeight = 116;

  /// One extra column vs. the standard poster grid, for the same "smaller
  /// cards" reason — search hits are channels too.
  static const int _phoneSearchColumns = 4;

  double _phoneSearchCellWidth(BuildContext context) {
    const padding = 32.0;
    const spacing = 12.0;
    return (MediaQuery.sizeOf(context).width -
            padding -
            spacing * (_phoneSearchColumns - 1)) /
        _phoneSearchColumns;
  }

  bool _loading = true;
  bool _failed = false;
  List<HomeSection> _sections = const [];

  /// The channels + sports rows from the previous open, kept across instances
  /// so a re-open paints instantly instead of showing the spinner while the
  /// IPTV index (several large playlists) is fetched again. Refreshed in the
  /// background on every open, and dropped when a fetch fails so a stale list
  /// can never outlive the page's own error state.
  ///
  /// Tagged with the [SourceRepository] that produced it: the cache is only
  /// reused while that same repository is registered, so a swapped repository
  /// (or a fresh one per test) can never paint another one's channels.
  static List<HomeSection>? _cachedSections;
  static List<MediaItem>? _cachedSports;
  static SourceRepository? _cacheOwner;

  /// Live-sports fixtures from every installed sports source's `getLive`
  /// (empty when none is installed, has no `getLive`, or the feeds are down).
  /// Held apart from [_sections] because it is a second source, and only
  /// prepended to the rails as a synthetic "Live Sports" row when non-empty.
  List<MediaItem> _sports = const [];

  /// Parental controls. When set, channels above the household ceiling and
  /// explicitly hidden channels are dropped from every rail, and the sports
  /// fixtures are regrouped by competition instead of one flat row.
  LiveParental? _parental;

  /// Regroup [_sports] by league so the rail reads as competitions rather than
  /// one undifferentiated list.
  ///
  /// Only used when there is more than one league — otherwise the flat rail is
  /// kept. Fixtures whose league cannot be inferred land in the "Other
  /// Football" bucket, so grouping never hides a live match.
  List<HomeSection>? _sportsLeagues(List<MediaItem> sports) {
    final groups = SportsFeed.group(sports);
    if (groups.length < 2) return null;
    return [
      for (final group in groups)
        HomeSection(
          title: '${group.league.emoji} ${group.league.name}'.trim(),
          items: group.items,
        ),
    ];
  }

  /// Apply the parental ceiling to a rail's items.
  List<MediaItem> _parentalFilter(List<MediaItem> items) {
    final parental = _parental;
    if (parental == null || parental.isInactive) return items;
    // A listing's only rating signal is the catalogue's adult flag; providers
    // don't publish per-channel ratings in the channel list.
    return parental.filter(
      items,
      ratingOf: (i) => i.isAdult ? ContentRating.adult : ContentRating.unrated,
      channelIdOf: (i) => i.url,
    );
  }

  Future<void> _enrichSports(List<MediaItem> sports) async {
    if (sports.isEmpty) return;
    try {
      final enriched = await LiveMatchEnrichment(
        sl<Dio>(),
      ).enrich(sports).timeout(const Duration(seconds: 12));
      if (!mounted || !identical(_sports, sports)) return;
      setState(() => _sports = enriched);
    } catch (_) {
      // The rail already shows the sources' badges; a dead scoreboard is fine.
    }
  }

  /// Keeps an unstarted fixture's countdown honest while the rail is on screen.
  void _tickCountdowns() {
    final now = DateTime.now();
    var changed = false;
    final next = <MediaItem>[];
    for (final m in _sports) {
      final start = m.liveStartMs;
      final badge = m.liveBadge?.toUpperCase();
      if (start == null || badge == 'LIVE' || badge == 'FT') {
        next.add(m);
        continue;
      }
      final countdown = liveCountdown(start, now);
      if (countdown != null && countdown != m.liveBadge) {
        changed = true;
        next.add(m.copyWith(liveBadge: countdown));
      } else {
        next.add(m);
      }
    }
    if (changed) setState(() => _sports = next);
  }

  /// 0 = "All channels", otherwise an index into [_categories]. Applied to
  /// browse AND search, so the bar stays meaningful once a query is typed.
  int _category = 0;
  LiveSort _sort = LiveSort.defaultOrder;

  /// IPTV category keys, keyed by the section title the provider returns. The
  /// search passes the key to the source so it sweeps only that category's
  /// playlist; a user-imported group with a different name has no key and is
  /// filtered client-side instead.
  static const Map<String, String> _categoryKeys = {
    'animation': 'animation',
    'movies': 'movies',
    'series': 'series',
    'news': 'news',
    'sports': 'sports',
    'kids': 'kids',
    'documentary': 'documentary',
    'music': 'music',
  };

  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  bool _searchFailed = false;
  List<MediaItem> _results = const [];

  /// Bumped whenever a search is superseded (new query, new pill, cleared
  /// field). A slower earlier request checks this before writing its hits, so
  /// changing the category pill mid-search cannot paint the old pill's hits.
  int _searchGen = 0;

  /// Recomputes upcoming-fixture countdowns, so "in 12m" becomes "in 11m" as
  /// the page sits open rather than freezing at whatever the source returned.
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _parental = sl.isRegistered<LiveParental>() ? sl<LiveParental>() : null;
    _parental?.addListener(_onParentalChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _tickCountdowns(),
    );
  }

  void _onParentalChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _parental?.removeListener(_onParentalChanged);
    _debounce?.cancel();
    _countdownTimer?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  SourceRepository get _repo => sl<SourceRepository>();

  bool get _isTv => sl.isRegistered<AppMode>() && sl<AppMode>().isTv;

  /// Warms [_cachedSections] ahead of the first open, so the very first tap on
  /// Live TV paints the channels instead of a spinner. Fire-and-forget from the
  /// app boot; a failure leaves the cache null and the screen fetches normally.
  /// A no-op once the cache is already populated, so repeated calls are cheap.
  static Future<void> preload() async {
    if (!sl.isRegistered<SourceRepository>()) return;
    final repo = sl<SourceRepository>();
    if (_cacheOwner == repo && _cachedSections != null) return;
    try {
      final sports = await _fetchSports(repo);
      final sections = await repo
          .home(sourceId: kLiveTvSourceId)
          .timeout(_timeout);
      final imported = await _importedSections();
      _cachedSections = [...imported, ...sections];
      _cachedSports = sports;
      _cacheOwner = repo;
    } catch (_) {
      // Best-effort: the screen fetches on open if this never landed.
    }
  }

  /// The user's own playlists as Home rows. Empty when none are saved or a
  /// remote playlist is unreachable, so Live TV still paints the bundled
  /// catalogue.
  static Future<List<HomeSection>> _importedSections() async {
    if (!sl.isRegistered<LivePlaylistStore>()) return const [];
    try {
      return await sl<LivePlaylistStore>()
          .sections(sl<Dio>())
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return const [];
    }
  }

  static Future<List<MediaItem>> _localSearch(String query) async {
    if (!sl.isRegistered<LivePlaylistStore>()) return const [];
    try {
      return await sl<LivePlaylistStore>().search(query, sl<Dio>());
    } catch (_) {
      return const [];
    }
  }

  /// The cached rows, but only while they belong to [repo] — a repository swap
  /// invalidates them so a stale list is never painted over a new source.
  (List<HomeSection>, List<MediaItem>)? _cachedFor(SourceRepository repo) {
    if (_cacheOwner != repo || _cachedSections == null) return null;
    return (_cachedSections!, _cachedSports ?? const []);
  }

  Future<void> _load() async {
    final cached = _cachedFor(_repo);
    setState(() {
      // Paint the last-known channels immediately on a re-open; the fetch below
      // replaces them when it lands. No cache → the normal spinner.
      _loading = cached == null;
      _failed = false;
      if (cached != null) {
        _sections = cached.$1;
        _sports = cached.$2;
      }
    });
    // The sports feed is a second, optional source. Fetch it alongside the
    // channels so the two don't serialize, but never let it sink the page: a
    // missing MovieBox (or a dead sports endpoint) just yields no rail.
    final sportsFuture = _fetchSports(_repo);
    final importedFuture = _importedSections();
    try {
      final sections = await _repo
          .home(sourceId: kLiveTvSourceId)
          .timeout(_timeout);
      final sports = await sportsFuture;
      final imported = await importedFuture;
      if (!mounted) return;
      final merged = [...imported, ...sections];
      _cachedSections = merged;
      _cachedSports = sports;
      _cacheOwner = _repo;
      setState(() {
        _sections = merged;
        _sports = sports;
        _loading = false;
      });
      _enrichSports(sports);
    } catch (_) {
      if (!mounted) return;
      // Keep whatever cache painted rather than blanking the page: a transient
      // fetch failure on a re-open should not hide the channels the user was
      // just looking at. Only a first open with no cache shows the error state.
      if (cached != null) return;
      final imported = await importedFuture;
      if (imported.isNotEmpty) {
        setState(() {
          _sections = imported;
          _loading = false;
          _failed = false;
        });
        return;
      }
      setState(() {
        _failed = true;
        _loading = false;
        _sections = const [];
        _sports = const [];
      });
    }
  }

  /// Every installed sports source's soccer fixtures, merged in
  /// [kLiveSportsSourceIds] order, preflighted so only in-play rows with a
  /// resolvable stream survive, or an empty list when none is installed or the
  /// feeds answer nothing. Best-effort by design: the IPTV channels are the
  /// page's reason to exist, sports are a bonus rail.
  ///
  /// Static + repo-parameterised so the launch [preload] can run it before the
  /// screen exists.
  static Future<List<MediaItem>> _fetchSports(SourceRepository repo) =>
      SportsFeed.fetch(repo, playableOnly: true);

  /// Non-empty category names, in catalogue order. Index 0 of the selector is
  /// the synthetic "All channels"; the rest map here by `index - 1`.
  List<String> get _categories => [
    for (final s in _sections)
      if (s.items.isNotEmpty) s.title,
  ];

  /// The category the selector is on, or null for "All". Guarded against an
  /// out-of-range index so a reload that returns fewer categories can't throw.
  String? get _selectedCategory =>
      _category > 0 && _category <= _categories.length
      ? _categories[_category - 1]
      : null;

  /// The selected pill's IPTV category key, or null for "All" and for a
  /// user-imported group the bundled provider doesn't know.
  String? get _selectedCategoryKey {
    final selected = _selectedCategory;
    if (selected == null) return null;
    return _categoryKeys[selected.trim().toLowerCase()];
  }

  /// The rows the browse view actually paints, after the category filter and
  /// the chosen sort. Empty rows are dropped so a filter never leaves a
  /// titled-but-empty rail.
  ///
  /// The live-sports fixtures lead the default ("All") view as a synthetic
  /// rail — they are a second source, not an IPTV category, so picking a
  /// specific channel category drops them and focuses on channels.
  List<HomeSection> get _visibleSections {
    final selected = _selectedCategory;
    final out = <HomeSection>[];
    final visibleSports = _parentalFilter(_sports);
    if (selected == null) {
      if (visibleSports.isNotEmpty) {
        // Grouped by competition when the fixtures name one, else the flat rail.
        final leagues = _sportsLeagues(visibleSports);
        if (leagues != null) {
          out.addAll(leagues);
        } else {
          out.add(
            HomeSection(
              title: context.l10n.liveSports,
              items: _sorted(visibleSports),
            ),
          );
        }
      }
      for (final s in _sections) {
        if (s.items.isEmpty) continue;
        final items = _parentalFilter(s.items);
        if (items.isEmpty) continue;
        out.add(HomeSection(title: s.title, items: _sorted(items)));
      }
      return out;
    }

    // A selected pill is a focused category. Collect every channel that
    // belongs to it, not only the section whose title happens to match
    // byte-for-byte: imported playlists and IPTV both spell categories
    // differently ("News", "News HD", "news"), and an exact-title filter
    // left those pills looking broken (an empty grid for a category that
    // clearly had channels). Title matches are still preferred; item-level
    // matching is the fallback.
    final wanted = _normaliseCategory(selected);
    final items = <MediaItem>[];
    for (final s in _sections) {
      if (s.items.isEmpty) continue;
      final filtered = _parentalFilter(s.items);
      if (_normaliseCategory(s.title) == wanted) {
        items.addAll(filtered);
        continue;
      }
      items.addAll(filtered.where((i) => _matchesCategory(i, selected)));
    }
    if (items.isNotEmpty) {
      out.add(HomeSection(title: selected, items: _sorted(items)));
    }
    return out;
  }

  String _normaliseCategory(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Search hits, narrowed by the same category selector and sort. The hits
  /// only carry a title/url — not the IPTV category they came from — so the
  /// category here is a title match, which is what a live channel name almost
  /// always carries anyway ("Sky Sports", "BBC News").
  List<MediaItem> get _visibleResults {
    return _parentalFilter(_visibleResultsRaw);
  }

  List<MediaItem> get _visibleResultsRaw {
    final selected = _selectedCategory;
    final hits = selected == null
        ? _results
        : _results
              .where((m) => _matchesCategory(m, selected))
              .toList(growable: false);
    return _sorted(hits);
  }

  /// Whether [item] belongs to [category]. IPTV category hits carry the pill's
  /// title in `genres`; imported-playlist hits carry their `group-title` in
  /// `liveInfo`. Title containment is deliberately not used: "Sky Sports" is
  /// not in the "News" pill just because the word appears in another channel.
  bool _matchesCategory(MediaItem item, String category) {
    final wanted = _normaliseCategory(category);
    if (wanted.isEmpty) return true;
    final info = _normaliseCategory(item.liveInfo ?? '');
    if (info == wanted ||
        info.startsWith('$wanted ') ||
        info.endsWith(' $wanted') ||
        info.contains(' $wanted ')) {
      return true;
    }
    return item.genres.any((g) => _normaliseCategory(g) == wanted);
  }

  List<MediaItem> _sorted(List<MediaItem> items) => switch (_sort) {
    LiveSort.defaultOrder => items,
    LiveSort.nameAsc => [
      ...items,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())),
    LiveSort.nameDesc => [
      ...items,
    ]..sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase())),
  };

  void _onCategoryChanged(int index) {
    if (index == _category) return;
    setState(() => _category = index);
    if (_query.isNotEmpty) {
      _debounce?.cancel();
      setState(() {
        _searching = true;
        _searchFailed = false;
      });
      _runSearch(_query);
    }
  }

  void _onSortChanged(LiveSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    _debounce?.cancel();
    if (query == _query) return;
    // Invalidate any request still in flight for the previous text.
    _searchGen++;
    setState(() => _query = query);
    if (query.isEmpty) {
      setState(() {
        _searching = false;
        _searchFailed = false;
        _results = const [];
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchFailed = false;
    });
    _debounce = Timer(_searchDebounce, () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    final gen = ++_searchGen;
    final localFuture = _localSearch(query);
    try {
      final hits = await _repo
          .search(
            query,
            sourceId: kLiveTvSourceId,
            category: _selectedCategoryKey ?? '',
          )
          .timeout(_timeout);
      final local = await localFuture;
      // A slower earlier query or a previous category pill must never
      // overwrite the current search's results.
      if (!mounted || gen != _searchGen || query != _query) return;
      setState(() {
        _results = [...local, ...hits];
        _searching = false;
        _searchFailed = false;
      });
    } catch (_) {
      if (!mounted || gen != _searchGen || query != _query) return;
      setState(() {
        _results = const [];
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  /// Opens the EPG grid over the channels currently listed, resolving each
  /// channel to the guide's own channel id (a guide covers what it covers; an
  /// uncovered channel still lists, without a schedule).
  Future<void> _openGuide() async {
    final store = sl<EpgStore>();
    final rows = <EpgChannelRow>[];
    // The IPTV catalogue carries no `tvg-id` in its item shape — a channel is
    // `ch:<name>|<url>` — so the guide is matched on the display name, which
    // is what `EpgStore.resolveChannelId` falls back to anyway.
    for (final section in _sections) {
      for (final item in section.items) {
        rows.add(
          EpgChannelRow(
            name: item.title,
            logo: item.cover ?? '',
            channelId: store.resolveChannelId(displayName: item.title),
          ),
        );
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LiveTvGuideScreen(channels: rows),
      ),
    );
  }

  Future<void> _open(MediaItem item) async {
    if (item.sourceId == LivePlaylistStore.sourceId) {
      await _openImported(item);
      return;
    }
    // A live-sports match is a provider-extension handle (`live:` scheme), not
    // a title: it has no detail page, so it opens the player directly. IPTV
    // channels are ordinary items and fall through to the Detail route.
    if (await openProviderExtensionItem(context, item, repository: _repo)) {
      return;
    }
    final target = await canonicalTargetFor(item);
    if (!mounted) return;
    Navigator.of(context).push(DetailScreen.route(target ?? item));
  }

  /// An imported channel has no provider behind it, so its URL is the stream.
  /// Handing it straight to the player skips the detail route (which would
  /// have to resolve a source id that is not registered).
  Future<void> _openImported(MediaItem item) async {
    final episode = Episode(id: item.url, title: item.title, url: item.url);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          sourceId: LivePlaylistStore.sourceId,
          episodes: [episode],
          startIndex: 0,
          resume: sl<ResumeStore>(),
          resolveSources: (_) async => [
            VideoSource(
              url: item.url,
              quality: 'live',
              label: item.title,
              container: item.url.contains('.m3u8')
                  ? SourceContainer.hls
                  : SourceContainer.unknown,
            ),
          ],
          showTitle: item.title,
          cover: item.cover,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _isTv ? _buildTv(context) : _buildPhone(context);

  // ── Phone layout ──────────────────────────────────────────────────────────

  /// Catch-up / VOD entries, recognised by the source's category name — the
  /// catalogue carries no VOD marker, so a name match is the only signal.
  List<MediaItem> get _vodItems => [
    for (final section in _sections)
      if (RegExp(
        r'vod|movie|film|on\s*demand|catch',
        caseSensitive: false,
      ).hasMatch(section.title))
        ...section.items,
  ];

  Future<void> _onMenuSelected(_LiveMenu value) async {
    switch (value) {
      case _LiveMenu.manage:
        final playlists = sl.isRegistered<LivePlaylistStore>()
            ? sl<LivePlaylistStore>().entries.length
            : 0;
        final accounts = sl.isRegistered<XtreamAccountStore>()
            ? sl<XtreamAccountStore>()
            : null;
        await accounts?.ensureLoaded();
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LiveManageScreen(
              playlistCount: playlists,
              accountCount: accounts?.accounts.length ?? 0,
              onOpenPlaylists: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LivePlaylistsScreen(),
                ),
              ),
              onOpenAccounts: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const XtreamAccountsScreen(),
                ),
              ),
              onOpenGuide: _openGuide,
              onOpenParental: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LiveParentalScreen(),
                ),
              ),
            ),
          ),
        );
      case _LiveMenu.onDemand:
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => LiveOnDemandScreen(
              items: [
                for (final item in _vodItems)
                  LiveVodItem(
                    title: item.title,
                    poster: item.cover,
                    onPlay: () => _open(item),
                  ),
              ],
              onRefresh: _load,
            ),
          ),
        );
      case _LiveMenu.sports:
        await _openSports();
    }
  }

  /// Opens the dedicated football destination. Passing the fixtures already
  /// fetched by this page means the first frame paints matches instead of a
  /// skeleton; the screen still refreshes in the background.
  Future<void> _openSports() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SportsScreen(initialFixtures: _sports),
      ),
    );
  }

  /// A channel card with its star. The mark lives in [IptvMarkStore], so a
  /// playlist refresh never loses it.
  Widget _markable(MediaItem item, Widget card) {
    final marked = IptvMarkStore.isMarked(item.id);
    return Stack(
      children: [
        card,
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            onPressed: () async {
              await IptvMarkStore.toggle(item.id);
              if (mounted) setState(() {});
            },
            icon: Icon(
              marked ? Icons.star_rounded : Icons.star_border_rounded,
              color: marked ? AppColors.accent : Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhone(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 16),
            Icon(Icons.live_tv_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 8),
            Text(context.l10n.live, style: AppText.barTitle),
          ],
        ),
        actions: [
          if (sl.isRegistered<LivePlaylistStore>())
            IconButton(
              tooltip: context.l10n.livePlaylists,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LivePlaylistsScreen(),
                ),
              ),
              icon: const Icon(Icons.playlist_play_rounded),
            ),
          if (sl.isRegistered<XtreamAccountStore>())
            IconButton(
              tooltip: context.l10n.liveXtreamAccounts,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const XtreamAccountsScreen(),
                ),
              ),
              icon: const Icon(Icons.account_circle_outlined),
            ),
          if (sl.isRegistered<LiveParental>())
            IconButton(
              tooltip: 'Parental controls',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LiveParentalScreen(),
                ),
              ),
              icon: Icon(
                _parental?.isInactive == false
                    ? Icons.lock_rounded
                    : Icons.lock_open_rounded,
              ),
            ),
          if (sl.isRegistered<DvrStore>())
            IconButton(
              tooltip: 'Recordings & reminders',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RecordingsScreen(),
                ),
              ),
              icon: const Icon(Icons.fiber_manual_record_outlined),
            ),
          if (sl.isRegistered<EpgStore>())
            IconButton(
              tooltip: context.l10n.tvGuide,
              onPressed: _openGuide,
              icon: const Icon(Icons.calendar_month_rounded),
            ),
          PopupMenuButton<_LiveMenu>(
            tooltip: context.l10n.more,
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenuSelected,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _LiveMenu.manage,
                child: Text('Manage Live TV'),
              ),
              if (_vodItems.isNotEmpty)
                const PopupMenuItem(
                  value: _LiveMenu.onDemand,
                  child: Text('On demand'),
                ),
              if (_sports.isNotEmpty)
                const PopupMenuItem(
                  value: _LiveMenu.sports,
                  child: Text('Sports'),
                ),
            ],
          ),
          IconButton(
            tooltip: context.l10n.retry,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _queryController,
                  onChanged: _onQueryChanged,
                  textInputAction: TextInputAction.search,
                  style: AppText.body.copyWith(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: context.l10n.search,
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: context.l10n.retry,
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _queryController.clear();
                              _onQueryChanged('');
                            },
                          ),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              _phoneControlBar(),
            ],
          ),
        ),
      ),
      body: _query.isEmpty ? _phoneBrowse() : _phoneSearchResults(),
    );
  }

  /// The sub-header under the search bar: a horizontally scrollable category
  /// selector (All + one per IPTV category) followed by a compact sort button.
  /// Both filter the browse rails and the search hits.
  Widget _phoneControlBar() {
    final categories = _categories;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          _phoneSportsChip(),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
              itemCount: categories.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _phoneCategoryChip(i),
            ),
          ),
          _phoneSortButton(),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// The fixed Sports entry that leads the sub-header. It is a destination,
  /// not a channel filter, so it sits outside the indexed category chips and
  /// keeps its own key.
  Widget _phoneSportsChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
      child: Center(
        child: GestureDetector(
          key: const ValueKey('live-sports-chip'),
          onTap: _openSports,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.accent.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sports',
                  style: AppText.caption.copyWith(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.sports_soccer_rounded,
                  size: 13,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneCategoryChip(int index) {
    final selected = _category == index;
    final label = index == 0 ? context.l10n.all : _categories[index - 1];
    return Center(
      child: GestureDetector(
        key: ValueKey('live-category-$index'),
        onTap: () => _onCategoryChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: AppText.body.copyWith(
              color: selected ? Colors.black : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneSortButton() => PopupMenuButton<LiveSort>(
    key: const ValueKey('live-sort-button'),
    tooltip: context.l10n.sort,
    initialValue: _sort,
    onSelected: _onSortChanged,
    color: AppColors.surface,
    itemBuilder: (context) => [
      for (final s in LiveSort.values)
        PopupMenuItem(value: s, child: Text(s.label)),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.sort_rounded,
            size: 16,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            _sort.label,
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

  Widget _phoneChannelCard(MediaItem item) => _markable(
    item,
    PosterCard(
      title: item.title,
      logoItem: item,
      imageUrl: item.cover,
      headers: item.coverHeaders,
      genres: item.genres,
      liveBadge: item.liveBadge,
      liveInfo: item.liveInfo,
      liveUnplayable: item.liveUnplayable,
      onTap: () => _open(item),
    ),
  );

  /// A selected pill is a focused category, so its channels fill a grid
  /// instead of one long horizontal rail. The "All" view keeps the rails.
  Widget _phoneCategoryGrid(List<HomeSection> sections) {
    final items = [for (final section in sections) ...section.items];
    return CustomScrollView(
      key: const ValueKey('live-category-grid'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedCategory ?? '',
                    style: AppText.headline.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _phoneSearchColumns,
              childAspectRatio: posterCellAspect(
                _phoneSearchCellWidth(context),
                textScaler: MediaQuery.textScalerOf(context),
                wide: posterLayout(context) == PosterCardLayout.wide,
                titleInside: posterTitleInside(
                  context,
                  wide: posterLayout(context) == PosterCardLayout.wide,
                ),
              ),
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => _phoneChannelCard(items[i]),
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneBrowse() {
    if (_loading) {
      // Preloader, not a spinner: the page is warmed at boot (see [preload])
      // and this paints the shape of the channel rails it is about to fill, so
      // the first frame already reads as the finished page. A spinner in the
      // middle of an empty page is the "loading spinner" the prewarm exists to
      // avoid.
      return ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          RowSkeleton(itemWidth: _phoneCardWidth, itemHeight: _phoneCardHeight),
          RowSkeleton(itemWidth: _phoneCardWidth, itemHeight: _phoneCardHeight),
          RowSkeleton(itemWidth: _phoneCardWidth, itemHeight: _phoneCardHeight),
        ],
      );
    }
    if (_failed) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        message: context.l10n.somethingWentWrong,
        actionLabel: context.l10n.tryAgain,
        onAction: _load,
      );
    }
    final sections = _visibleSections;
    if (sections.isEmpty) {
      return EmptyState(
        icon: Icons.live_tv_outlined,
        message: context.l10n.noResults,
        actionLabel: context.l10n.tryAgain,
        onAction: _load,
      );
    }
    if (_selectedCategory != null) return _phoneCategoryGrid(sections);
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 96),
      itemCount: sections.length,
      itemBuilder: (context, i) {
        final section = sections[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ContentRow(
            title: section.title,
            itemCount: section.items.length,
            itemWidth: _phoneCardWidth,
            itemHeight: _phoneCardHeight,
            itemBuilder: (context, j) {
              final item = section.items[j];
              return _markable(
                item,
                PosterCard(
                  title: item.title,
                  logoItem: item,
                  imageUrl: item.cover,
                  headers: item.coverHeaders,
                  genres: item.genres,
                  // A live-sports match carries its status chip ("LIVE", a
                  // countdown, "FT") and its competition/clock line. Both are
                  // computed by the source and refined by `_enrichSports` /
                  // `_tickCountdowns`; without passing them here the rail showed
                  // bare posters and the enrichment had nowhere to land.
                  liveBadge: item.liveBadge,
                  liveInfo: item.liveInfo,
                  liveUnplayable: item.liveUnplayable,
                  onTap: () => _open(item),
                  cellWidth: _phoneCardWidth,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _phoneSearchResults() {
    if (_searching) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_searchFailed) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        message: context.l10n.somethingWentWrong,
        actionLabel: context.l10n.tryAgain,
        onAction: () => _runSearch(_query),
      );
    }
    final results = _visibleResults;
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        message: context.l10n.noResults,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _phoneSearchColumns,
        childAspectRatio: posterCellAspect(
          _phoneSearchCellWidth(context),
          textScaler: MediaQuery.textScalerOf(context),
          wide: posterLayout(context) == PosterCardLayout.wide,
          titleInside: posterTitleInside(
            context,
            wide: posterLayout(context) == PosterCardLayout.wide,
          ),
        ),
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) => _phoneChannelCard(results[i]),
    );
  }

  // ── TV layout ─────────────────────────────────────────────────────────────
  //
  // D-pad first: a focusable Back + search field in the header, then a
  // vertically-scrolling stack of horizontal poster rails (one per IPTV
  // category). A search replaces the rails with a focusable grid.

  Widget _buildTv(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showBack)
              TvBackHeader(
                titleWidget: Row(
                  children: [
                    Icon(
                      Icons.live_tv_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(l10n.live, style: AppText.largeTitle),
                  ],
                ),
                trailing: _tvSearchField(l10n),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.live_tv_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(l10n.live, style: AppText.largeTitle),
                    const Spacer(),
                    _tvSearchField(l10n),
                  ],
                ),
              ),
            _tvControlBar(l10n),
            Expanded(
              child: _query.isEmpty ? _tvBrowse(l10n) : _tvSearchResults(l10n),
            ),
          ],
        ),
      ),
    );
  }

  /// TV sub-header: the same category selector + sort as phone, but built from
  /// D-pad-focusable pills so a remote can drive it. Sits under the title row
  /// and above the rails.
  Widget _tvControlBar(AppLocalizations l10n) {
    final categories = _categories;
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: _tvSportsPill(l10n),
          ),
          for (var i = 0; i <= categories.length; i++)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: _tvCategoryPill(i, categories),
            ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 10),
            child: _tvSortPill(l10n),
          ),
        ],
      ),
    );
  }

  /// TV counterpart of the fixed Sports chip: the first focus stop in the
  /// sub-header, and the only one that opens a destination instead of
  /// filtering channels.
  Widget _tvSportsPill(AppLocalizations l10n) {
    return TvFocusable(
      variant: TvFocusVariant.pill,
      semanticLabel: l10n.liveSports,
      onTap: _openSports,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Sports',
              style: AppText.caption.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.sports_soccer_rounded,
              size: 14,
              color: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tvCategoryPill(int index, List<String> categories) {
    final selected = _category == index;
    final label = index == 0 ? context.l10n.all : categories[index - 1];
    return TvFocusable(
      key: ValueKey('live-category-$index'),
      variant: TvFocusVariant.pill,
      semanticLabel: label,
      onTap: () => _onCategoryChanged(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Text(
          label,
          style: AppText.button.copyWith(
            color: selected ? AppColors.textPrimary : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Cycles Default → A–Z → Z–A. A menu would be three focus stops for one
  /// value; a cycle keeps the remote's path short.
  Widget _tvSortPill(AppLocalizations l10n) {
    final next = LiveSort.values[(_sort.index + 1) % LiveSort.values.length];
    return TvFocusable(
      variant: TvFocusVariant.pill,
      semanticLabel: '${l10n.sort}: ${_sort.label}',
      onTap: () => _onSortChanged(next),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sort_rounded,
              size: 16,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              _sort.label,
              style: AppText.button.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tvSearchField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SizedBox(
        width: 340,
        child: TvTextField(
          controller: _queryController,
          onChanged: _onQueryChanged,
          onSubmitted: _runSearch,
          style: AppText.body,
          cursorColor: AppColors.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.search,
            hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  /// TV counterpart of the phone category grid: a D-pad-focusable grid for a
  /// selected pill, while "All" keeps the horizontal rails.
  Widget _tvCategoryGrid(List<HomeSection> sections) {
    final items = [for (final section in sections) ...section.items];
    return CustomScrollView(
      key: const ValueKey('live-category-grid'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 16),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedCategory ?? '',
                    style: AppText.headline.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${items.length}',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: tvPosterGridColumns(context),
              childAspectRatio: tvPosterGridAspect(context),
              crossAxisSpacing: 18,
              mainAxisSpacing: 22,
            ),
            delegate: SliverChildBuilderDelegate((_, i) {
              final item = items[i];
              return TvPosterTile(
                autofocus: i == 0,
                title: item.title,
                logoItem: item,
                imageUrl: item.cover,
                wideImageUrl: item.banner,
                headers: item.coverHeaders,
                genres: item.genres,
                isAdult: item.isAdult,
                scoreBadge: item.score,
                qualityBadge: item.quality,
                dubBadge: item.dubBadge,
                liveBadge: item.liveBadge,
                liveInfo: item.liveInfo,
                liveUnplayable: item.liveUnplayable,
                onTap: () => _open(item),
              );
            }, childCount: items.length),
          ),
        ),
      ],
    );
  }

  Widget _tvBrowse(AppLocalizations l10n) {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: SkeletonGrid(
          crossAxisCount: tvPosterGridColumns(context),
          childAspectRatio: tvPosterGridAspect(context),
        ),
      );
    }
    if (_failed) return _tvMessage(l10n.somethingWentWrong, retry: _load);
    final sections = _visibleSections;
    if (sections.isEmpty) return _tvMessage(l10n.noResults, retry: _load);
    if (_selectedCategory != null) return _tvCategoryGrid(sections);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: sections.length,
      itemBuilder: (_, i) =>
          TvRail(section: sections[i], onTap: _open, firstAutofocus: i == 0),
    );
  }

  Widget _tvSearchResults(AppLocalizations l10n) {
    if (_searching) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: SkeletonGrid(
          crossAxisCount: tvPosterGridColumns(context),
          childAspectRatio: tvPosterGridAspect(context),
        ),
      );
    }
    if (_searchFailed) {
      return _tvMessage(
        l10n.somethingWentWrong,
        retry: () => _runSearch(_query),
      );
    }
    final results = _visibleResults;
    if (results.isEmpty) return _tvMessage(l10n.noResults);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: tvPosterGridColumns(context),
        childAspectRatio: tvPosterGridAspect(context),
        crossAxisSpacing: 18,
        mainAxisSpacing: 22,
      ),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final item = results[i];
        return TvPosterTile(
          autofocus: i == 0,
          title: item.title,
          logoItem: item,
          imageUrl: item.cover,
          wideImageUrl: item.banner,
          headers: item.coverHeaders,
          genres: item.genres,
          isAdult: item.isAdult,
          scoreBadge: item.score,
          qualityBadge: item.quality,
          dubBadge: item.dubBadge,
          liveBadge: item.liveBadge,
          liveInfo: item.liveInfo,
          liveUnplayable: item.liveUnplayable,
          onTap: () => _open(item),
        );
      },
    );
  }

  /// D-pad-friendly message with an optional focusable Retry control. A plain
  /// [EmptyState] button is not reachable with a remote, so TV uses this.
  Widget _tvMessage(String message, {VoidCallback? retry}) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.headline.copyWith(color: AppColors.textSecondary),
        ),
        if (retry != null) ...[
          const SizedBox(height: 20),
          TvFocusable(
            autofocus: true,
            variant: TvFocusVariant.pill,
            semanticLabel: context.l10n.tryAgain,
            onTap: retry,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Text(
                context.l10n.tryAgain,
                style: AppText.button.copyWith(color: AppColors.textPrimary),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
