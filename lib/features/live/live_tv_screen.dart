import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/models/home_section.dart';
import '../../core/models/media_item.dart';
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
import '../search/browse_source_screen.dart' show canonicalTargetFor;

/// The bundled source that carries live channels. Shipped inside the app's own
/// pack (see `bundled_pack.dart`), so this page never has to ask the user to
/// install anything.
const String kLiveTvSourceId = 'iptv';

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

  bool _loading = true;
  bool _failed = false;
  List<HomeSection> _sections = const [];

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
    try {
      final sections = await _repo
          .home(sourceId: kLiveTvSourceId)
          .timeout(_timeout);
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
        _sections = const [];
      });
    }
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
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
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
        ),
      ),
      body: _query.isEmpty ? _phoneBrowse() : _phoneSearchResults(),
    );
  }

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
    final sections = _sections
        .where((s) => s.items.isNotEmpty)
        .toList(growable: false);
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
            itemWidth: 200,
            itemHeight: 168,
            itemBuilder: (context, j) => PosterCard(
              title: section.items[j].title,
              imageUrl: section.items[j].cover,
              headers: section.items[j].coverHeaders,
              onTap: () => _open(section.items[j]),
              cellWidth: 200,
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
    if (_results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        message: context.l10n.noResults,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: posterGridColumns(context),
        childAspectRatio: posterGridAspect(context),
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) => PosterCard(
        title: _results[i].title,
        imageUrl: _results[i].cover,
        headers: _results[i].coverHeaders,
        onTap: () => _open(_results[i]),
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
            Expanded(
              child: _query.isEmpty ? _tvBrowse(l10n) : _tvSearchResults(l10n),
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
    final sections = _sections
        .where((s) => s.items.isNotEmpty)
        .toList(growable: false);
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
    if (_results.isEmpty) return _tvMessage(l10n.noResults);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: tvPosterGridColumns(context),
        childAspectRatio: tvPosterGridAspect(context),
        crossAxisSpacing: 18,
        mainAxisSpacing: 22,
      ),
      itemCount: _results.length,
      itemBuilder: (_, i) {
        final item = _results[i];
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
