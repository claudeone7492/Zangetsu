import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/streaming_prefs.dart';
import '../../core/zmode/metadata_filters.dart';
import '../../core/zmode/tmdb_filter_options.dart';
import '../../core/zmode/zmode_ids.dart';
import '../../l10n/l10n.dart';
import 'meta_filter_dialog_tv.dart';

/// Filter sheet for the metadata catalogue.
///
/// A half-height list rather than a full-height wall of chips: seven filters
/// as chips ran past two screens, so nothing below Genres was ever seen. Each
/// row shows its current value and opens a small picker, which keeps the whole
/// set visible at once and leaves the results behind it in view.
///
/// Adult content is deliberately NOT here — it is a privacy setting, not a
/// search refinement, and lives in Settings → Privacy.
Future<MetaFilters?> showMetaFilterSheet(
  BuildContext context,
  ZKind kind,
  MetaFilters current, {
  bool showStatus = true,
}) => showModalBottomSheet<MetaFilters>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (_) =>
      _MetaFilterSheet(kind: kind, initial: current, showStatus: showStatus),
);

/// D-pad-friendly dialog variant for TV search.
Future<MetaFilters?> showMetaFilterDialog(
  BuildContext context,
  ZKind kind,
  MetaFilters current, {
  bool showStatus = true,
}) => showMetaFilterDialogTv(context, kind, current, showStatus: showStatus);

class _MetaFilterSheet extends StatefulWidget {
  const _MetaFilterSheet({
    required this.kind,
    required this.initial,
    required this.showStatus,
  });

  final ZKind kind;
  final MetaFilters initial;
  final bool showStatus;

  @override
  State<_MetaFilterSheet> createState() => _MetaFilterSheetState();
}

class _MetaFilterSheetState extends State<_MetaFilterSheet> {
  late MetaFilters _f = widget.initial;

  bool get _isVideo => widget.kind == ZKind.movie || widget.kind == ZKind.tv;

