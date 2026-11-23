import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/live/live_match_enrichment.dart';
import '../../core/live/live_match_format.dart';
import '../../core/live/sports_catalog.dart';
import '../../core/live/sports_feed.dart';
import '../../core/models/media_item.dart';
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_back_button.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';
import '../home/provider_browse_route.dart' show openProviderExtensionItem;

/// The football match centre.
///
/// A fixture-first page in the shape of a live-score app: in-play matches lead,
/// then today, tomorrow and the rest of the schedule, each day broken into its
/// leagues. Only playable soccer fixtures are shown; linear sports channels are
/// deliberately excluded (they belong in Live TV, not here).
class SportsScreen extends StatefulWidget {
  const SportsScreen({
    super.key,
    this.initialFixtures = const [],
    this.showBack = true,
  });

  /// Fixtures already fetched by Live TV. They paint immediately; a fresh
  /// fetch still runs so the page never shows a stale kickoff.
  final List<MediaItem> initialFixtures;

  /// False when the TV rail owns navigation and the page's own Back control
  /// would be redundant.
  final bool showBack;

  @override
  State<SportsScreen> createState() => _SportsScreenState();
}

enum _SportsView { all, live, today, tomorrow }

class _SportsScreenState extends State<SportsScreen> {
  SourceRepository? _repo;
  List<MediaItem> _fixtures = const [];
  bool _loading = true;
  bool _failed = false;
  _SportsView _view = _SportsView.all;
  Timer? _ticker;

  bool get _isTv => sl.isRegistered<AppMode>() && sl<AppMode>().isTv;

