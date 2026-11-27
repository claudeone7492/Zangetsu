import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/download/download_manager.dart';
import '../../core/download/download_prefs.dart';
import '../../core/download/download_record.dart';
import '../../core/download/download_size_estimate.dart';
import '../../core/models/episode.dart';
import '../../core/models/video_source.dart';
import '../../core/storage/storage_info.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_list_focusable.dart';
import '../../core/ui/app_dialog.dart';
import '../../l10n/l10n.dart';
import '../detail/cubit/detail_cubit.dart' show seasonOf;

String _sourceName(AppLocalizations l10n, VideoSource s, int index) {
  final l = s.label?.trim();
  if (l != null && l.isNotEmpty) return l;
  final q = s.quality?.trim();
  if (q != null && q.isNotEmpty) return q;
  final host = (Uri.tryParse(s.url)?.host ?? '').replaceFirst('www.', '');
  return host.isNotEmpty
      ? l10n.serverWithHost(index + 1, host)
      : l10n.serverNumber(index + 1);
}

/// The short badge a tile leads with: the quality when the source states one,
/// else the host, else its position.
String _qualityBadge(AppLocalizations l10n, VideoSource s, int index) {
  final q = s.quality?.trim();
  if (q != null && q.isNotEmpty) return q;
  final host = (Uri.tryParse(s.url)?.host ?? '').replaceFirst('www.', '');
  if (host.isNotEmpty) return host.split('.').first;
  return l10n.serverNumber(index + 1);
}

Future<String> resolveEpisodeDownloadShowId({
  required String sourceId,
  required String showUrl,
  String? knownId,
  required Iterable<DownloadRecord> downloads,
  required Future<String> Function() loadShowId,
}) async {
  if (knownId != null && knownId.isNotEmpty) return knownId;
  for (final record in downloads) {
    if (record.sourceId == sourceId && record.showUrl == showUrl) {
      return record.showId;
    }
  }
  final id = await loadShowId();
  if (id.isEmpty) throw StateError('Missing download title ID');
  return id;
}

Episode? matchDownloadEpisode(Episode original, List<Episode> episodes) {
  final matches = episodes
      .where(
        (candidate) =>
            (seasonOf(candidate) ?? 1) == (seasonOf(original) ?? 1) &&
            (original.number != null
                ? candidate.number == original.number
                : candidate.url == original.url ||
                      (original.title.trim().isNotEmpty &&
                          candidate.title.trim() == original.title.trim())),
      )
      .toList();
  return matches.length == 1 ? matches.single : null;
}

typedef SingleEpisodeDownloadChoice = ({
  VideoSource chosen,
  List<VideoSource> all,
  Episode episode,
  String category,
});

/// Server/quality picker for one episode's download.
///
/// Every resolved mirror becomes a grid tile carrying its quality, estimated
/// size and container, so choosing a download is one glance instead of reading
/// a column of identical rows. Sizes arrive progressively (one HEAD request or
/// manifest read each) and never block the tap.
class EpisodeDownloadSourceSheet extends StatefulWidget {
  const EpisodeDownloadSourceSheet({
    super.key,
    required this.title,
    required this.category,
    required this.resolve,
    required this.episode,
    required this.availableCategories,
    required this.resolveEpisodes,
    this.initialSources = const [],
    this.estimateSize,
  });

  final String title;
  final String category;
  final Episode episode;
  final List<String> availableCategories;
  final Future<Map<int, List<Episode>>> Function(String) resolveEpisodes;
  final Future<List<VideoSource>> Function(Episode) resolve;

  /// Sources the caller already resolved (the player's current list). Seeds
  /// the grid so it is tappable while the fresh resolve runs.
  final List<VideoSource> initialSources;

  /// Size probe for one source. Injectable so widget tests never touch the
  /// network; production uses [estimateEpisodeBytes].
  @visibleForTesting
  final Future<SizeEstimate?> Function(VideoSource source, int? runtimeMinutes)?
  estimateSize;

  @override
  State<EpisodeDownloadSourceSheet> createState() =>
      _EpisodeDownloadSourceSheetState();
}

