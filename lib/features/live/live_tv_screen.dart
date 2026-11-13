import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/models/home_section.dart';
import '../../core/models/media_item.dart';
import '../../core/playback/playback_prefs.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_back_button.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/tv/tv_poster_tile.dart';
import '../../core/tv/tv_text_field.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';
import '../detail/detail_screen.dart';
import '../home/home_screen_tv.dart';
import '../home/provider_browse_route.dart' show openProviderExtensionItem;
import '../search/browse_source_screen.dart' show canonicalTargetFor;

/// The bundled source that carries live channels. Shipped inside the app's own
/// pack (see `bundled_pack.dart`), so this page never has to ask the user to
/// install anything.
const String kLiveTvSourceId = 'iptv';

/// The sources that carry live sports fixtures. Each exposes them through its
/// optional `getLive` extension (a `live:`-scheme stream per fixture): MovieBox
/// leads with its own sports feed, StreamFree adds per-sport fixtures (24/7
/// channels plus matches). Both are asked in parallel and merged, in this
/// order, so an installed-but-empty source simply contributes nothing. A source
/// that isn't installed is skipped before the call.
const List<String> kLiveSportsSourceIds = <String>['moviebox', 'streamfree'];

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
class LiveTvScreen extends StatefulWidget {
  const LiveTvScreen({super.key, this.showBack = true});

  /// False when shown as the TV rail page — the rail owns navigation there, so
  /// the page's own Back affordance is suppressed (mirrors [DownloadsScreen]).
  final bool showBack;

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

  /// Live-sports fixtures from every installed sports source's `getLive`
  /// (empty when none is installed, has no `getLive`, or the feeds are down).
  /// Held apart from [_sections] because it is a second source, and only
  /// prepended to the rails as a synthetic "Live Sports" row when non-empty.
  List<MediaItem> _sports = const [];

  /// 0 = "All channels", otherwise an index into [_categories]. Applied to
  /// browse AND search, so the bar stays meaningful once a query is typed.
  int _category = 0;
  LiveSort _sort = LiveSort.defaultOrder;

  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;
  bool _searchFailed = false;
  List<MediaItem> _results = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  SourceRepository get _repo => sl<SourceRepository>();

  bool get _isTv => sl.isRegistered<AppMode>() && sl<AppMode>().isTv;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    // The sports feed is a second, optional source. Fetch it alongside the
    // channels so the two don't serialize, but never let it sink the page: a
    // missing MovieBox (or a dead sports endpoint) just yields no rail.
    final sportsFuture = _loadSports();
    try {
      final sections = await _repo
          .home(sourceId: kLiveTvSourceId)
          .timeout(_timeout);
      final sports = await sportsFuture;
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _sports = sports;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
        _sections = const [];
        _sports = const [];
      });
    }
  }

  /// Every installed sports source's fixtures, merged in
  /// [kLiveSportsSourceIds] order, or an empty list when none is installed or
  /// the feeds answer nothing. Best-effort by design: the IPTV channels are the
  /// page's reason to exist, sports are a bonus rail.
  ///
  /// In-play fixtures lead the rail, then upcoming ones, then finished ones —
  /// what a user can watch now should not sit under yesterday's results. The
  /// order within a rank is the sources' own, which is why the sort is done on
  /// decorated indices: `List.sort` is not stable, so sorting the items alone
  /// could shuffle two upcoming fixtures for no reason.
  Future<List<MediaItem>> _loadSports() async {
    final installed = kLiveSportsSourceIds.where(_repo.hasSource).toList();
    if (installed.isEmpty) return const [];
    final merged = <MediaItem>[];
    for (final id in installed) {
      try {
        merged.addAll(await _repo.live(sourceId: id).timeout(_timeout));
      } catch (_) {
        // One dead feed must not hide the others.
      }
    }
    final indexed = merged.asMap().entries.toList();
    indexed.sort((a, b) {
      final byRank = _liveRank(a.value).compareTo(_liveRank(b.value));
      return byRank != 0 ? byRank : a.key.compareTo(b.key);
    });
    return [for (final e in indexed) e.value];
  }

  /// 0 in play, 2 finished, 1 for everything else — an upcoming kickoff, or a
  /// 24/7 channel the source gives no kickoff at all.
  int _liveRank(MediaItem m) {
    final badge = m.liveBadge?.toUpperCase();
    if (badge == 'LIVE') return 0;
    if (badge == 'FT') return 2;
    return 1;
  }

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
    if (selected == null && _sports.isNotEmpty) {
      out.add(
        HomeSection(title: context.l10n.liveSports, items: _sorted(_sports)),
      );
    }
    for (final s in _sections) {
      if (s.items.isEmpty) continue;
      if (selected != null && s.title != selected) continue;
      out.add(HomeSection(title: s.title, items: _sorted(s.items)));
    }
    return out;
  }

  /// Search hits, narrowed by the same category selector and sort. The hits
  /// only carry a title/url — not the IPTV category they came from — so the
  /// category here is a title match, which is what a live channel name almost
  /// always carries anyway ("Sky Sports", "BBC News").
  List<MediaItem> get _visibleResults {
    final selected = _selectedCategory;
    final hits = selected == null
        ? _results
        : _results
              .where(
                (m) => m.title.toLowerCase().contains(selected.toLowerCase()),
              )
              .toList(growable: false);
    return _sorted(hits);
  }

  List<MediaItem> _sorted(List<MediaItem> items) => switch (_sort) {
    LiveSort.defaultOrder => items,
    LiveSort.nameAsc =>
      [...items]..sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      ),
    LiveSort.nameDesc =>
      [...items]..sort(
        (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
      ),
  };

  void _onCategoryChanged(int index) {
    if (index == _category) return;
    setState(() => _category = index);
  }

  void _onSortChanged(LiveSort sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    _debounce?.cancel();
    if (query == _query) return;
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
    try {
      final hits = await _repo
          .search(query, sourceId: kLiveTvSourceId)
          .timeout(_timeout);
      // A slower earlier query must never overwrite a newer one's results.
      if (!mounted || query != _query) return;
      setState(() {
        _results = hits;
        _searching = false;
        _searchFailed = false;
      });
    } catch (_) {
      if (!mounted || query != _query) return;
      setState(() {
        _results = const [];
        _searching = false;
        _searchFailed = true;
      });
    }
  }

  Future<void> _open(MediaItem item) async {
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

  @override
  Widget build(BuildContext context) =>
      _isTv ? _buildTv(context) : _buildPhone(context);

  // ── Phone layout ──────────────────────────────────────────────────────────

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
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
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
          const Icon(Icons.sort_rounded, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(
            _sort.label,
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

  Widget _phoneBrowse() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
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
            itemBuilder: (context, j) => PosterCard(
              title: section.items[j].title,
              imageUrl: section.items[j].cover,
              headers: section.items[j].coverHeaders,
              onTap: () => _open(section.items[j]),
              cellWidth: _phoneCardWidth,
            ),
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
      itemBuilder: (context, i) => PosterCard(
        title: results[i].title,
        imageUrl: results[i].cover,
        headers: results[i].coverHeaders,
        onTap: () => _open(results[i]),
      ),
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

  Widget _tvCategoryPill(int index, List<String> categories) {
    final selected = _category == index;
    final label = index == 0 ? context.l10n.all : categories[index - 1];
    return TvFocusable(
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
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: sections.length,
      itemBuilder: (_, i) => TvRail(
        section: sections[i],
        onTap: _open,
        firstAutofocus: i == 0,
      ),
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
      return _tvMessage(l10n.somethingWentWrong, retry: () => _runSearch(_query));
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