  @override
  void initState() {
    super.initState();
    _repo = sl.isRegistered<SourceRepository>() ? sl<SourceRepository>() : null;
    if (widget.initialFixtures.isNotEmpty) {
      _fixtures = widget.initialFixtures;
      _loading = false;
    }
    _refresh(silent: widget.initialFixtures.isNotEmpty);
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(_tickCountdowns);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    final repo = _repo;
    if (repo == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      var items = await SportsFeed.fetch(repo);
      if (!mounted) return;
      setState(() {
        _fixtures = items;
        _loading = false;
        _failed = false;
      });
      items = await _enrich(items);
      if (!mounted) return;
      setState(() => _fixtures = items);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = _fixtures.isEmpty;
      });
    }
  }

  Future<List<MediaItem>> _enrich(List<MediaItem> items) async {
    if (items.isEmpty || !sl.isRegistered<Dio>()) return items;
    try {
      return await LiveMatchEnrichment(
        sl<Dio>(),
      ).enrich(items).timeout(const Duration(seconds: 12));
    } catch (_) {
      return items;
    }
  }

  void _tickCountdowns() {
    final now = DateTime.now();
    _fixtures = [
      for (final item in _fixtures)
        if (item.liveStartMs != null &&
            !SportsFeed.isLive(item) &&
            !SportsFeed.isFinished(item) &&
            liveCountdown(item.liveStartMs!, now) != null)
          item.copyWith(liveBadge: liveCountdown(item.liveStartMs!, now))
        else
          item,
    ];
  }

  Future<void> _open(MediaItem item) async {
    final repo = _repo;
    if (repo == null) return;
    await openProviderExtensionItem(context, item, repository: repo);
  }

  @override
  Widget build(BuildContext context) {
    return _isTv ? _buildTv(context) : _buildPhone(context);
  }

  // ── Phone ────────────────────────────────────────────────────────────────

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
            Icon(
              Icons.sports_soccer_rounded,
              color: AppColors.accent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(context.l10n.liveSports, style: AppText.barTitle),
          ],
        ),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            onPressed: _loading ? null : () => _refresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        color: AppColors.accent,
        child: _content(context),
      ),
    );
  }

  // ── TV ───────────────────────────────────────────────────────────────────

  Widget _buildTv(BuildContext context) {
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
                      Icons.sports_soccer_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(context.l10n.liveSports, style: AppText.largeTitle),
                  ],
                ),
                trailing: TvFocusable(
                  variant: TvFocusVariant.pill,
                  onTap: () {
                    if (!_loading) _refresh();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(context.l10n.retry, style: AppText.body),
                      ],
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.sports_soccer_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(context.l10n.liveSports, style: AppText.largeTitle),
                  ],
                ),
              ),
            Expanded(child: _content(context, tv: true)),
          ],
        ),
      ),
    );
  }

  // ── Content ──────────────────────────────────────────────────────────────

  Widget _content(BuildContext context, {bool tv = false}) {
    if (_loading && _fixtures.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(tv ? 24 : 16, 8, tv ? 24 : 16, 96),
        physics: const NeverScrollableScrollPhysics(),
        children: const [_LoadingCard(), _LoadingCard(), _LoadingCard()],
      );
    }
    if (_failed && _fixtures.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        message: context.l10n.somethingWentWrong,
        actionLabel: context.l10n.tryAgain,
        onAction: () => _refresh(),
      );
    }

    final sections = _buildSections(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(child: _AmbientBackdrop(tv: tv)),
        ),
        ListView(
          padding: EdgeInsets.fromLTRB(
            tv ? 28 : 16,
            tv ? 8 : 6,
            tv ? 28 : 16,
            110,
          ),
          children: [
            _summaryCard(context, tv: tv),
            const SizedBox(height: 16),
            _filterBar(context, tv: tv),
            const SizedBox(height: 6),
            if (sections.isEmpty) _emptyView(context) else ...sections,
          ],
        ),
      ],
    );
  }

  List<Widget> _buildSections(BuildContext context) {
    final live = _fixtures.where(SportsFeed.isLive).toList();
    final finished = _fixtures.where(SportsFeed.isFinished).toList();
    final scheduled = _fixtures
        .where((m) => !SportsFeed.isLive(m) && !SportsFeed.isFinished(m))
        .toList();

    final byDay = <DateTime, List<MediaItem>>{};
    final tbc = <MediaItem>[];
    for (final item in scheduled) {
      final start = item.liveStartMs;
      if (start == null) {
        tbc.add(item);
        continue;
      }
      final dt = DateTime.fromMillisecondsSinceEpoch(start).toLocal();
      final day = _dayOf(dt);
      byDay.putIfAbsent(day, () => []).add(item);
    }

    final today = _dayOf(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    final out = <Widget>[];

    void addLive() {
      if (live.isEmpty) return;
      out.add(
        _sectionHeader(
          'LIVE NOW',
          count: live.length,
          live: true,
          subtitle: 'In play right now',
        ),
      );
      out.addAll(_leagueBlocks(live));
    }

    void addDay(DateTime day, String title, {String? subtitle}) {
      final items = byDay[day];
      if (items == null || items.isEmpty) return;
      out.add(
        _sectionHeader(
          title,
          count: items.length,
          subtitle: subtitle ?? _longDate(day),
        ),
      );
      out.addAll(_leagueBlocks(items));
    }

    switch (_view) {
      case _SportsView.live:
        addLive();
      case _SportsView.today:
        addLive();
        addDay(today, 'TODAY', subtitle: _longDate(today));
      case _SportsView.tomorrow:
        addDay(tomorrow, 'TOMORROW', subtitle: _longDate(tomorrow));
      case _SportsView.all:
        addLive();
        addDay(today, 'TODAY', subtitle: _longDate(today));
        addDay(tomorrow, 'TOMORROW', subtitle: _longDate(tomorrow));
        final later = byDay.keys.where((d) => d.isAfter(tomorrow)).toList()
          ..sort();
        for (final day in later) {
          addDay(day, _dayName(day).toUpperCase(), subtitle: _longDate(day));
        }
        if (tbc.isNotEmpty) {
          out.add(_sectionHeader('DATE TO BE CONFIRMED', count: tbc.length));
          out.addAll(_leagueBlocks(tbc));
        }
        if (finished.isNotEmpty) {
          out.add(
            _sectionHeader(
              'RESULTS',
              count: finished.length,
              subtitle: 'Recent finishes',
            ),
          );
          out.addAll(_leagueBlocks(finished));
        }
    }
    return out;
  }

  Widget _emptyView(BuildContext context) {
    final (message, action, onAction) = switch (_view) {
      _SportsView.live => (
        'No football matches are in play right now.',
        'Show the full schedule',
        () => setState(() => _view = _SportsView.all),
      ),
      _SportsView.today => (
        'No more football scheduled today.',
        'Show upcoming days',
        () => setState(() => _view = _SportsView.all),
      ),
      _SportsView.tomorrow => (
        'No football scheduled tomorrow.',
        'Show all fixtures',
        () => setState(() => _view = _SportsView.all),
      ),
      _SportsView.all => (
        'No football fixtures are available right now.',
        context.l10n.tryAgain,
        () => _refresh(),
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: EmptyState(
        icon: Icons.sports_soccer_outlined,
        message: message,
        actionLabel: action,
        onAction: onAction,
      ),
    );
  }

  // ── Summary + filters ────────────────────────────────────────────────────

  Widget _summaryCard(BuildContext context, {bool tv = false}) {
    final live = _fixtures.where(SportsFeed.isLive).length;
    final today = _fixtures.where((m) {
      if (SportsFeed.isLive(m) || SportsFeed.isFinished(m)) return false;
      final s = m.liveStartMs;
      if (s == null) return false;
      return _dayOf(DateTime.fromMillisecondsSinceEpoch(s).toLocal()) ==
          _dayOf(DateTime.now());
    }).length;
    final finished = _fixtures.where(SportsFeed.isFinished).length;
    final upcoming = _fixtures.length - live - today - finished;

    return _GlassPanel(
      margin: EdgeInsets.only(top: tv ? 4 : 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      radius: 24,
      tint: AppColors.surface,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.accent.withValues(alpha: 0.24),
          AppColors.surface.withValues(alpha: 0.18),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _LiveDot(size: 6),
                    const SizedBox(width: 6),
                    Text(
                      'MATCH CENTRE',
                      style: AppText.caption.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.16),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.26),
                  ),
                ),
                child: Icon(
                  Icons.sports_soccer_rounded,
                  color: AppColors.accent,
                  size: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Live football,\narranged by league.',
            style: AppText.largeTitle.copyWith(fontSize: 28, height: 1.05),
          ),
          const SizedBox(height: 6),
          Text(
            'Every fixture from your six sports sources, with the league and '
            'kickoff already sorted.',
            style: AppText.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricPill(value: '$live', label: 'Live', accent: true),
              _MetricPill(value: '$today', label: 'Today'),
              _MetricPill(value: '$upcoming', label: 'Upcoming'),
              _MetricPill(value: '$finished', label: 'Results'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterBar(BuildContext context, {bool tv = false}) {
    final live = _fixtures.where(SportsFeed.isLive).length;
    final today = _countFor(_SportsView.today);
    final tomorrow = _countFor(_SportsView.tomorrow);
    final chips = <(String, IconData, _SportsView, int)>[
      ('All', Icons.grid_view_rounded, _SportsView.all, _fixtures.length),
      ('Live', Icons.bolt_rounded, _SportsView.live, live),
      ('Today', Icons.today_rounded, _SportsView.today, today),
      ('Tomorrow', Icons.wb_twilight_rounded, _SportsView.tomorrow, tomorrow),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (label, icon, view, count) = chips[i];
          final selected = _view == view;
          final chip = _FilterPill(
            icon: icon,
            label: label,
            count: count,
            selected: selected,
          );
          return tv
              ? TvFocusable(
                  key: ValueKey('sports-filter-${view.name}'),
                  variant: TvFocusVariant.pill,
                  onTap: () => setState(() => _view = view),
                  child: chip,
                )
              : GestureDetector(
                  key: ValueKey('sports-filter-${view.name}'),
                  onTap: () => setState(() => _view = view),
                  child: chip,
                );
        },
      ),
    );
  }

  int _countFor(_SportsView view) {
    final today = _dayOf(DateTime.now());
    final tomorrow = today.add(const Duration(days: 1));
    return _fixtures.where((m) {
      if (view == _SportsView.all) return true;
      if (SportsFeed.isLive(m)) return view == _SportsView.today;
      if (SportsFeed.isFinished(m)) return false;
      final s = m.liveStartMs;
      if (s == null) return false;
      final day = _dayOf(DateTime.fromMillisecondsSinceEpoch(s).toLocal());
      return switch (view) {
        _SportsView.today => day == today,
        _SportsView.tomorrow => day == tomorrow,
        _ => true,
      };
    }).length;
  }

  // ── Sections ─────────────────────────────────────────────────────────────

  Widget _sectionHeader(
    String title, {
    int? count,
    String? subtitle,
    bool live = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 3,
            height: live ? 28 : 22,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  live ? AppColors.accent : AppColors.textTertiary,
                  live
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : Colors.transparent,
                ],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          if (live) ...[_LiveDot(size: 7), const SizedBox(width: 7)],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.headline.copyWith(
                  fontSize: live ? 15 : 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: live ? 1.1 : 0.2,
                  color: live ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (count != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.hairline),
              ),
              child: Text(
                '$count ${count == 1 ? 'match' : 'matches'}',
                style: AppText.caption.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _leagueBlocks(List<MediaItem> items) {
    final sections = SportsFeed.group(items);
    return [for (final section in sections) _leagueCard(section)];
  }

  Widget _leagueCard(SportsSection section) {
    return _GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      radius: 20,
      tint: AppColors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.accent.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Text(
                    section.league.emoji,
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    section.league.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.headline.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (section.hasLive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LiveDot(size: 5),
                        const SizedBox(width: 5),
                        Text(
                          '${section.liveCount} LIVE',
                          style: AppText.caption.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface2.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${section.items.length}',
                      style: AppText.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.hairline),
          for (var i = 0; i < section.items.length; i++) ...[
            _matchRow(section.items[i], section.league),
            if (i != section.items.length - 1)
              Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: AppColors.hairline,
              ),
          ],
        ],
      ),
    );
  }

  Widget _matchRow(MediaItem item, SportsLeague league) {
    final row = _MatchRow(item: item, league: league, onTap: () => _open(item));
    if (!_isTv) return row;
    return TvFocusable(
      variant: TvFocusVariant.float,
      onTap: () => _open(item),
      borderRadius: 12,
      child: row,
    );
  }
}

/// One fixture line inside a league card.
class _MatchRow extends StatelessWidget {
  const _MatchRow({
    required this.item,
    required this.league,
    required this.onTap,
  });

  final MediaItem item;
  final SportsLeague league;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = SportsFeed.isLive(item);
    final finished = SportsFeed.isFinished(item);
    final clock = _clock(item);
    final score = _score(item);
    final teams = _teams(item.title, league);
    final info = _infoLine(item, league);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 11, 12, 11),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 3,
                height: 40,
                margin: const EdgeInsets.only(right: 9),
                decoration: BoxDecoration(
                  color: live
                      ? AppColors.accent
                      : AppColors.hairline.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                  boxShadow: live
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
              ),
              Container(
                width: 52,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: live
                      ? AppColors.accent.withValues(alpha: 0.10)
                      : AppColors.surface2.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _StatusColumn(
                  live: live,
                  finished: finished,
                  kickoff: _kickoff(item),
                  clock: clock,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (teams != null) ...[
                      _teamLine(teams.$1),
                      const SizedBox(height: 3),
                      _teamLine(teams.$2),
                    ] else
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 1.25,
                        ),
                      ),
                    if (info != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        info,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (score != null) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: live
                        ? LinearGradient(
                            colors: [
                              AppColors.accent,
                              Color.lerp(AppColors.accent, Colors.white, 0.3)!,
                            ],
                          )
                        : null,
                    color: live ? null : AppColors.surface2,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: live
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.25),
                              blurRadius: 12,
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    '${score.$1} - ${score.$2}',
                    style: AppText.headline.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: live ? Colors.black : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 10),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: live
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.accent,
                            Color.lerp(AppColors.accent, Colors.white, 0.3)!,
                          ],
                        )
                      : null,
                  color: live ? null : AppColors.surface2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: live
                        ? Colors.transparent
                        : AppColors.hairline.withValues(alpha: 0.8),
                  ),
                  boxShadow: live
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.30),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: live ? Colors.black : AppColors.textPrimary,
                  size: 21,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamLine(String name) {
    return Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppText.body.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        height: 1.2,
      ),
    );
  }

  /// Split "Home vs Away" into the two team lines a match centre shows. Titles
  /// that do not name two sides (a race, a channel, "TBC") stay on one line.
  (String, String)? _teams(String raw, SportsLeague league) {
    var title = raw.trim();
    final colon = title.indexOf(':');
    if (colon > 0 && colon < 48) {
      final prefix = title.substring(0, colon).toLowerCase();
      if (league.name.toLowerCase().contains(prefix) ||
          prefix.contains(league.name.toLowerCase())) {
        title = title.substring(colon + 1).trim();
      }
    }
    for (final sep in const [' vs. ', ' vs ', ' v ', ' VS ', ' Vs ']) {
      final idx = title.toLowerCase().indexOf(sep.toLowerCase());
      if (idx > 0) {
        final home = title.substring(0, idx).trim();
        final away = title.substring(idx + sep.length).trim();
        if (home.isNotEmpty && away.isNotEmpty) return (home, away);
      }
    }
    final dash = title.indexOf(' - ');
    if (dash > 0) {
      final home = title.substring(0, dash).trim();
      final away = title.substring(dash + 3).trim();
      // A dash between two numbers is a score, not a team separator.
      if (home.isNotEmpty &&
          away.isNotEmpty &&
          !RegExp(r'\d$').hasMatch(home) &&
          !RegExp(r'^\d').hasMatch(away)) {
        return (home, away);
      }
    }
    return null;
  }

  /// A "competition · broadcaster" line, minus the score/clock that the row
  /// already renders. Enrichment replaces `liveInfo` with
  /// "Home 1-0 Away · 63'", which would just repeat the team lines, so that
  /// shape is dropped.
  String? _infoLine(MediaItem item, SportsLeague league) {
    var info = (item.liveInfo ?? '').trim();
    if (info.isEmpty) return null;
    if (RegExp(r'\d\s*[-–:v]\s*\d', caseSensitive: false).hasMatch(info) &&
        info.contains('·')) {
      return null;
    }
    // The league header already names the competition, and the status column
    // already shows the clock, so neither belongs on the info line.
    if (info.toLowerCase().startsWith(league.name.toLowerCase())) {
      info = info.substring(league.name.length);
      info = info.replaceFirst(RegExp(r'^\s*[·|:\-–]\s*'), '');
    }
    info = info
        .replaceAll(RegExp(r"\b\d{1,3}'"), '')
        .replaceAll(RegExp(r'\b(HT|FT|LIVE)\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*[·|]\s*'), ' · ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[·|:\-–\s]+|[·|:\-–\s]+$'), '')
        .trim();
    return info.isEmpty ? null : info;
  }

  static String? _clock(MediaItem item) {
    final info = item.liveInfo ?? '';
    final minute = RegExp(r"(\d{1,3})'").firstMatch(info);
    if (minute != null) return "${minute.group(1)}'";
    if (RegExp(r'\bHT\b').hasMatch(info)) return 'HT';
    return null;
  }

  static (int, int)? _score(MediaItem item) {
    final pattern = RegExp(r'(?<![\d-])(\d{1,2})\s*[-–:]\s*(\d{1,2})(?![\d-])');
    (int, int)? parse(String text) {
      final m = pattern.firstMatch(text);
      if (m == null) return null;
      final a = int.tryParse(m.group(1)!);
      final b = int.tryParse(m.group(2)!);
      if (a == null || b == null) return null;
      // A 4-digit year next to a dash is a date, not a scoreline.
      if (a > 9 && b > 9) return null;
      return (a, b);
    }

    return parse(item.liveInfo ?? '') ?? parse(item.title);
  }

  static DateTime? _kickoff(MediaItem item) {
    final ms = item.liveStartMs;
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  }
}