class _EpisodeDownloadSourceSheetState
    extends State<EpisodeDownloadSourceSheet> {
  List<VideoSource>? _sources;
  bool _loading = true;
  bool _loadFailed = false;
  late String _category;
  Episode? _episode;
  int _request = 0;
  bool _submitting = false;

  /// url -> estimate. Present with a null value once the probe answered
  /// "unknowable"; absent while it is still running.
  final Map<String, SizeEstimate?> _sizes = {};

  @override
  void initState() {
    super.initState();
    _category = widget.category;
    _load(_category);
  }

  Future<void> _load(String category) async {
    final request = ++_request;
    final seeded = category == widget.category
        ? _prepare(widget.initialSources, category)
        : const <VideoSource>[];
    setState(() {
      _category = category;
      _episode = null;
      _sources = seeded.isEmpty ? null : seeded;
      _sizes.clear();
      _loading = seeded.isEmpty;
      _loadFailed = false;
    });
    if (seeded.isNotEmpty) unawaited(_estimateSizes(seeded));

    try {
      Episode? episode = widget.episode;
      if (category != widget.category) {
        final seasons = await widget.resolveEpisodes(category);
        if (!mounted || request != _request) return;
        final original = widget.episode;
        final pool = seasons[seasonOf(original) ?? 1] ?? <Episode>[];
        episode = matchDownloadEpisode(original, pool);
      }
      if (episode == null) {
        if (mounted && request == _request) setState(() => _loading = false);
        return;
      }
      final sources = await widget.resolve(episode);
      if (!mounted || request != _request) return;
      final resolved = _prepare(sources, category);
      setState(() {
        _episode = episode;
        // A failed sweep must not wipe a list the caller already handed us.
        if (resolved.isNotEmpty || seeded.isEmpty) _sources = resolved;
      });
      if (resolved.isNotEmpty) unawaited(_estimateSizes(resolved));
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => _loadFailed = _sources?.isEmpty ?? true);
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  /// Category filter, de-duplication by URL, then best-quality-first. The
  /// provider's own order survives inside equal qualities.
  List<VideoSource> _prepare(List<VideoSource> sources, String category) {
    final filtered = DownloadManager.sourcesForDownloadCategory(
      sources,
      category,
    );
    final seen = <String>{};
    final unique = <VideoSource>[
      for (final source in filtered)
        if (source.url.trim().isNotEmpty && seen.add(source.url.trim())) source,
    ];
    final indexed = unique.indexed.toList();
    indexed.sort((a, b) {
      final ha = qualityHeight(a.$2.quality) ?? 0;
      final hb = qualityHeight(b.$2.quality) ?? 0;
      if (ha != hb) return hb.compareTo(ha);
      return a.$1.compareTo(b.$1);
    });
    return [for (final entry in indexed) entry.$2];
  }

  /// Fill the size column, four probes at a time. Each probe is a HEAD or a
  /// manifest read; the grid stays interactive throughout.
  Future<void> _estimateSizes(List<VideoSource> sources) async {
    final request = _request;
    final runtime = _episode?.runtimeMinutes ?? widget.episode.runtimeMinutes;
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        final source = sources[next++];
        if (_sizes.containsKey(source.url)) continue;
        SizeEstimate? estimate;
        try {
          final probe = widget.estimateSize;
          estimate = probe != null
              ? await probe(source, runtime)
              : await estimateEpisodeBytes(source, runtimeMinutes: runtime);
        } catch (_) {
          estimate = null;
        }
        if (!mounted || request != _request) return;
        setState(() => _sizes[source.url] = estimate);
      }
    }

    await Future.wait([
      for (var i = 0; i < 4 && i < sources.length; i++) worker(),
    ]);
  }

  bool _isHls(VideoSource s) =>
      s.container == SourceContainer.hls ||
      (Uri.tryParse(s.url)?.path ?? s.url).toLowerCase().endsWith('.m3u8');

  String _sizeLabel(VideoSource s) {
    if (!_sizes.containsKey(s.url)) return '…';
    final estimate = _sizes[s.url];
    return estimate == null ? '—' : formatApproxBytes(estimate.bytes);
  }

  Future<void> _choose(VideoSource source) async {
    final episode = _episode;
    if (episode == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      final estimate = _sizes[source.url];
      // Only a solid number (a real Content-Length or stated bitrate) is worth
      // interrupting for; guesses skip the warning rather than cry wolf.
      if (estimate != null && estimate.solid) {
        final free = await _freeBytes();
        if (!mounted) return;
        if (free != null && estimate.bytes > free) {
          final go = await AppDialog.confirm(
            context,
            title: context.l10n.storageLowTitle,
            message: context.l10n.storageLowBody(
              formatApproxBytes(estimate.bytes),
              formatApproxBytes(free),
            ),
            confirmLabel: context.l10n.downloadAnyway,
          );
          if (!go || !mounted) return;
        }
      }
      if (!mounted) return;
      Navigator.pop(context, (
        chosen: source,
        all: _sources ?? <VideoSource>[source],
        episode: episode,
        category: _category,
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<int?> _freeBytes() async {
    try {
      final prefs = sl<DownloadPrefs>();
      return await StorageInfo.freeBytes(
        destination: prefs.locationUri,
        privateStorage: prefs.keepPrivate,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.6;
    final sources = _sources ?? const <VideoSource>[];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.downloadChooseServer,
                          style: AppText.title,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.title,
                          style: AppText.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _loading ? null : () => _load(_category),
                    tooltip: context.l10n.refresh,
                    icon: _loading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          )
                        : Icon(Icons.refresh_rounded, color: AppColors.accent),
                  ),
                ],
              ),
            ),
            if (widget.availableCategories.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 4),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final category in widget.availableCategories)
                      ChoiceChip(
                        label: Text(
                          category == 'dub'
                              ? context.l10n.dub
                              : context.l10n.sub,
                        ),
                        selected: _category == category,
                        onSelected: (_) {
                          if (_category != category) _load(category);
                        },
                      ),
                  ],
                ),
              ),
            if (sources.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 8, end: 8),
                child: Text(
                  context.l10n.sourcesCount(sources.length),
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (sources.isEmpty && _loading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              )
            else if (sources.isEmpty)
              _emptyState()
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: sl<AppMode>().isTv ? _tvList(sources) : _grid(sources),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8, top: 8, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _loadFailed
                    ? Icons.cloud_off_rounded
                    : Icons.videocam_off_rounded,
                size: 20,
                color: AppColors.textTertiary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _loadFailed
                      ? context.l10n.couldntLoadDownloadOptions
                      : context.l10n.noDownloadSourcesFound,
                  style: AppText.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : () => _load(_category),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.l10n.retry),
          ),
        ],
      ),
    );
  }

  Widget _grid(List<VideoSource> sources) {
    return GridView.builder(
      shrinkWrap: true,
      padding: const EdgeInsetsDirectional.only(end: 8, bottom: 8),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisExtent: 92,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: sources.length,
      itemBuilder: (context, i) => _tile(sources[i], i),
    );
  }

  /// Second line of a tile: who serves it. Never repeats the quality badge
  /// sitting right above it.
  String _tileLabel(VideoSource source, int i) {
    final label = _sourceName(context.l10n, source, i);
    final badge = _qualityBadge(context.l10n, source, i);
    if (label != badge) return label;
    final host = (Uri.tryParse(source.url)?.host ?? '').replaceFirst('www.', '');
    return host.isNotEmpty ? host : context.l10n.serverNumber(i + 1);
  }

  Widget _tile(VideoSource source, int i) {
    final label = _tileLabel(source, i);
    final badge = _qualityBadge(context.l10n, source, i);
    final size = _sizeLabel(source);
    final kind = _isHls(source) ? context.l10n.hls : context.l10n.direct;
    final audio = source.audioLang?.trim();
    final top = i == 0;
    return Semantics(
      button: true,
      label: '$label, $badge, $size, $kind',
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _choose(source),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: top
                    ? AppColors.accent.withValues(alpha: 0.55)
                    : AppColors.hairline,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        badge,
                        style: AppText.body.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (top) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accentSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context.l10n.best,
                          style: AppText.overline.copyWith(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  audio != null && audio.isNotEmpty ? '$label · $audio' : label,
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Icons.download_rounded,
                      size: 13,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        size,
                        style: AppText.caption.copyWith(
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (source.subtitles.isNotEmpty) ...[
                      Text(
                        'CC',
                        style: AppText.overline.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      kind,
                      style: AppText.overline.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tvList(List<VideoSource> sources) {
    return ListView.builder(
      shrinkWrap: true,
      itemCount: sources.length,
      itemBuilder: (context, i) {
        final source = sources[i];
        final label = _tileLabel(source, i);
        final quality = source.quality?.trim();
        final sub = [
          if (quality != null && quality.isNotEmpty && quality != label)
            quality,
          _sizeLabel(source),
          _isHls(source) ? context.l10n.hls : context.l10n.direct,
        ].join(' · ');
        return TvListFocusable(
          autofocus: i == 0,
          onTap: () => _choose(source),
          semanticLabel: '$label, $sub',
          // This ListTile is only built on this TV branch — exclude its own
          // title/subtitle so TalkBack doesn't hear them twice.
          child: ExcludeSemantics(
            child: ListTile(
              contentPadding: const EdgeInsetsDirectional.only(end: 8),
              leading: Icon(Icons.download_rounded, color: AppColors.accent),
              title: Text(
                label,
                style: AppText.body.copyWith(color: AppColors.textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(sub, style: AppText.caption),
            ),
          ),
        );
      },
    );
  }
}
