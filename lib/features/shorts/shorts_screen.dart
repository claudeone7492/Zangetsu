import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/comments/episode_comments_service.dart';
import '../../core/di/injector.dart';
import '../../core/mode/content_mode.dart';
import '../../core/models/episode.dart';
import '../../core/models/media_item.dart';
import '../../core/models/provider_info.dart';
import '../../core/playback/my_list.dart';
import '../../core/repository/catalogue_repository.dart';
import '../../core/share/share_link.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/route_observer.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';
import '../detail/detail_screen.dart';
import '../home/provider_browse_route.dart' show isProviderExtensionUrl;
import '../player/episode_comments_sheet.dart';
import '../player/mpv_player_pool.dart';

/// A vertical, swipeable feed of what the app's own sources are offering —
/// the "Shorts" destination.
///
/// The app installs its sources itself (see `bundled_pack.dart`), so this
/// screen never asks the user to pick one: it gathers rows from every
/// operational video source already installed and lays them out as a
/// full-bleed vertical feed, one title per swipe.
///
/// The ACTIVE page resolves its first playable episode's stream and plays it
/// inline, muted and looping, TikTok-style. That is best-effort: a title whose
/// stream can't be resolved (or a source that is slow, or a test with no
/// player pool registered) still shows its art and stays tappable, and tapping
/// opens the title's Detail — the same path Home and search use, where the
/// real playback is resolved with the full player. So the feed is a preview,
/// never a second, drifting playback path.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key, this.active = true, this.prewarm = false});

  /// Whether this destination is the one on screen.
  ///
  /// The dock keeps every tab mounted (an [IndexedStack]), so without this the
  /// feed would gather its rows and autoplay its previews while the user is
  /// looking at Home. Defaults to true so a direct pump — the tests, or any
  /// host that shows Shorts on its own — behaves as before.
  final bool active;

  /// Whether to gather the feed while the destination is still off-screen.
  ///
  /// A docked tab that is not selected builds with [active] false and, by
  /// default, does no work at all. The shell sets this true so the Shorts feed
  /// is already gathered — and its first pages already resolved — by the time
  /// the user taps the tab, which is what makes the first swipe play instead of
  /// spin. Playback never starts early: a page still only opens its player when
  /// it is the visible one, so this warms data, not decoders.
  final bool prewarm;

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

/// The one thing a page needs to play its preview: a direct stream URL and the
/// headers it wants. Null when nothing could be resolved.
class _VideoFeedSource {
  const _VideoFeedSource({required this.url, this.headers, this.episode});

  final String url;
  final Map<String, String>? headers;

  /// The episode this preview came from, so the comment thread and the
  /// "Episode N" label name the same thing the player will.
  final Episode? episode;
}

class _ShortsScreenState extends State<ShortsScreen> {
  /// How many sources to pull a feed from, and how long each may take. The
  /// feed must open quickly even if a source is slow, so the first rows in
  /// win and the rest are dropped rather than holding the screen.
  static const int _maxSources = 6;
  static const Duration _perSourceTimeout = Duration(seconds: 8);

  final _pageController = PageController();

  bool _loading = true;
  bool _loadStarted = false;
  List<MediaItem> _items = const [];
  int _index = 0;

  /// Resolved stream per item, keyed by `sourceId:id`, so a page that has
  /// already been warmed reuses its source instead of resolving again. The
  /// value is the in-flight future, so a prefetch and the page's own ask share
  /// one lookup rather than racing two.
  final Map<String, Future<_VideoFeedSource?>> _resolved = {};

  /// How many leading pages to resolve a stream for in the background once the
  /// feed is known, so the first swipes are instant. Kept small: each entry
  /// costs a provider round-trip, and the point is to cover the opening, not
  /// the whole feed.
  static const int _prefetchCount = 3;

  /// Muted by default: the feed autoplays as you swipe, so sound-on would be a
  /// jump-scare. The tap-to-toggle is remembered across pages, like TikTok.
  bool _muted = true;