class _StatusColumn extends StatelessWidget {
  const _StatusColumn({
    required this.live,
    required this.finished,
    required this.kickoff,
    required this.clock,
  });

  final bool live;
  final bool finished;
  final DateTime? kickoff;
  final String? clock;

  @override
  Widget build(BuildContext context) {
    if (live) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LIVE',
            style: AppText.caption.copyWith(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
          if (clock != null) ...[
            const SizedBox(height: 2),
            Text(
              clock!,
              style: AppText.caption.copyWith(
                color: AppColors.accent,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      );
    }
    if (finished) {
      return Text(
        'FT',
        style: AppText.caption.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kickoff == null ? 'TBC' : _time(kickoff!),
          style: AppText.body.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
        if (kickoff != null) ...[
          const SizedBox(height: 2),
          Text(
            _shortDate(kickoff!),
            style: AppText.caption.copyWith(
              color: AppColors.textTertiary,
              fontSize: 9,
            ),
          ),
        ],
      ],
    );
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _shortDate(DateTime t) {
    final diff = _dayOf(t).difference(_dayOf(DateTime.now())).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tmrw';
    return '${t.day}/${t.month}';
  }
}

class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop({required this.tv});

  final bool tv;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -140,
          left: -100,
          child: _Glow(
            size: tv ? 440 : 320,
            color: AppColors.accent.withValues(alpha: 0.20),
          ),
        ),
        Positioned(
          bottom: -120,
          right: -90,
          child: _Glow(
            size: tv ? 380 : 280,
            color: AppColors.accent.withValues(alpha: 0.10),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.all(16),
    this.radius = 20,
    this.tint,
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final base = tint ?? AppColors.surface;
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: gradient,
              color: gradient == null ? base.withValues(alpha: 0.72) : null,
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.value,
    required this.label,
    this.accent = false,
  });

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: accent
          ? AppColors.accent.withValues(alpha: 0.14)
          : Colors.white.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: accent
            ? AppColors.accent.withValues(alpha: 0.26)
            : AppColors.hairline,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (accent) ...[_LiveDot(size: 5), const SizedBox(width: 6)],
        Text(
          value,
          style: AppText.headline.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: accent ? AppColors.accent : AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: AppText.caption.copyWith(
            fontSize: 9,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w700,
            color: accent ? AppColors.accent : AppColors.textTertiary,
          ),
        ),
      ],
    ),
  );
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
    decoration: BoxDecoration(
      gradient: selected
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.accent,
                Color.lerp(AppColors.accent, Colors.white, 0.28)!,
              ],
            )
          : null,
      color: selected ? null : AppColors.surface.withValues(alpha: 0.62),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: selected ? Colors.transparent : AppColors.hairline,
      ),
      boxShadow: selected
          ? [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ]
          : null,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: selected ? Colors.black : AppColors.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppText.body.copyWith(
            color: selected ? Colors.black : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 7),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: selected
                ? Colors.black.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: AppText.caption.copyWith(
              color: selected ? Colors.black : AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    ),
  );
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({this.size = 6});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: AppColors.accent,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.55),
          blurRadius: size * 2.4,
        ),
      ],
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface2.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}

DateTime _dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _longDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]} ${day.day} ${_months[day.month - 1]}';

String _dayName(DateTime day) {
  final today = _dayOf(DateTime.now());
  final diff = _dayOf(day).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return _weekdays[day.weekday - 1];
}
