import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../core/di/injector.dart';
import '../../core/stremio/stremio_manager.dart';
import '../../core/stremio/stremio_provider.dart';
import '../../core/stremio/stremio_home_cache.dart';
import '../../core/profiles/viewer_profile.dart';
import '../../core/mode/content_mode.dart';
import '../../core/mode/content_mode_cubit.dart';
import '../../core/models/home_section.dart';
import '../../core/metadata/home_dedupe.dart';
import '../../core/metadata/title_quality.dart';
import '../../core/privacy/nsfw_gate.dart';
import '../../core/models/media_item.dart';
import '../../core/collections/collection_store.dart';
import '../../core/repository/source_repository.dart';
import '../../core/state/active_source_cubit.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/row_skeleton.dart';
import '../detail/detail_screen.dart';
import '../search/browse_source_screen.dart' show canonicalTargetFor;
import '../sources/providers_hub_screen.dart';
import '../sources/stremio_sources_screen.dart';
import 'cubit/home_rows_composer.dart' show providerRowSections;
import 'provider_browse_route.dart';
import 'see_all_screen.dart';

/// Use the same metadata identity as source browsing, or keep source-only
/// titles available when matching is off, slow, or uncertain.
Future<MediaItem> sourceCatalogueTargetFor(
  MediaItem item, {
  Future<MediaItem?> Function(MediaItem)? lookup,
}) async => await (lookup ?? canonicalTargetFor)(item) ?? item;

/// Lets the Home pull-to-refresh gesture refresh whichever embedded catalogue
/// instance is currently mounted, without a GlobalKey that must be reparented
/// when Home rows finish loading.
class SourceCatalogueHomeController {
  Object? _owner;
  Future<void> Function()? _refresh;

  Future<void> refresh() async {
    await _refresh?.call();
  }

  void _attach(Object owner, Future<void> Function() refresh) {
    _owner = owner;
    _refresh = refresh;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _refresh = null;
  }
}

/// Source catalogue content embedded directly in the Home feed. Its
/// source choice is local so browsing cannot change the user's active source.
class SourceCatalogueHomeContent extends StatefulWidget {
  const SourceCatalogueHomeContent({
    super.key,
    this.initialSourceId,
    this.mode,
    this.controller,
    this.onSourceSelected,
    this.onSectionsChanged,
    this.sectionBuilder,
    this.showSourcePicker = true,
    this.repository,
    this.sliver = false,
  });

  final String? initialSourceId;
  final ContentMode? mode;
  final SourceCatalogueHomeController? controller;
  final ValueChanged<String>? onSourceSelected;
  final ValueChanged<List<HomeSection>>? onSectionsChanged;
  final Widget Function(HomeSection)? sectionBuilder;
  final bool showSourcePicker;
  final bool sliver;

  @visibleForTesting
  final SourceRepository? repository;

  @override
  State<SourceCatalogueHomeContent> createState() =>
      SourceCatalogueHomeContentState();
}