  /// Sort is excluded unless moved off its default: every search is sorted, so
  /// counting it would say "1 filter" on an untouched sheet.
  int get _count =>
      (_f.genres.isNotEmpty ? 1 : 0) +
      (_f.excludedGenres.isNotEmpty ? 1 : 0) +
      (_f.hasYear ? 1 : 0) +
      (_f.season != null ? 1 : 0) +
      (_f.format != null ? 1 : 0) +
      (widget.showStatus && _f.status != null ? 1 : 0) +
      (_f.minScore != null ? 1 : 0) +
      (_f.runtimeMin != null || _f.runtimeMax != null ? 1 : 0) +
      (_f.originCountry != null ? 1 : 0) +
      (_f.watchProviders.isNotEmpty ? 1 : 0) +
      (_f.certifications.isNotEmpty ? 1 : 0) +
      (_f.tvNetworks.isNotEmpty ? 1 : 0) +
      (_f.tvStatuses.isNotEmpty ? 1 : 0) +
      (_f.tvTypes.isNotEmpty ? 1 : 0) +
      (_f.sort != MetaSort.popularity ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.32,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scroll) => DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.defaultBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.filters, style: AppText.barTitle)),
                  // Only when there IS something to reset — a permanently
                  // visible one reads as an action you forgot to take.
                  if (_count > 0)
                    TextButton(
                      onPressed: () => setState(() => _f = const MetaFilters()),
                      child: Text(l10n.reset),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                children: [
                  // Two per row: these are short label/value pairs, and one
                  // per line pushed half of them below the fold of a half
                  // sheet — the thing the list format was meant to fix.
                  _pair(
                    _cell(
                      l10n.sortBy,
                      _sortLabel(context, _f.sort),
                      true,
                      () => _pick<MetaSort>(
                        l10n.sortBy,
                        MetaSort.values,
                        _f.sort,
                        (v) => _sortLabel(context, v),
                        (v) => setState(() => _f = _f.copyWith(sort: v)),
                      ),
                    ),
                    _cell(
                      l10n.year,
                      _yearLabel(_f),
                      _f.hasYear,
                      _pickYearRange,
                    ),
                  ),
                  _pair(
                    widget.showStatus
                        ? _cell(
                            l10n.status,
                            _f.status == null
                                ? l10n.any
                                : _statusLabel(_f.status!),
                            _f.status != null,
                            () => _pick<MetaStatus>(
                              l10n.status,
                              MetaStatus.values,
                              _f.status,
                              _statusLabel,
                              (v) => setState(
                                () => _f = _f.status == v
                                    ? _f.copyWith(clearStatus: true)
                                    : _f.copyWith(status: v),
                              ),
                            ),
                          )
                        : null,
                    _cell(
                      l10n.minimumScore,
                      _f.minScore == null ? l10n.any : '${_f.minScore}+',
                      _f.minScore != null,
                      () => _pick<int>(
                        l10n.minimumScore,
                        const [50, 60, 70, 80, 90],
                        _f.minScore,
                        (v) => '$v+',
                        (v) => setState(
                          () => _f = _f.minScore == v
                              ? _f.copyWith(clearScore: true)
                              : _f.copyWith(minScore: v),
                        ),
                      ),
                    ),
                  ),
                  // Season is an anime idea; TMDB has no equivalent, so it
                  // would be a control that silently does nothing there.
                  _pair(
                    !_isVideo
                        ? _cell(
                            l10n.season,
                            _f.season == null
                                ? l10n.any
                                : _seasonLabel(_f.season!),
                            _f.season != null,
                            () => _pick<MetaSeason>(
                              l10n.season,
                              MetaSeason.values,
                              _f.season,
                              _seasonLabel,
                              (v) => setState(
                                () => _f = _f.season == v
                                    ? _f.copyWith(clearSeason: true)
                                    : _f.copyWith(season: v),
                              ),
                            ),
                          )
                        : null,
                    _formats().isEmpty
                        ? null
                        : _cell(
                            l10n.format,
                            _f.format == null
                                ? l10n.any
                                : _formatLabel(_f.format!),
                            _f.format != null,
                            () => _pick<MetaFormat>(
                              l10n.format,
                              _formats(),
                              _f.format,
                              _formatLabel,
                              (v) => setState(
                                () => _f = _f.format == v
                                    ? _f.copyWith(clearFormat: true)
                                    : _f.copyWith(format: v),
                              ),
                            ),
                          ),
                  ),
                  // Genres is the multi-select and its value is the longest,
                  // so it takes the full width rather than being truncated
                  // into half of one.
                  _cell(
                    l10n.genres,
                    _f.genres.isEmpty ? l10n.any : _f.genres.join(', '),
                    _f.genres.isNotEmpty,
                    _pickGenres,
                  ),
                  // The rest narrow TMDB's /discover, which only movies and TV
                  // use — anime/manga go through AniList, which has none of
                  // them, so they are not offered there rather than shown and
                  // ignored.
                  if (_isVideo) ...[
                    _pair(
                      _cell(
                        l10n.excludeGenres,
                        _f.excludedGenres.isEmpty
                            ? l10n.any
                            : _f.excludedGenres.join(', '),
                        _f.excludedGenres.isNotEmpty,
                        _pickExcludedGenres,
                      ),
                      _cell(
                        l10n.originCountry,
                        _f.originCountry == null
                            ? l10n.any
                            : _countryLabel(_f.originCountry!),
                        _f.originCountry != null,
                        _pickCountry,
                      ),
                    ),
                    _pair(
                      _cell(
                        l10n.originalLanguage,
                        _f.originalLanguage == null
                            ? l10n.any
                            : _languageLabel(_f.originalLanguage!),
                        _f.originalLanguage != null,
                        _pickLanguage,
                      ),
                      _cell(
                        l10n.runtime,
                        _runtimeLabel(_f),
                        _f.runtimeMin != null || _f.runtimeMax != null,
                        _pickRuntime,
                      ),
                    ),
                    _pair(
                      _cell(
                        l10n.streamingService,
                        _f.watchProviders.isEmpty
                            ? l10n.any
                            : '${_f.watchProviders.length}',
                        _f.watchProviders.isNotEmpty,
                        _pickProviders,
                      ),
                      _f.format == MetaFormat.movie
                          ? _cell(
                              l10n.certification,
                              _f.certifications.isEmpty
                                  ? l10n.any
                                  : _f.certifications.join(', '),
                              _f.certifications.isNotEmpty,
                              _pickCertifications,
                            )
                          : _f.format == MetaFormat.tv
                          ? _cell(
                              l10n.network,
                              _f.tvNetworks.isEmpty
                                  ? l10n.any
                                  : _f.tvNetworks.map(_networkLabel).join(', '),
                              _f.tvNetworks.isNotEmpty,
                              _pickNetworks,
                            )
                          : null,
                    ),
                    if (_f.format == MetaFormat.tv)
                      _pair(
                        _cell(
                          l10n.showStatus,
                          _f.tvStatuses.isEmpty
                              ? l10n.any
                              : _f.tvStatuses
                                    .map(_tvStatusLabelById)
                                    .join(', '),
                          _f.tvStatuses.isNotEmpty,
                          _pickTvStatuses,
                        ),
                        _cell(
                          l10n.showType,
                          _f.tvTypes.isEmpty
                              ? l10n.any
                              : _f.tvTypes.map(_tvTypeLabelById).join(', '),
                          _f.tvTypes.isNotEmpty,
                          _pickTvTypes,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(_f),
                  child: Text(
                    _count == 0 ? l10n.apply : '${l10n.apply} ($_count)',
                    style: AppText.button.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Two cells side by side. A null cell leaves its half empty rather than
  /// letting the other stretch, so the grid stays aligned when a filter does
  /// not apply to this kind.
  Widget _pair(Widget? a, Widget? b) {
    if (a == null && b == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a ?? const SizedBox.shrink()),
        const SizedBox(width: 10),
        Expanded(child: b ?? const SizedBox.shrink()),
      ],
    );
  }

  /// One filter as a tappable box: label above, current value below. The value
  /// is the point — it makes the selection readable at a glance, which a grid
  /// of chips cannot do once there are seven filters.
  Widget _cell(String title, String value, bool on, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: on
                      ? AppColors.accent.withValues(alpha: 0.55)
                      : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: AppText.overline.copyWith(fontSize: 10),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body.copyWith(
                            fontSize: 14,
                            color: on
                                ? AppColors.accent
                                : AppColors.textPrimary,
                            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.expand_more_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// Single-value picker. Tapping the current value clears it, so every filter
  /// can be undone without hunting for an "Any" entry.
  Future<void> _pick<T>(
    String title,
    List<T> values,
    T? current,
    String Function(T) label,
    void Function(T) onPicked,
  ) async {
    final v = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(title, style: AppText.barTitle),
            ),
            const SizedBox(height: 6),
            for (final v in values)
              ListTile(
                title: Text(label(v), style: AppText.body),
                trailing: v == current
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(sheet).pop(v),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (v == null || !mounted) return;
    onPicked(v);
  }

  /// Genres are the one multi-select, so they get chips of their own rather
  /// than a single-value list.
  Future<void> _pickGenres() async {
    var match = _f.genreMatch;
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) {
        var sel = [..._f.genres];
        return StatefulBuilder(
          builder: (sheet2, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.genres, style: AppText.barTitle),
                  const SizedBox(height: 10),
                  // Only worth asking once two genres are in play: with none or
                  // one, all-of and any-of are the same query.
                  if (sel.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SegmentedButton<MetaGenreMatch>(
                        segments: [
                          ButtonSegment(
                            value: MetaGenreMatch.any,
                            label: Text(context.l10n.matchAnyGenre),
                          ),
                          ButtonSegment(
                            value: MetaGenreMatch.all,
                            label: Text(context.l10n.matchAllGenres),
                          ),
                        ],
                        selected: {match},
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          textStyle: WidgetStatePropertyAll(AppText.caption),
                          visualDensity: VisualDensity.compact,
                        ),
                        onSelectionChanged: (s) =>
                            setSheet(() => match = s.first),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Follows the 18+ switch rather than Settings: the
                      // toggle sits right beside this sheet, and offering the
                      // adult genre while it is off would select a genre the
                      // query then filters out — an empty grid and no reason
                      // given. Turn 18+ on and it appears here.
                      for (final g in metaGenresFor(
                        widget.kind,
                        adult: _f.adult,
                      ))
                        GestureDetector(
                          onTap: () => setSheet(() {
                            sel.contains(g) ? sel.remove(g) : sel.add(g);
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: sel.contains(g)
                                  ? AppColors.accent.withValues(alpha: 0.16)
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel.contains(g)
                                    ? AppColors.accent
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              g,
                              style: AppText.caption.copyWith(
                                color: sel.contains(g)
                                    ? AppColors.accent
                                    : AppColors.textPrimary,
                                fontWeight: sel.contains(g)
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(sheet2).pop(sel),
                      child: Text(
                        context.l10n.done,
                        style: AppText.button.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() => _f = _f.copyWith(genres: picked, genreMatch: match));
  }

  /// The sheet's current year range as one line, e.g. "2010 – 2019".
  static String _yearLabel(MetaFilters f) {
    if (f.yearFrom == null && f.yearTo == null) return 'Any';
    if (f.yearFrom != null && f.yearTo == null) return '${f.yearFrom}+';
    if (f.yearFrom == null) return 'up to ${f.yearTo}';
    if (f.yearFrom == f.yearTo) return '${f.yearFrom}';
    return '${f.yearFrom} – ${f.yearTo}';
  }

  static String _runtimeLabel(MetaFilters f) {
    final a = f.runtimeMin;
    final b = f.runtimeMax;
    if (a == null && b == null) return 'Any';
    if (a != null && b == null) return '$a+ min';
    if (a == null) return 'up to $b min';
    if (a == b) return '$a min';
    return '$a – $b min';
  }

  /// Two decade bounds, each independent, so a range can be open at one end.
  /// One sheet rather than two nested ones, and a record rather than a nullable
  /// int — "Any" and "dismissed" would otherwise both read as null.
  Future<void> _pickYearRange() async {
    final now = DateTime.now().year;
    final years = [for (var y = now; y >= 1950; y--) y];
    final picked = await showModalBottomSheet<(int?, int?)>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) {
        int? from = _f.yearFrom;
        int? to = _f.yearTo;
        return StatefulBuilder(
          builder: (sheet2, setSheet) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.l10n.year, style: AppText.barTitle),
                  const SizedBox(height: 12),
                  _yearRow(
                    context.l10n.yearFrom,
                    from,
                    years,
                    (v) => setSheet(() => from = v),
                  ),
                  const SizedBox(height: 12),
                  _yearRow(
                    context.l10n.yearTo,
                    to,
                    years,
                    (v) => setSheet(() => to = v),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.of(sheet2).pop((from, to)),
                      child: Text(
                        context.l10n.done,
                        style: AppText.button.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        yearFrom: picked.$1,
        yearTo: picked.$2,
        clearYear: picked.$1 == null && picked.$2 == null,
      ),
    );
  }

  Widget _yearRow(
    String label,
    int? current,
    List<int> years,
    void Function(int?) onPick,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label.toUpperCase(), style: AppText.overline.copyWith(fontSize: 10)),
      const SizedBox(height: 6),
      SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: years.length + 1,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final v = i == 0 ? null : years[i - 1];
            final on = v == current;
            return GestureDetector(
              onTap: () => onPick(v),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: on
                      ? AppColors.accent.withValues(alpha: 0.16)
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: on ? AppColors.accent : Colors.transparent,
                  ),
                ),
                child: Text(
                  v?.toString() ?? 'Any',
                  style: AppText.caption.copyWith(
                    color: on ? AppColors.accent : AppColors.textPrimary,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ],
  );

  /// An inclusive runtime window, each end optional.
  Future<void> _pickRuntime() async {
    const presets = <(int?, int?, String)>[
      (null, 40, 'Under 40 min'),
      (40, 90, '40 – 90 min'),
      (90, 120, '90 – 120 min'),
      (120, 180, '120 – 180 min'),
      (180, null, '180+ min'),
    ];
    final picked = await showModalBottomSheet<(int?, int?)>(
      context: context,
      backgroundColor: AppColors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.l10n.runtime, style: AppText.barTitle),
            ),
            const SizedBox(height: 6),
            ListTile(
              title: Text('Any', style: AppText.body),
              trailing: _f.runtimeMin == null && _f.runtimeMax == null
                  ? Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.of(sheet).pop((null, null)),
            ),
            for (final (a, b, label) in presets)
              ListTile(
                title: Text(label, style: AppText.body),
                trailing: _f.runtimeMin == a && _f.runtimeMax == b
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(sheet).pop((a, b)),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        runtimeMin: picked.$1,
        runtimeMax: picked.$2,
        clearRuntime: picked.$1 == null && picked.$2 == null,
      ),
    );
  }

  /// A small curated country list — the origin countries a viewer is likely to
  /// reach for. Values are `|`-joined ISO codes where one chip covers several.
  static const _countries = <String, String>{
    'US': 'United States',
    'GB': 'United Kingdom',
    'NG': 'Nigeria',
    'IN': 'India',
    'KR': 'South Korea',
    'JP': 'Japan',
    'CN': 'China',
    'FR': 'France',
    'DE': 'Germany',
    'ES': 'Spain',
    'IT': 'Italy',
    'BR': 'Brazil',
    'MX': 'Mexico',
    'CA': 'Canada',
    'AU': 'Australia',
    'ZA': 'South Africa',
    'GH': 'Ghana',
  };

  Future<void> _pickCountry() async {
    // A sentinel, not null: dismissing the sheet and choosing "Any" both
    // return null from showModalBottomSheet, and they mean different things.
    const anyCode = '__any__';
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(context.l10n.originCountry, style: AppText.barTitle),
            ),
            const SizedBox(height: 6),
            ListTile(
              title: Text('Any', style: AppText.body),
              trailing: _f.originCountry == null
                  ? Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.of(sheet).pop(anyCode),
            ),
            for (final e in _countries.entries)
              ListTile(
                title: Text(e.value, style: AppText.body),
                trailing: _f.originCountry == e.key
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(sheet).pop(e.key),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (code == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        originCountry: code == anyCode ? null : code,
        clearCountry: code == anyCode,
      ),
    );
  }

  static String _countryLabel(String code) =>
      code.split('|').map((c) => _countries[c] ?? c).join(', ');

  /// ISO 639-1 codes the viewer is likely to want, with the languages that
  /// pair with the curated countries above.
  static const _languages = <String, String>{
    'en': 'English',
    'fr': 'French',
    'es': 'Spanish',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'hi': 'Hindi',
    'ko': 'Korean',
    'ja': 'Japanese',
    'zh': 'Chinese',
    'yo': 'Yoruba',
    'ig': 'Igbo',
    'ha': 'Hausa',
    'ar': 'Arabic',
    'ru': 'Russian',
    'tr': 'Turkish',
  };

  static String _languageLabel(String code) =>
      code.split('|').map((c) => _languages[c] ?? c).join(', ');

  Future<void> _pickLanguage() async {
    const anyCode = '__any__';
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                context.l10n.originalLanguage,
                style: AppText.barTitle,
              ),
            ),
            const SizedBox(height: 6),
            ListTile(
              title: Text('Any', style: AppText.body),
              trailing: _f.originalLanguage == null
                  ? Icon(Icons.check_rounded, color: AppColors.accent)
                  : null,
              onTap: () => Navigator.of(sheet).pop(anyCode),
            ),
            for (final e in _languages.entries)
              ListTile(
                title: Text(e.value, style: AppText.body),
                trailing: _f.originalLanguage == e.key
                    ? Icon(Icons.check_rounded, color: AppColors.accent)
                    : null,
                onTap: () => Navigator.of(sheet).pop(e.key),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (code == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        originalLanguage: code == anyCode ? null : code,
        clearLanguage: code == anyCode,
      ),
    );
  }

  /// Genres to drop, the mirror of the genre picker.
  Future<void> _pickExcludedGenres() async {
    final all = metaGenresFor(widget.kind);
    final picked = await _pickMulti(
      context.l10n.excludeGenres,
      all,
      selected: _f.excludedGenres.toSet(),
      label: (g) => g,
    );
    if (picked == null || !mounted) return;
    setState(() => _f = _f.copyWith(excludedGenres: picked));
  }

  /// Streaming services with titles in the active region, fetched from TMDB.
  Future<void> _pickProviders() async {
    final options = _filterOptions();
    if (options == null) return;
    final region = _f.watchRegion ?? StreamingPrefs.region;
    final providers = await options.watchProviders(region);
    if (!mounted) return;
    if (providers.isEmpty) {
      showAppToast(context, context.l10n.filtersNeedProvider('TMDB'));
      return;
    }
    final picked = await _pickMulti(
      context.l10n.streamingService,
      providers,
      selected: _f.watchProviders.toSet(),
      label: (p) => p.name,
      idOf: (p) => p.id,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        watchProviders: picked.map((p) => p.id).toList(),
        watchRegion: region,
        clearProviders: picked.isEmpty,
      ),
    );
  }

  /// Age ratings for the active region, fetched from TMDB.
  Future<void> _pickCertifications() async {
    final options = _filterOptions();
    if (options == null) return;
    final country = _f.certificationCountry ?? StreamingPrefs.region;
    final certs = await options.movieCertifications(country);
    if (!mounted) return;
    if (certs.isEmpty) {
      showAppToast(context, context.l10n.filtersNeedProvider('TMDB'));
      return;
    }
    final picked = await _pickMulti(
      context.l10n.certification,
      certs,
      selected: _f.certifications.toSet(),
      label: (c) => c.code,
      sub: (c) => c.meaning,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        certifications: picked.map((c) => c.code).toList(),
        certificationCountry: country,
        clearCertifications: picked.isEmpty,
      ),
    );
  }

  Future<void> _pickNetworks() async {
    final picked = await _pickMulti(
      context.l10n.network,
      TmdbTvNetwork.values,
      selected: _f.tvNetworks.toSet(),
      label: (n) => n.displayName,
      idOf: (n) => n.id,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        tvNetworks: picked.map((n) => n.id).toList(),
        clearNetworks: picked.isEmpty,
      ),
    );
  }

  Future<void> _pickTvStatuses() async {
    final picked = await _pickMulti(
      context.l10n.showStatus,
      TmdbTvStatus.values,
      selected: _f.tvStatuses.toSet(),
      label: _tvStatusLabel,
      idOf: (s) => s.id,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        tvStatuses: picked.map((s) => s.id).toList(),
        clearTvStatuses: picked.isEmpty,
      ),
    );
  }

  Future<void> _pickTvTypes() async {
    final picked = await _pickMulti(
      context.l10n.showType,
      TmdbTvType.values,
      selected: _f.tvTypes.toSet(),
      label: _tvTypeLabel,
      idOf: (t) => t.id,
    );
    if (picked == null || !mounted) return;
    setState(
      () => _f = _f.copyWith(
        tvTypes: picked.map((t) => t.id).toList(),
        clearTvTypes: picked.isEmpty,
      ),
    );
  }

  /// The TMDB option source, or null when Z Mode isn't wired up (tests, or a
  /// build without the module).
  TmdbFilterOptions? _filterOptions() =>
      sl.isRegistered<TmdbFilterOptions>() ? sl<TmdbFilterOptions>() : null;

  /// Multi-select over [values]. [selected] holds the ids (see [idOf], default
  /// the value itself) that are already chosen; the return is the chosen
  /// values, or null when the sheet is dismissed.
  Future<List<T>?> _pickMulti<T>(
    String title,
    List<T> values, {
    required Set<Object> selected,
    required String Function(T) label,
    Object Function(T)? idOf,
    String Function(T)? sub,
  }) async {
    final id = idOf ?? (T v) => v as Object;
    final sel = <Object>{...selected};
    final result = await showModalBottomSheet<List<Object>>(
      context: context,
      backgroundColor: AppColors.bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet2, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.barTitle),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in values)
                          GestureDetector(
                            onTap: () => setSheet(() {
                              sel.contains(id(v))
                                  ? sel.remove(id(v))
                                  : sel.add(id(v));
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: sel.contains(id(v))
                                    ? AppColors.accent.withValues(alpha: 0.16)
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: sel.contains(id(v))
                                      ? AppColors.accent
                                      : Colors.transparent,
                                ),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label(v),
                                    style: AppText.caption.copyWith(
                                      color: sel.contains(id(v))
                                          ? AppColors.accent
                                          : AppColors.textPrimary,
                                      fontWeight: sel.contains(id(v))
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  if (sub != null && sub(v).isNotEmpty)
                                    Text(
                                      sub(v),
                                      style: AppText.overline.copyWith(
                                        fontSize: 10,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(sheet2).pop(sel.toList()),
                    child: Text(
                      context.l10n.done,
                      style: AppText.button.copyWith(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null) return null;
    final wanted = result.toSet();
    return [
      for (final v in values)
        if (wanted.contains(id(v))) v,
    ];
  }

  /// Formats worth offering. Manga and novel already pin their format by kind,
  /// so a picker there would contradict the query and return nothing.
  List<MetaFormat> _formats() {
    if (_isVideo) return const [MetaFormat.tv, MetaFormat.movie];
    if (widget.kind == ZKind.anime) {
      return const [
        MetaFormat.tv,
        MetaFormat.movie,
        MetaFormat.ova,
        MetaFormat.special,
      ];
    }
    return const [];
  }

  static String _sortLabel(BuildContext c, MetaSort s) => switch (s) {
    MetaSort.popularity => c.l10n.sortPopularity,
    MetaSort.score => c.l10n.sortScore,
    MetaSort.trending => c.l10n.sortTrending,
    MetaSort.newest => c.l10n.sortNewest,
    MetaSort.oldest => c.l10n.sortOldest,
    MetaSort.title => c.l10n.sortTitle,
  };

  static String _seasonLabel(MetaSeason s) => switch (s) {
    MetaSeason.winter => 'Winter',
    MetaSeason.spring => 'Spring',
    MetaSeason.summer => 'Summer',
    MetaSeason.fall => 'Fall',
  };

  static String _formatLabel(MetaFormat f) => switch (f) {
    MetaFormat.tv => 'TV',
    MetaFormat.movie => 'Movie',
    MetaFormat.ova => 'OVA',
    MetaFormat.special => 'Special',
    MetaFormat.manga => 'Manga',
    MetaFormat.novel => 'Novel',
    MetaFormat.oneShot => 'One shot',
  };

  static String _statusLabel(MetaStatus s) => switch (s) {
    MetaStatus.releasing => 'Airing',
    MetaStatus.finished => 'Finished',
    MetaStatus.notYetReleased => 'Upcoming',
    MetaStatus.cancelled => 'Cancelled',
  };

  static String _networkLabel(int id) =>
      TmdbTvNetwork.values
          .where((n) => n.id == id)
          .map((n) => n.displayName)
          .firstOrNull ??
      '$id';

  static String _tvStatusLabelById(int id) =>
      TmdbTvStatus.values
          .where((s) => s.id == id)
          .map(_tvStatusLabel)
          .firstOrNull ??
      '$id';

  static String _tvTypeLabelById(int id) =>
      TmdbTvType.values
          .where((t) => t.id == id)
          .map(_tvTypeLabel)
          .firstOrNull ??
      '$id';

  static String _tvStatusLabel(TmdbTvStatus s) => switch (s) {
    TmdbTvStatus.returning => 'Returning',
    TmdbTvStatus.planned => 'Planned',
    TmdbTvStatus.inProduction => 'In production',
    TmdbTvStatus.ended => 'Ended',
    TmdbTvStatus.cancelled => 'Cancelled',
    TmdbTvStatus.pilot => 'Pilot',
  };

  static String _tvTypeLabel(TmdbTvType t) => switch (t) {
    TmdbTvType.documentary => 'Documentary',
    TmdbTvType.news => 'News',
    TmdbTvType.miniseries => 'Miniseries',
    TmdbTvType.reality => 'Reality',
    TmdbTvType.scripted => 'Scripted',
    TmdbTvType.talkShow => 'Talk show',
    TmdbTvType.video => 'Video',
  };
}