  @override
  void initState() {
    super.initState();
    // Gather when the destination is on screen, or when the host asked for it
    // to be warmed ahead of the tap. The dock mounts every tab, and a hidden
    // Shorts tab that was not asked to prewarm must not start fetching.
    if (widget.active || widget.prewarm) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void didUpdateWidget(covariant ShortsScreen old) {
    super.didUpdateWidget(old);
    // Leaving the destination rebuilds so the live page tears its preview down
    // (pages read [widget.active]); coming back gathers the feed if it was
    // never started, and the visible page resumes on its own.
    if (!widget.active && old.active) {
      setState(() {});
    } else if ((widget.active || widget.prewarm) && !_loadStarted) {
      _load();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Video sources worth pulling a feed from, the short-drama sources first.
  /// Reading sources are skipped outright — a vertical "short" feed is a video
  /// idea, and manga/novel pages belong in their own readers, so there is no
  /// reason to even fetch their home rows.
  ///
  /// [kShortsPreferredSourceIds] lead so the feed is dominated by the
  /// short-drama catalogues even when other sources were installed earlier; the
  /// rest keep install order behind them. The cap is applied after the reorder,
  /// so a late-installed drama source is never squeezed out by the generic
  /// movie sources that sort ahead of it.
  List<String> _candidateSourceIds(CatalogueRepository repo) {
    final types = manifestSourceTypes();
    final video = repo.loadedSources
        .where((s) => sourceInMode(s.id, ContentMode.anime, types))
        .map((s) => s.id)
        .toList();
    final preferred = video.where(kShortsPreferredSourceIds.contains).toList()
      ..sort(
        (a, b) => kShortsPreferredSourceIds
            .indexOf(a)
            .compareTo(kShortsPreferredSourceIds.indexOf(b)),
      );
    final ordered = <String>[
      ...preferred,
      ...video.where((id) => !kShortsPreferredSourceIds.contains(id)),
    ];
    return ordered.take(_maxSources).toList();
  }

  Future<void> _load() async {
    if (!sl.isRegistered<CatalogueRepository>()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    _loadStarted = true;
    final repo = sl<CatalogueRepository>();
    final ids = _candidateSourceIds(repo);
    final seen = <String>{};
    final gathered = <MediaItem>[];
    for (final id in ids) {
      // A source with a dedicated short-drama feed (`getShorts`, MovieBox
      // today) contributes ONLY its shorts. Its general home rows are skipped
      // for it: they are two dozen movie/TV rails, and letting them in buries
      // the shorts hundreds of swipes down — the feed's whole reason for
      // existing. Every other source keeps the generic home-row behaviour.
      List<MediaItem> fromShorts;
      try {
        fromShorts = await repo.shorts(sourceId: id).timeout(_perSourceTimeout);
      } catch (_) {
        fromShorts = const [];
      }
      if (!mounted) return;
      if (fromShorts.isNotEmpty) {
        for (final item in fromShorts) {
          if (seen.add('${item.sourceId}:${item.id}')) gathered.add(item);
        }
        continue;
      }
      try {
        final sections = await repo
            .home(sourceId: id)
            .timeout(_perSourceTimeout);
        for (final section in sections) {
          for (final item in section.items) {
            if (item.type == ProviderType.manga ||
                item.type == ProviderType.novel) {
              continue;
            }
            // Provider-extension rows (a `browse:` platform/filter handle or a
            // `live:` match) are navigation, not a short — they carry no
            // episode to resolve, so they'd render as a dead poster.
            if (isProviderExtensionUrl(item.url)) continue;
            if (seen.add('${item.sourceId}:${item.id}')) gathered.add(item);
          }
        }
      } catch (_) {
        // One slow or dead source must never sink the feed.
      }
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() {
      _items = gathered;
      _index = 0;
      _loading = false;
    });
    // Warm the opening pages' streams now, in the background, so the first
    // swipes play instead of resolving on the spot.
    _prefetchLeading();
  }

  /// Resolve the first [_prefetchCount] items' streams ahead of time. Each
  /// lookup is memoised in [_resolved], so the page that later becomes visible
  /// finds its stream already in flight (or done) rather than starting over.
  void _prefetchLeading() {
    final n = _items.length < _prefetchCount ? _items.length : _prefetchCount;
    for (var i = 0; i < n; i++) {
      final item = _items[i];
      _resolved.putIfAbsent(
        '${item.sourceId}:${item.id}',
        () => _resolveVideo(item),
      );
    }
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(DetailScreen.route(item));
  }

  /// The stream for [item], resolved once and reused. A page calls this when it
  /// becomes visible; the prefetch calls it too, and whichever is first owns
  /// the lookup — the other awaits the same future.
  Future<_VideoFeedSource?> _resolveCached(MediaItem item) {
    return _resolved.putIfAbsent(
      '${item.sourceId}:${item.id}',
      () => _resolveVideo(item),
    );
  }

  /// Resolve the first playable stream for [item]'s first available episode.
  /// Best-effort: any failure (no episodes, no mirrors, a slow source) yields
  /// null and the page simply falls back to its poster.
  Future<_VideoFeedSource?> _resolveVideo(MediaItem item) async {
    if (!sl.isRegistered<CatalogueRepository>()) return null;
    final repo = sl<CatalogueRepository>();
    try {
      final episodes = await repo
          .episodes(item.url, sourceId: item.sourceId)
          .timeout(_perSourceTimeout);
      if (episodes.isEmpty) return null;
      final ep = episodes.firstWhere(
        (e) => e.available,
        orElse: () => episodes.first,
      );
      final sources = await repo
          .sources(ep.url, sourceId: item.sourceId, fast: true)
          .timeout(_perSourceTimeout);
      if (sources.isEmpty) return null;
      final v = sources.first;
      if (v.url.trim().isEmpty) return null;
      return _VideoFeedSource(url: v.url, headers: v.headers, episode: ep);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(context.l10n.shorts, style: AppText.barTitle),
        actions: [
          IconButton(
            tooltip: context.l10n.retry,
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    // Off-screen and not warming (a dock tab that isn't showing and wasn't
    // asked to prewarm): drop the whole feed, which disposes the live preview
    // with it. [didUpdateWidget] rebuilds it the moment the destination is
    // selected again — no refetch, the rows stay. A prewarming tab builds it
    // (IndexedStack paints only the selected child) so the opening page can
    // hold its first frame ready.
    if (!widget.active && !widget.prewarm) return const SizedBox.shrink();
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.bolt_outlined,
        message: context.l10n.noResults,
        actionLabel: context.l10n.tryAgain,
        onAction: _load,
      );
    }
    // While prewarming (built but not yet visible), the page that will be
    // visible on the tap is the one worth decoding, so it holds its frame.
    final warming = widget.prewarm && !widget.active;
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _items.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => _ShortPage(
            key: ValueKey('${_items[i].sourceId}:${_items[i].id}'),
            item: _items[i],
            // Only the page in view holds a playing player, so a long feed
            // never keeps a pile of live decoders alive — and while the whole
            // destination is off-screen, no page plays at all. The neighbour
            // pages (and the page that will open, while warming) resolve and
            // hold their first frame, which is what makes the first swipe and
            // the first open land on moving video.
            active: widget.active && i == _index,
            near: widget.active
                ? (i - _index).abs() == 1
                : (warming && i == _index),
            muted: _muted,
            onToggleMute: () => setState(() => _muted = !_muted),
            onOpen: () => _open(_items[i]),
            resolveVideo: () => _resolveCached(_items[i]),
          ),
        ),
        // Position read-out — a long feed with no sense of place is
        // disorienting, and the dock hides the scrollbar.
        Positioned(
          left: 12,
          bottom: 24,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                '${_index + 1} / ${_items.length}',
                style: AppText.caption.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One full-bleed page of the feed: the title's inline preview (or its art),
/// a scrim, its name/source, and a TikTok-style action rail. Tapping the video
/// toggles sound; the rail opens the title's Detail.
class _ShortPage extends StatefulWidget {
  const _ShortPage({
    super.key,
    required this.item,
    required this.active,
    required this.muted,
    required this.onToggleMute,
    required this.onOpen,
    required this.resolveVideo,
    this.near = false,
  });

  final MediaItem item;
  final bool active;

  /// True for the pages one step either side of the visible one. They resolve
  /// their stream and hold the first frame paused, so the swipe that brings one
  /// in starts on moving video instead of a spinner. They never play.
  final bool near;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onOpen;
  final Future<_VideoFeedSource?> Function() resolveVideo;

  @override
  State<_ShortPage> createState() => _ShortPageState();
}

class _ShortPageState extends State<_ShortPage> with RouteAware {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<bool>? _playingSub;
  _VideoFeedSource? _source;
  bool _resolving = false;
  bool _resolved = false;
  bool _saved = false;
  bool _failed = false;

  /// True while another route (a Detail page opened from the rail) sits on
  /// top. The preview pauses rather than decoding video behind what the user
  /// is actually looking at — the same reason the detail hero watches the
  /// route.
  bool _covered = false;
  ModalRoute<dynamic>? _route;

  @override
  void initState() {
    super.initState();
    _syncSaved();
    if (widget.active) {
      _activate();
    } else if (widget.near) {
      _preload();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    if (_route != null) appRouteObserver.unsubscribe(this);
    _route = route;
    if (route is PageRoute<dynamic>) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPushNext() {
    _covered = true;
    unawaited(_player?.pause());
  }

  @override
  void didPopNext() {
    _covered = false;
    final player = _player;
    if (widget.active && player != null) unawaited(player.play());
  }

  @override
  void didUpdateWidget(covariant _ShortPage old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      if (!old.active) {
        // Coming into view: resume a preloaded player, or start one now.
        _activate();
      } else if (widget.muted != old.muted) {
        _applyVolume();
      }
      return;
    }
    // Not the visible page. A neighbour is kept warm (resolved, first frame
    // held, paused); anything further is freed. The page that was visible also
    // lands here when the destination leaves — paused, so no audio plays on
    // behind the tab the user switched to.
    if (widget.near) {
      if (!old.near) _preload();
      unawaited(_player?.pause());
    } else if (old.active || old.near) {
      _deactivate();
    }
  }

  @override
  void dispose() {
    if (_route != null) appRouteObserver.unsubscribe(this);
    _playingSub?.cancel();
    _disposePlayer();
    super.dispose();
  }

  void _syncSaved() {
    if (!sl.isRegistered<MyListStore>()) return;
    _saved = sl<MyListStore>().contains(widget.item);
  }

  /// Resolve the preview and start it playing. A page already warmed by
  /// [_preload] only needs resuming — its player holds the first frame.
  Future<void> _activate() async {
    if (!sl.isRegistered<MpvPlayerPool>()) return;
    final existing = _player;
    if (existing != null) {
      _applyVolume();
      unawaited(existing.play());
      return;
    }
    await _resolveAndOpen(play: true);
  }

  /// Resolve the preview and open it paused, so the first frame is decoded and
  /// waiting. Never plays: this is a neighbour page, not the visible one.
  Future<void> _preload() async {
    if (!sl.isRegistered<MpvPlayerPool>()) return;
    if (_player != null || _resolving) return;
    await _resolveAndOpen(play: false);
  }

  /// Resolve [widget.item]'s stream and open a player for it. [play] decides
  /// whether it starts immediately (the visible page) or holds its first frame
  /// (a neighbour being warmed).
  Future<void> _resolveAndOpen({required bool play}) async {
    if (_resolving || _player != null) return;
    setState(() => _resolving = true);
    final source = await widget.resolveVideo();
    if (!mounted) return;
    if (source == null) {
      setState(() {
        _resolving = false;
        _resolved = true;
        _failed = true;
      });
      return;
    }
    _source = source;
    await _startPlayback(source, play: play);
    if (!mounted) return;
    setState(() {
      _resolving = false;
      _resolved = true;
    });
  }

  Future<void> _startPlayback(
    _VideoFeedSource source, {
    required bool play,
  }) async {
    final pool = sl<MpvPlayerPool>();
    final player = pool.acquire(libass: false);
    final controller = VideoController(player);
    _player = player;
    _videoController = controller;
    // Mount the Video widget before opening so media_kit's output exists
    // first; opening into an unmounted texture can sit paused on some engines.
    if (mounted) setState(() {});
    _playingSub = player.stream.playing.listen((playing) {
      if (!mounted || player != _player) return;
      // Keeps the stream wired before open() resolves and repaints the frame
      // once playback actually starts, mirroring the detail hero's warm-up.
      if (playing) setState(() {});
    });
    try {
      await player.setVolume(widget.muted ? 0 : 100);
      await player.setPlaylistMode(PlaylistMode.single);
      await player.open(
        Media(source.url, httpHeaders: source.headers),
        // A preloaded neighbour opens paused to hold its frame; the visible
        // page opens playing. If a Detail page was opened while the preview was
        // resolving, don't start decoding behind it — didPopNext resumes.
        play: play && !_covered,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  void _deactivate() {
    _playingSub?.cancel();
    _playingSub = null;
    _disposePlayer();
    if (mounted) setState(() {});
  }

  void _disposePlayer() {
    final player = _player;
    _player = null;
    _videoController = null;
    if (player != null) unawaited(player.dispose());
  }

  void _applyVolume() {
    final player = _player;
    if (player == null) return;
    unawaited(player.setVolume(widget.muted ? 0 : 100));
  }

  Future<void> _toggleSave() async {
    if (!sl.isRegistered<MyListStore>()) return;
    final store = sl<MyListStore>();
    final wasSaved = store.contains(widget.item);
    await store.toggle(widget.item);
    if (!mounted) return;
    setState(() => _saved = !wasSaved);
  }

  void _share() {
    SharePlus.instance.share(
      ShareParams(text: ShareLink.shareText(widget.item)),
    );
  }

  void _comments() {
    if (!sl.isRegistered<EpisodeCommentsService>()) return;
    showEpisodeCommentsSheet(
      context,
      sourceId: widget.item.sourceId,
      showId: widget.item.id,
      episodeId: _source?.episode?.id ?? widget.item.id,
      episodeLabel: _source?.episode?.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final art = item.banner?.trim().isNotEmpty == true
        ? item.banner!
        : item.cover;
    final sourceName = sl.isRegistered<CatalogueRepository>()
        ? sl<CatalogueRepository>().displayName(item.sourceId)
        : item.sourceId;
    final controller = _videoController;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (controller != null)
          Video(
            controller: controller,
            // No chrome: the tap surface below owns mute, and a preview has no
            // business showing a scrub bar.
            controls: NoVideoControls,
            fit: BoxFit.cover,
          )
        else if (art != null && art.isNotEmpty)
          CachedNetworkImage(
            imageUrl: art,
            httpHeaders: item.coverHeaders,
            fit: BoxFit.cover,
            placeholder: (_, _) => ColoredBox(color: AppColors.surface),
            errorWidget: (_, _, _) => ColoredBox(color: AppColors.surface),
          )
        else
          ColoredBox(color: AppColors.surface),
        // Tap surface: toggles sound once a preview is up; otherwise opens the
        // title. Sits below the rail so the rail buttons stay independent.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: controller != null ? widget.onToggleMute : widget.onOpen,
          ),
        ),
        if (_resolving && controller == null)
          const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        if (_resolved && _failed && controller == null)
          const Center(
            child: Icon(
              Icons.play_circle_outline_rounded,
              size: 56,
              color: Colors.white70,
            ),
          ),
        // Bottom-up scrim so the title stays readable over any art or video.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 84,
          bottom: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.title,
                style: AppText.title.copyWith(color: Colors.white),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.play_circle_fill_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      sourceName,
                      style: AppText.caption.copyWith(color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (controller != null)
          Positioned(
            left: 20,
            bottom: 24,
            child: Icon(
              widget.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white70,
              size: 20,
            ),
          ),
        Positioned(
          right: 10,
          bottom: 48,
          child: _ActionRail(
            saved: _saved,
            onSave: _toggleSave,
            onComments: _comments,
            onShare: _share,
            onDetails: widget.onOpen,
          ),
        ),
      ],
    );
  }
}

/// The vertical column of round actions down the right edge — save, comments,
/// share, and a way through to the title's full page.
class _ActionRail extends StatelessWidget {
  const _ActionRail({
    required this.saved,
    required this.onSave,
    required this.onComments,
    required this.onShare,
    required this.onDetails,
  });

  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onComments;
  final VoidCallback onShare;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          icon: saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          label: saved ? context.l10n.saved : context.l10n.save,
          onTap: onSave,
        ),
        _RailButton(
          icon: Icons.mode_comment_outlined,
          label: context.l10n.comments,
          onTap: onComments,
        ),
        _RailButton(
          icon: Icons.ios_share_rounded,
          label: context.l10n.share,
          onTap: onShare,
        ),
        _RailButton(
          icon: Icons.info_outline_rounded,
          label: context.l10n.showDetails,
          onTap: onDetails,
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: AppText.caption.copyWith(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