class SourceCatalogueHomeContentState
    extends State<SourceCatalogueHomeContent> {
  final Object _controllerOwner = Object();
  late final SourceRepository _repository =
      widget.repository ?? sl<SourceRepository>();
  late ContentMode _mode;
  List<({String id, String name})> _sources = const [];

  String? _sourceId;
  List<HomeSection>? _sections;
  bool _loading = false;
  bool _failed = false;
  bool _openingItem = false;
  int _generation = 0;
  StremioManager? _stremioManager;
  ViewerProfileStore? _profiles;
  Timer? _sectionUpdateTimer;
  List<HomeSection>? _pendingSections;

  ContentMode _modeFor(SourceCatalogueHomeContent widget) =>
      widget.mode ??
      (sl.isRegistered<ContentModeCubit>()
          ? sl<ContentModeCubit>().state
          : ContentMode.anime);

  @override
  void initState() {
    super.initState();
    if (sl.isRegistered<StremioManager>()) {
      _stremioManager = sl<StremioManager>()..addListener(_onStremioChanged);
    }
    if (sl.isRegistered<ViewerProfileStore>()) {
      _profiles = sl<ViewerProfileStore>();
      _profiles!.contextRevision.addListener(_onProfileChanged);
    }
    widget.controller?._attach(_controllerOwner, refresh);
    _mode = _modeFor(widget);
    _sources = _sourcesForMode();
    _sourceId = _chooseSourceId(widget.initialSourceId);
    _rememberSource();
    if (_sourceId != null) _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant SourceCatalogueHomeContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(_controllerOwner);
      widget.controller?._attach(_controllerOwner, refresh);
    }
    final nextMode = _modeFor(widget);
    final modeChanged = nextMode != _mode;
    final requestedSourceChanged =
        widget.initialSourceId != oldWidget.initialSourceId &&
        widget.initialSourceId != _sourceId;
    if (!modeChanged && !requestedSourceChanged) {
      return;
    }
    _mode = nextMode;
    _sources = _sourcesForMode();
    _generation++;
    _sourceId = _chooseSourceId(widget.initialSourceId);
    _rememberSource();
    _sections = null;
    _loading = false;
    _failed = false;
    if (_sourceId != null) _load(reset: true);
    _notifySections(const []);
  }

  void _onProfileChanged() {
    if (!mounted || _sourceId != 'stremio') return;
    _load(reset: true);
    _notifySections(const []);
  }

  void _onStremioChanged() {
    if (!mounted || _sourceId != 'stremio') return;
    _sources = _sourcesForMode();
    _load(reset: true);
    _notifySections(const []);
  }

  void _notifySections(List<HomeSection> sections) {
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) {
        widget.onSectionsChanged?.call(sections);
      }
    });
  }

  /// Used by Home's existing pull-to-refresh gesture when source mode is active.
  Future<void> refresh() async {
    final sources = _sourcesForMode();
    final changed = !listEquals(sources, _sources);
    if (changed) {
      _sources = sources;
      _sourceId = _chooseSourceId(_sourceId);
      _rememberSource();
    }
    if (_sourceId == null) {
      if (changed) setState(() {});
      return;
    }
    await _load(reset: changed, forceRefresh: true);
  }

  String? _chooseSourceId([String? preferred]) {
    if (widget.initialSourceId == 'stremio') return 'stremio';
    if (_sources.any((source) => source.id == preferred)) return preferred;
    final activeId = sl.isRegistered<ActiveSourceCubit>()
        ? sl<ActiveSourceCubit>().state
        : null;
    if (_sources.any((source) => source.id == activeId)) return activeId;
    return _sources.firstOrNull?.id;
  }

  void _rememberSource() {
    final sourceId = _sourceId;
    if (sourceId != null) widget.onSourceSelected?.call(sourceId);
  }

  List<({String id, String name})> _sourcesForMode() {
    final types = manifestSourceTypes();
    return _repository.loadedSources
        .where((source) {
          final id = source.id;
          // Stremio has its own catalogue toggle; never select it as a fallback.
          if (widget.initialSourceId == 'stremio') return id == 'stremio';
          if (id == 'stremio') return false;
          return sourceInMode(id, _mode, types);
        })
        .toList(growable: false);
  }

  Future<void> _load({bool reset = false, bool forceRefresh = false}) async {
    _sectionUpdateTimer?.cancel();
    _sectionUpdateTimer = null;
    _pendingSections = null;
    var previousSections = reset
        ? const <HomeSection>[]
        : _sections ?? const <HomeSection>[];
    final sourceId = _sourceId;
    if (sourceId == null) return;
    if (sourceId == 'stremio' && !_sources.any((s) => s.id == sourceId)) {
      _generation++;
      setState(() {
        _loading = false;
        _failed = false;
        _sections = const [];
      });
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) _sections = null;
    });
    final cache = sourceId == 'stremio' && sl.isRegistered<StremioHomeCache>()
        ? sl<StremioHomeCache>()
        : null;
    final snapshotScope = cache == null || _stremioManager == null
        ? null
        : StremioHomeCache.scope(
            owner: _profiles?.ownerKey ?? 'local',
            profile:
                '${_profiles?.activeId ?? kDefaultProfileId}:${_profiles?.activeProfile.isKids ?? false}',
            addons: _stremioManager!.enabled,
          );
    final failedCatalogs = <String>{};
    List<HomeSection>? completedSections;
    var loadFailed = false;
    List<HomeSection> recoveredRows(List<HomeSection> fresh) =>
        retainFailedStremioRows(
          fresh,
          previousSections,
          loadFailed
              ? {
                  for (final row in previousSections)
                    row.more?.categoryId ?? row.title,
                }
              : failedCatalogs,
        );
    if (cache != null && snapshotScope != null && _sections == null) {
      unawaited(
        cache.read(snapshotScope).then((remembered) {
          if (!mounted ||
              generation != _generation ||
              remembered == null ||
              remembered.isEmpty) {
            return;
          }
          previousSections = remembered;
          final finished = completedSections;
          if (finished != null) {
            if (!loadFailed && failedCatalogs.isEmpty) return;
            final restored = recoveredRows(finished);
            setState(() {
              _sections = restored;
              _failed = restored.isEmpty;
            });
            _notifySections(restored);
          } else if (_sections == null && _loading) {
            setState(() => _sections = remembered);
            _notifySections(remembered);
          }
        }),
      );
    }
    try {
      void publish(List<HomeSection> updates) {
        if (!mounted || generation != _generation) return;
        _pendingSections = updates;
        void apply() {
          _sectionUpdateTimer = null;
          if (!mounted || generation != _generation) return;
          final next = _pendingSections;
          _pendingSections = null;
          if (next == null) return;
          final firstResult = _sections == null || _sections!.isEmpty;
          // Keep existing rows while slower catalogues refresh.
          final merged = {
            for (final section in previousSections)
              section.more?.categoryId ?? section.title: section,
          };
          for (final section in next) {
            merged[section.more?.categoryId ?? section.title] = section;
          }
          setState(() => _sections = merged.values.toList(growable: false));
          if (firstResult) _notifySections(_sections!);
        }

        if (_sections == null) {
          apply();
        } else {
          _sectionUpdateTimer ??= Timer(
            const Duration(milliseconds: 100),
            apply,
          );
        }
      }

      final sections =
          sourceId == 'stremio' && sl.isRegistered<StremioProvider>()
          ? await sl<StremioProvider>().getHome(
                  onSections: publish,
                  forceRefresh: forceRefresh,
                  onFailure: failedCatalogs.add,
                ) ??
                const <HomeSection>[]
          : await _repository.home(sourceId: sourceId);
      if (!mounted || generation != _generation) return;
      _sectionUpdateTimer?.cancel();
      _sectionUpdateTimer = null;
      _pendingSections = null;
      completedSections = sections;
      final withCollections = await _withCollections(sections);
      if (!mounted || generation != _generation) return;
      final visible = _sanitize(withCollections);
      final displayed = recoveredRows(visible);
      setState(() {
        _sections = displayed;
        _loading = false;
        _failed = displayed.isEmpty && failedCatalogs.isNotEmpty;
      });
      _notifySections(displayed);
      if (cache != null && snapshotScope != null && failedCatalogs.isEmpty) {
        unawaited(cache.write(snapshotScope, sections));
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _sectionUpdateTimer?.cancel();
      _sectionUpdateTimer = null;
      _pendingSections = null;
      loadFailed = true;
      completedSections = _sections ?? const [];
      final displayed = sourceId == 'stremio'
          ? recoveredRows(completedSections)
          : const <HomeSection>[];
      setState(() {
        _failed = displayed.isEmpty;
        _loading = false;
        _sections = displayed;
      });
      _notifySections(displayed);
    }
  }

  /// Personal collections sit ABOVE the source's own rows: they are the user's
  /// own catalogue, so they belong at the top of the page they built.
  ///
  /// A live folder refills here (one Home load, one refresh) rather than on a
  /// timer, so a collection can never change under a reader mid-scroll.
  Future<List<HomeSection>> _withCollections(
    List<HomeSection> sections,
  ) async {
    if (!sl.isRegistered<CollectionStore>()) return sections;
    final store = sl<CollectionStore>();
    try {
      await store.refreshLive();
    } catch (_) {
      // A collection that cannot refresh keeps its last titles.
    }
    final rows = store.sections();
    if (rows.isEmpty) return sections;
    return [...rows, ...sections];
  }

  void _selectSource(String? sourceId) {
    if (sourceId == null || sourceId == _sourceId) return;
    setState(() => _sourceId = sourceId);
    _rememberSource();
    _load(reset: true);
    _notifySections(const []);
  }

  Future<void> _openItem(MediaItem item) async {
    if (_openingItem) return;
    _openingItem = true;
    try {
      if (await openProviderExtensionItem(
        context,
        item,
        repository: _repository,
      )) {
        return;
      }
      final target = await sourceCatalogueTargetFor(item);
      if (mounted) Navigator.of(context).push(DetailScreen.route(target));
    } finally {
      _openingItem = false;
    }
  }

  /// Drops adult titles when the NSFW switch is off, and collapses the same
  /// title arriving from two engines. Rows left empty disappear with them.
  List<HomeSection> _sanitize(List<HomeSection> sections) {
    final out = <HomeSection>[];
    for (final section in sections) {
      final items = HomeDedupe.dedupe(
        NsfwGate.filter(
          section.items,
          title: (i) => i.title,
          flagged: (i) => i.isAdult,
        ),
        key: (i) => HomeDedupe.keyFor(
          id: i.id,
          type: i.type.name,
          year: i.year,
          title: i.title,
        ),
      );
      if (items.isNotEmpty) {
        out.add(HomeSection(title: section.title, items: items, more: section.more));
      }
    }
    return out;
  }

  void _openSection(HomeSection section) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SeeAllScreen(
          title: section.title,
          items: section.items,
          onTap: _openItem,
          onLoadMore: section.more == null
              ? null
              : (page) => _repository.browseMore(section.more!, page),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sectionUpdateTimer?.cancel();
    widget.controller?._detach(_controllerOwner);
    _stremioManager?.removeListener(_onStremioChanged);
    _profiles?.contextRevision.removeListener(_onProfileChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections ?? const <HomeSection>[];
    if (!widget.sliver) return _content(sections);
    if (sections.isEmpty || _failed || _sources.isEmpty) {
      return SliverToBoxAdapter(child: _content(sections));
    }
    final rows = widget.sectionBuilder == null
        ? sections
        : providerRowSections(sections, isTv: false);
    final keys = [
      for (var i = 0; i < rows.length; i++)
        ValueKey(rows[i].more?.categoryId ?? '${rows[i].title}:$i'),
    ];
    final indices = {for (var i = 0; i < keys.length; i++) keys[i]: i};
    return SliverMainAxisGroup(
      slivers: [
        if (widget.showSourcePicker) SliverToBoxAdapter(child: _sourcePicker()),
        SliverList.builder(
          itemCount: rows.length,
          findChildIndexCallback: (key) => indices[key],
          itemBuilder: (context, index) => KeyedSubtree(
            key: keys[index],
            child:
                widget.sectionBuilder?.call(rows[index]) ??
                _sectionRow(rows[index]),
          ),
        ),
        if (_loading) SliverToBoxAdapter(child: _shimmerRow()),
      ],
    );
  }

  Widget _content(List<HomeSection> sections) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_sources.isEmpty && _sourceId == 'stremio')
        _stremioEmptyState()
      else if (_sources.isEmpty)
        _emptyState(
          icon: Icons.extension_off_rounded,
          title: context.l10n.sourcesNoneAvailable,
          message: 'Install a source to browse its catalogue here.',
          action: _openSources,
          actionLabel: 'Browse sources',
        )
      else ...[
        if (widget.showSourcePicker) _sourcePicker(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _catalogueContent(sections),
        ),
      ],
    ],
  );

  Widget _catalogueContent(List<HomeSection> sections) {
    if (_loading && _sections == null) {
      return Column(
        key: ValueKey('source-catalogue-loading:$_sourceId'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < 3; i++) _shimmerRow()],
      );
    }
    if (_failed) {
      return Column(
        key: ValueKey('source-catalogue-failed:$_sourceId'),
        children: [
          _emptyState(
            icon: Icons.cloud_off_outlined,
            title: context.l10n.sourcesCouldNotLoadCatalogue,
            message: 'Check your connection and try again.',
            action: () => _load(reset: true),
            actionLabel: 'Try again',
          ),
        ],
      );
    }
    if (!_loading && sections.isEmpty) {
      if (_sourceId == 'stremio') return _stremioEmptyState();
      return Column(
        key: ValueKey('source-catalogue-empty:$_sourceId'),
        children: [
          _emptyState(
            icon: Icons.movie_filter_outlined,
            title: context.l10n.sourcesNoTitlesToShow,
            message: 'This source did not return any home lists.',
            action: () => _load(reset: true),
            actionLabel: 'Refresh',
          ),
        ],
      );
    }
    return Column(
      key: const ValueKey('source-catalogue-content-results'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section
            in widget.sectionBuilder == null
                ? sections
                : providerRowSections(sections, isTv: false))
          widget.sectionBuilder?.call(section) ?? _sectionRow(section),
        if (_loading) _shimmerRow(),
      ],
    );
  }

  Widget _stremioEmptyState() {
    final installed = _stremioManager?.installations.isNotEmpty ?? false;
    final enabled = _stremioManager?.enabled.isNotEmpty ?? false;
    return _emptyState(
      icon: Icons.extension_outlined,
      title: !installed
          ? 'No addons added'
          : !enabled
          ? 'No addons enabled'
          : 'No catalogues to show',
      message: !installed
          ? 'Add a Stremio catalogue addon to start browsing.'
          : !enabled
          ? 'Enable a catalogue addon to browse Stremio here.'
          : 'Check your enabled catalogue addons and connection.',
      action: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const StremioSourcesScreen()),
      ),
      actionLabel: installed ? 'Manage addons' : 'Add addons',
    );
  }

  Widget _shimmerRow() => RowSkeleton(
    itemWidth: posterRowWidth(context),
    itemHeight: posterRowHeight(context),
  );

  Widget _sourcePicker() {
    final id = _sourceId;
    if (id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.extension_outlined, color: AppColors.accent, size: 20),
            const SizedBox(width: 10),
            Text(
              'Source',
              style: AppText.caption.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const ValueKey('source-catalogue-source-picker'),
                  value: id,
                  isExpanded: true,
                  menuMaxHeight: 420,
                  dropdownColor: AppColors.surface,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  style: AppText.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  items: [
                    for (final source in _sources)
                      DropdownMenuItem<String>(
                        value: source.id,
                        child: Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _loading ? null : _selectSource,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionRow(HomeSection section) => ContentRow(
    title: section.title,
    itemCount: section.items.length,
    itemWidth: posterRowWidth(context),
    itemHeight: posterRowHeight(context),
    onSeeAll: () => _openSection(section),
    itemBuilder: (context, index) {
      final item = section.items[index];
      return PosterCard(
        title: item.title,
        logoItem: item,
        imageUrl: item.cover,
        headers: item.coverHeaders,
        cellWidth: posterRowWidth(context),
        wideImageUrl: item.banner,
        genres: item.genres,
        isAdult: item.isAdult,
        qualityBadge: item.quality ?? TitleQualityParser.badge(item.title),
        scoreBadge: item.score,
        dubBadge: item.dubBadge,
        liveBadge: item.liveBadge,
        liveInfo: item.liveInfo,
        liveUnplayable: item.liveUnplayable,
        onTap: () => _openItem(item),
      );
    },
  );

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
    required VoidCallback action,
    required String actionLabel,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.textTertiary),
          const SizedBox(height: 14),
          Text(title, style: AppText.headline, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppText.body.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.tonal(onPressed: action, child: Text(actionLabel)),
        ],
      ),
    ),
  );

  void _openSources() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ProvidersHubScreen()));
}
