import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/live/dvr_store.dart';
import '../../core/live/epg_store.dart';
import '../../core/live/xmltv_parser.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/settings_widgets.dart';
import '../../core/ui/source_icon_tile.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';

/// One channel row the guide renders: the playlist entry plus the EPG channel
/// id it resolved to (null when the guide doesn't cover it).
class EpgChannelRow {
  const EpgChannelRow({
    required this.name,
    this.logo = '',
    this.channelId,
    this.tvgId,
  });

  final String name;
  final String logo;

  /// Guide channel id, or null when no configured guide covers this channel.
  final String? channelId;
  final String? tvgId;
}

/// The TV guide — an EPG grid over the channels the Live TV page lists.
///
/// Hikari's `LiveTvGuideScreen` equivalent: for each channel, what is on now
/// (with a progress bar), what is on next, and the next few hours underneath.
/// The guide is an enhancement, not a requirement — a channel with no EPG
/// coverage still lists, with "No guide data" where its schedule would be.
///
/// Reads [EpgStore] synchronously and refreshes stale guides in the background,
/// so opening the guide never waits on a multi-megabyte XMLTV download.
class LiveTvGuideScreen extends StatefulWidget {
  const LiveTvGuideScreen({super.key, required this.channels});

  final List<EpgChannelRow> channels;

  @override
  State<LiveTvGuideScreen> createState() => _LiveTvGuideScreenState();
}

class _LiveTvGuideScreenState extends State<LiveTvGuideScreen> {
  EpgStore? _store;
  DvrStore? _dvr;
  Timer? _ticker;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _store = sl.isRegistered<EpgStore>() ? sl<EpgStore>() : null;
    _dvr = sl.isRegistered<DvrStore>() ? sl<DvrStore>() : null;
    _store?.addListener(_changed);
    _dvr?.addListener(_changed);
    _dvr?.ensureLoaded();
    _refresh();
    // Re-render every 30s so the "now" bar advances and a programme rolls over
    // to the next without the viewer having to leave and come back.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _store?.removeListener(_changed);
    _dvr?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    final store = _store;
    if (store == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await store.refreshAll();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final covered = widget.channels.where((c) {
      final id = c.channelId;
      return id != null && (store?.schedule(id).isNotEmpty ?? false);
    }).length;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: settingsAppBar(
        'TV guide',
        actions: [
          IconButton(
            tooltip: context.l10n.liveRefreshGuide,
            onPressed: _refreshing ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: store == null
          ? const EmptyState(
              icon: Icons.calendar_month_outlined,
              message: 'The TV guide is not available on this device',
            )
          : Column(
              children: [
                if (_refreshing) const LinearProgressIndicator(minHeight: 2),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          covered == 0
                              ? context.l10n.liveNoGuideData
                              : '$covered of ${widget.channels.length} '
                                    'channels have guide data',
                          style: AppText.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: widget.channels.isEmpty
                      ? const EmptyState(
                          icon: Icons.live_tv_outlined,
                          message: 'No channels to show',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                          itemCount: widget.channels.length,
                          itemBuilder: (context, i) => _channelTile(
                            store,
                            widget.channels[i],
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _channelTile(EpgStore store, EpgChannelRow channel) {
    final id = channel.channelId;
    final now = id == null ? null : store.nowOn(id);
    final next = id == null ? null : store.nextOn(id);
    final later = id == null
        ? const <EpgProgramme>[]
        : store
              .upcoming(id, hours: 6)
              .where((p) => now == null || p.start.isAfter(now.start))
              .skip(1)
              .take(3)
              .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SourceIconTile(
                name: channel.name,
                icon: channel.logo.isEmpty ? null : channel.logo,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channel.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body,
                ),
              ),
              if (now != null)
                Text(
                  _clock(now.start),
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (now == null)
            Text(
              context.l10n.liveNoGuideData,
              style: AppText.caption.copyWith(color: AppColors.textTertiary),
            )
          else ...[
            Text(
              now.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            _progress(now),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '${_clock(now.start)}–${_clock(now.stop)}',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (next != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Next: ${next.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
                if (_dvr != null) ...[
                  IconButton(
                    tooltip: context.l10n.liveSetReminder,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _book(now, channel, DvrKind.reminder),
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      size: 18,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.liveRecord,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _book(now, channel, DvrKind.recording),
                    icon: const Icon(
                      Icons.fiber_manual_record_outlined,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
            if (later.isNotEmpty) ...[
              const SizedBox(height: 6),
              for (final p in later)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text(
                          _clock(p.start),
                          style: AppText.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  /// Book a reminder or a recording for [programme] on [channel].
  ///
  /// The booking is made from the guide, which knows the airing but not the
  /// playable URL, so a recording starts without a stream and the schedule
  /// flags it until the channel is opened. That is honest: the guide can book
  /// the intent, only the provider can resolve the stream.
  Future<void> _book(
    EpgProgramme programme,
    EpgChannelRow channel,
    DvrKind kind,
  ) async {
    final dvr = _dvr;
    if (dvr == null) return;
    await dvr.book(
      DvrEntry.fromProgramme(
        programme,
        channelName: channel.name,
        kind: kind,
        paddingMinutes: kind == DvrKind.recording ? 2 : 0,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          kind == DvrKind.recording
              ? 'Recording booked: ${programme.title}'
              : 'Reminder set: ${programme.title}',
        ),
      ),
    );
  }

  /// How far through the current programme we are, as a thin bar. Reads the
  /// wall clock, which the 30s ticker keeps current.
  Widget _progress(EpgProgramme now) {
    final total = now.duration.inSeconds;
    if (total <= 0) return const SizedBox.shrink();
    final elapsed = DateTime.now().toUtc().difference(now.start).inSeconds;
    final fraction = (elapsed / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 3,
        backgroundColor: AppColors.surface2,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
      ),
    );
  }

  /// Local wall-clock label for a guide timestamp.
  static String _clock(DateTime utc) {
    final local = utc.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
