import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/models/provider_info.dart';
import '../../core/playback/watch_history.dart';
import '../../core/reading/read_history.dart';
import '../../core/stats/stats_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// Stats page (gap E1): the watch/read time Hikari's StatsScreen shows, built
/// from the history stores we already keep — no new backend, no new dependency.
///
/// [StatsEngine] does all the arithmetic over plain value objects; this screen
/// only adapts [HistoryEntry]/[ReadEntry] into [WatchStat]/[ReadStat] and
/// renders the result, so the numbers are unit-tested independently of the UI.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _watch = sl<WatchHistory>();
  final _read = sl<ReadHistory>();

  StatsSummary get _summary => StatsSummary.from(
    [
      for (final e in _watch.all())
        WatchStat(
          showId: e.showId,
          title: e.showTitle,
          position: e.position,
          duration: e.duration,
          updatedAt: e.updatedAt,
          category: e.category,
          episodeNumber: e.episodeNumber,
          finished: e.finished,
        ),
    ],
    [
      for (final t in [ProviderType.manga, ProviderType.novel])
        for (final e in _read.all().where((r) => r.type == t))
          ReadStat(
            title: e.title,
            type: t.name,
            pos: e.pos,
            total: e.total,
            updatedAt: e.updatedMs,
            finished: e.finished,
          ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    final l10n = context.l10n;
    final hasAny = s.titlesWatched > 0 || s.titlesRead > 0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(l10n.stats),
      body: !hasAny
          ? EmptyState(
              icon: Icons.insights_outlined,
              message: '${l10n.statsNothingYet}\n${l10n.statsNothingYetBody}',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 28),
              children: [
                SettingsSectionLabel(l10n.statsWatchTime, first: true),
                _StatGrid(
                  entries: [
                    (Icons.schedule_rounded, l10n.statsWatchTime,
                        formatStatDuration(s.watchTime)),
                    (Icons.menu_book_outlined, l10n.statsReadTime,
                        formatStatDuration(s.readTime)),
                    (Icons.movie_outlined, l10n.statsTitlesWatched,
                        '${s.titlesWatched}'),
                    (Icons.playlist_play_rounded, l10n.statsEpisodesWatched,
                        '${s.episodesWatched}'),
                    (Icons.auto_stories_outlined, l10n.statsTitlesRead,
                        '${s.titlesRead}'),
                    (Icons.bookmark_border_rounded, l10n.statsChaptersRead,
                        '${s.chaptersRead}'),
                  ],
                ),
                SettingsSectionLabel(l10n.statsDayStreak),
                _StatGrid(
                  entries: [
                    (Icons.local_fire_department_outlined, l10n.statsDayStreak,
                        l10n.statsDayStreakValue(s.streakDays)),
                    (Icons.event_available_outlined, l10n.statsActiveDays,
                        l10n.statsActiveDaysValue(s.activeDays)),
                  ],
                ),
                SettingsSectionLabel(l10n.statsLast7),
                _ActivityBars(buckets: s.last7, dense: false),
                SettingsSectionLabel(l10n.statsLast30),
                _ActivityBars(buckets: s.last30, dense: true),
                if (s.topShows.isNotEmpty) ...[
                  SettingsSectionLabel(l10n.statsMostWatched),
                  SettingsCard(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    children: [
                      for (final t in s.topShows.take(5))
                        SettingsTile(
                          icon: Icons.bar_chart_rounded,
                          title: t.title.isEmpty ? t.showId : t.title,
                          subtitle: l10n.statsEpisodesCount(t.episodes),
                          trailing: Text(
                            formatStatDuration(t.time),
                            style: AppText.caption,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

/// A 2-up grid of label/value cards.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.entries});
  final List<(IconData, String, String)> entries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final (icon, label, value) in entries)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 42) / 2,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 20, color: AppColors.accent),
                    const SizedBox(height: 10),
                    Text(value, style: AppText.title.copyWith(fontSize: 24)),
                    const SizedBox(height: 2),
                    Text(label, style: AppText.caption),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A row of bars, one per day, watch stacked under read. Empty days render as a
/// faint baseline so the axis keeps a fixed width.
class _ActivityBars extends StatelessWidget {
  const _ActivityBars({required this.buckets, required this.dense});
  final List<DayBucket> buckets;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final maxCount = buckets.fold<int>(
      1,
      (m, b) => [m, b.watches, b.reads].reduce((a, c) => a > c ? a : c),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        height: 120,
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final b in buckets)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 1 : 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _bar(
                        (b.watches / maxCount).clamp(0.0, 1.0),
                        AppColors.accent,
                        dense,
                      ),
                      const SizedBox(height: 2),
                      _bar(
                        (b.reads / maxCount).clamp(0.0, 1.0),
                        AppColors.textTertiary,
                        dense,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double fraction, Color color, bool dense) {
    const trackHeight = 76.0;
    final h = (trackHeight * fraction).clamp(2.0, trackHeight);
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: fraction == 0 ? AppColors.hairline : color,
        borderRadius: BorderRadius.circular(dense ? 2 : 4),
      ),
    );
  }
}
