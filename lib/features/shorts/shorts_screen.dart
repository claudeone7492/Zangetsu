import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_config.dart';
import '../../core/comments/episode_comments_service.dart';
import '../../core/di/injector.dart';
import '../../core/models/episode.dart';
import '../../core/models/episode_title.dart';
import '../../core/models/media_item.dart';
import '../../core/models/provider_info.dart';
import '../../core/playback/my_list.dart';
import '../../core/repository/catalogue_repository.dart';
import '../../core/repository/source_repository.dart';
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

  /// The whole gathered feed before paging: [_items] starts as a shuffled copy
  /// of it and [_appendMore] keeps drawing shuffled batches from it, so the
  /// feed never repeats the same drama back-to-back and never runs out.
  List<MediaItem> _pool = const [];

  /// Guards [_appendMore] against re-entering while a batch is being built.
  bool _appending = false;

  /// How many pages [_appendMore] adds each time the feed nears its end, and
  /// how many shuffled passes it may make through the pool to find that many
  /// unseen items. Bounded so a small pool simply stops instead of spinning.
  static const int _appendBatch = 12;
  static const int _maxAppendPasses = 4;

  /// The source ids the last gather walked. A docked tab warms at boot, but
  /// providers finish loading on their own schedule, so the first gather can
  /// run before any source is installed and come back empty. Re-gathering when
  /// the tab is opened AND the source set has grown turns that empty warm into
  /// a populated feed instead of a permanently blank tab.
  List<String> _gatheredFrom = const [];

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

  /// Sound is on from the first page — a feed that opens silent reads as
  /// broken. Tapping the video toggles it, and the choice is remembered across
  /// pages, like TikTok.
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    // Gather when the destination is on screen, or when the host asked for it
    // to be warmed ahead of the tap. The dock mounts every tab, and a hidden
    // Shorts tab that was not asked to prewarm must not start fetching.
    if (widget.active || widget.prewarm) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    // The boot race: this tab warms before the JS providers finish loading, so
    // the first gather can walk an empty source set and leave the feed blank.
    // Re-gather the moment the source set is populated, so a tab the user has
    // not tapped yet is already full by the time they do.
    sourcesRevision.addListener(_onSourcesChanged);
  }

  void _onSourcesChanged() {
    if (!mounted || !(widget.active || widget.prewarm)) return;
    if (_shouldRetry) _load();
  }

  @override
  void didUpdateWidget(covariant ShortsScreen old) {
    super.didUpdateWidget(old);
    // Leaving the destination rebuilds so the live page tears its preview down
    // (pages read [widget.active]); coming back gathers the feed if it was
    // never started, and the visible page resumes on its own.
    if (!widget.active && old.active) {
      setState(() {});
    } else if (widget.active || widget.prewarm) {
      // Coming into view, or still warming: gather if it was never started, or
      // retry when the earlier gather found no sources — a docked tab can warm
      // before provider load finishes, and an empty feed there must not stick.
      if (!_loadStarted || _shouldRetry) {
        _load();
      }
    }
  }

  /// True when the last gather came back with nothing while more sources are
  /// installed now than it walked. The boot race: the tab warms before the
  /// providers finish loading, so the first gather sees no sources; the tap
  /// that opens it must re-gather rather than show the empty state forever.
  bool get _shouldRetry {
    if (_items.isNotEmpty || !sl.isRegistered<SourceRepository>()) return false;
    final now = _candidateSourceIds(sl<SourceRepository>());
    return now.isNotEmpty && !_sameIds(now, _gatheredFrom);
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    sourcesRevision.removeListener(_onSourcesChanged);
    _pageController.dispose();
    super.dispose();
  }

  /// The short-drama sources installed right now, drama catalogues first.
  ///
  /// The feed is a SHORT-DRAMA surface: "the reels page should be only drama
  /// shorts nothing more, no any other providers should be there". So it draws
  /// from [kShortDramaSourceIds] only — the catalogues built end to end around
  /// serialized short dramas — rather than walking every installed video source
  /// and folding each one's movie/TV home rows in behind the dramas (which is
  /// exactly how feature films leaked into the feed). The order is the config's,
  /// so the leading catalogue is stable and the feed is drama-weighted before
  /// its shuffle. A source that isn't installed is skipped.
  List<String> _candidateSourceIds(SourceRepository repo) {
    return kShortDramaSourceIds
        .where(repo.hasSource)
        .take(_maxSources)
        .toList();
  }

  Future<void> _load() async {
    if (!sl.isRegistered<SourceRepository>()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    _loadStarted = true;
    // The SOURCE repository directly, not the Z Mode router: the router's
    // `loadedSources`/`home` follow the metadata toggle, so under Z Mode the
    // feed walked the metadata pseudo-source and filled with AniList/TMDB
    // anime rows instead of the drama catalogues' own rows. Same reasoning as
    // `LiveTvScreen`.
    final repo = sl<SourceRepository>();
    final ids = _candidateSourceIds(repo);
    _gatheredFrom = ids;
    // Walk the sources CONCURRENTLY: gathered one after another, six sources at
    // up to 8s each could hold the feed for the best part of a minute on a slow
    // network — the exact spinner the prewarm exists to avoid. Run in parallel
    // and each row simply arrives whenever its own source answers, in the
    // order [ids] lists them so the drama sources still lead.
    final perSource = await Future.wait([
      for (final id in ids) _gatherFrom(repo, id),
    ]);
    if (!mounted) return;
    final seen = <String>{};
    final gathered = <MediaItem>[];
    for (final rows in perSource) {
      for (final item in rows) {
        if (seen.add('${item.sourceId}:${item.id}')) gathered.add(item);
      }
    }
    // Shuffle the pool so the feed is a discovery surface, not a replay of the
    // first source's rails in the same order every launch — the source rows
    // are near-identical between opens, so an unshuffled feed shows the same
    // dramas at the top forever. The drama sources still lead the gather, so
    // the pool is drama-weighted before the shuffle.
    _pool = _shuffled(gathered);
    setState(() {
      _items = _pool;
      _index = 0;
      _loading = false;
    });
    // Warm the opening pages' streams now, in the background, so the first
    // swipes play instead of resolving on the spot.
    _prefetchLeading();
  }

  /// [items] reordered with a fresh random seed. The pool is the whole feed, so
  /// the shuffle is what keeps two visits from opening on the same dramas.
  List<MediaItem> _shuffled(List<MediaItem> items) {
    final copy = List<MediaItem>.of(items);
    copy.shuffle(Random());
    return copy;
  }

  /// Appends the next batch of the pool when the feed nears its end, so the
  /// swipe never hits a wall. Unseen dramas are drawn first; once the pool is
  /// exhausted it is reshuffled and cycled again, and the same drama is never
  /// appended twice in a row — the endless scroll the feed is for.
  void _appendMore() {
    if (_pool.isEmpty || _appending) return;
    _appending = true;
    final shown = {for (final i in _items) '${i.sourceId}:${i.id}'};
    final batch = <MediaItem>[];
    String? lastKey = _items.isEmpty
        ? null
        : '${_items.last.sourceId}:${_items.last.id}';
    for (
      var pass = 0;
      pass < _maxAppendPasses && batch.length < _appendBatch;
      pass++
    ) {
      final unseenOnly = pass == 0;
      for (final item in _shuffled(_pool)) {
        final key = '${item.sourceId}:${item.id}';
        if (unseenOnly && shown.contains(key)) continue;
        if (key == lastKey) continue;
        batch.add(item);
        shown.add(key);
        lastKey = key;
        if (batch.length >= _appendBatch) break;
      }
    }
    _appending = false;
    if (batch.isEmpty || !mounted) return;
    setState(() => _items = [..._items, ...batch]);
  }

  /// The rows one source contributes to the feed.
  ///
  /// A short-drama catalogue's dedicated `getShorts` feed is used when it has
  /// one — it is dramas and nothing else, which is the whole point of the feed.
  /// Only when that feed is empty do the catalogues whose OWN home rows are
  /// short dramas end to end ([kDramaOnlyHomeSourceIds]) fall back to their home
  /// rows; MovieBox's home is two dozen movie/TV rails, so it is served by
  /// `getShorts` alone and never leaks films into a drama feed. Every item is
  /// run through [_dramaItems], so a reading title or a navigation handle can
  /// never render as a dead poster. Never throws: one slow or dead source must
  /// not sink the feed.
  Future<List<MediaItem>> _gatherFrom(SourceRepository repo, String id) async {
    try {
      final shorts = await repo
          .shorts(sourceId: id)
          .timeout(_perSourceTimeout);
      final items = _dramaItems(shorts);
      if (items.isNotEmpty) return items;
    } catch (_) {
      // Fall through to the home rows.
    }
    if (!kDramaOnlyHomeSourceIds.contains(id)) return const [];
    try {
      final sections = await repo.home(sourceId: id).timeout(_perSourceTimeout);
      return [for (final section in sections) ..._dramaItems(section.items)];
    } catch (_) {
      return const [];
    }
  }

  /// [items] with the rows a vertical drama feed must never show removed: the
  /// reading titles (manga/novel belong in their own readers) and the
  /// provider-extension rows (a `browse:` platform/filter handle or a live
  /// match is navigation, not a short — it carries no episode to resolve, so it
  /// would render as a dead poster).
  List<MediaItem> _dramaItems(List<MediaItem> items) {
    final out = <MediaItem>[];
    for (final item in items) {
      if (item.type == ProviderType.manga ||
          item.type == ProviderType.novel) {
        continue;
      }
      if (isProviderExtensionUrl(item.url)) continue;
      out.add(item);
    }
    return out;
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
    if (!sl.isRegistered<SourceRepository>()) return null;
    final repo = sl<SourceRepository>();
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
    // No app bar: the feed is full-bleed, so the first frame reaches the top
    // edge and the reels read as a single immersive surface rather than a
    // screen with a chrome strip. A reload lives on the empty state's action.
    return Scaffold(backgroundColor: Colors.black, body: _body());
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
      // A preloader shaped like a reel page, not a spinner: the feed is a
      // full-bleed vertical surface, and a spinner in the middle of a black
      // page reads as "broken" for the second it takes the drama sources to
      // answer. The placeholder keeps the page's shape while the prewarm
      // (see [widget.prewarm]) finishes behind it.
      return const _ReelsPreloader();
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
          onPageChanged: (i) {
            setState(() => _index = i);
            // Approaching the end: append a fresh shuffled batch behind the
            // pages already seen so the swipe keeps going.
            if (i >= _items.length - _prefetchCount) _appendMore();
          },
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

  /// Playback state for the paused affordance. The progress bar reads the
  /// player's position stream directly, so it does not rebuild the video.
  bool _paused = false;

  /// Transient "−10s" / "+10s" badge shown after a double-tap seek, fading out
  /// once the jump has landed. Null when no seek is in flight.
  String? _seekFlash;
  Timer? _seekFlashTimer;

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
    _seekFlashTimer?.cancel();
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
      // Drives both the paused affordance and a repaint once the first frame
      // lands (mirroring the detail hero's warm-up), so the card never sits on
      // a stale frame while the decoder spins up.
      if (mounted) setState(() => _paused = !playing);
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

  /// Double-tap seek: jump [delta] from the current position, clamped into the
  /// clip, and flash a "±Ns" badge. A no-op until the stream has a duration —
  /// seeking a live preview is meaningless.
  void _seekBy(Duration delta) {
    final player = _player;
    if (player == null) return;
    final duration = player.state.duration;
    if (duration <= Duration.zero) return;
    var target = player.state.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (target > duration) target = duration;
    unawaited(player.seek(target));
    setState(() => _seekFlash = delta.isNegative ? '−10s' : '+10s');
    _seekFlashTimer?.cancel();
    _seekFlashTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFlash = null);
    });
  }

  void _togglePlay() {
    final player = _player;
    if (player == null) return;
    unawaited(player.playOrPause());
  }

  /// Right/left thirds are the seek zones (the TikTok gesture); the middle
  /// third pauses. The player's own playing stream keeps [_paused] honest, so
  /// this only has to issue the command.
  void _onDoubleTapDown(TapDownDetails details, double width) {
    final player = _player;
    if (player == null) {
      widget.onOpen();
      return;
    }
    final x = details.localPosition.dx;
    if (x < width / 3) {
      _seekBy(const Duration(seconds: -10));
    } else if (x > width * 2 / 3) {
      _seekBy(const Duration(seconds: 10));
    } else {
      _togglePlay();
    }
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

  /// "Episode N · title" for the resolved preview, or null before it resolves
  /// (or when the source gave no episode at all — a bare movie). Shown under
  /// the title so the card names the part that is playing.
  String? get _episodeLabel {
    final ep = _source?.episode;
    if (ep == null) return null;
    return episodeDisplayTitle(ep, number: ep.number?.toInt());
  }

  /// The compact fact chips under the title: live state, score, year, quality
  /// and the first couple of genres. Only what the item actually carries — a
  /// bare title with no metadata renders no chip row at all.
  List<Widget> _metaChips(MediaItem item) {
    final chips = <Widget>[];
    if (item.liveBadge != null && item.liveBadge!.trim().isNotEmpty) {
      chips.add(_MetaChip(label: item.liveBadge!, live: true));
    }
    if (item.score != null && item.score! > 0) {
      chips.add(_MetaChip(label: '★ ${(item.score! / 10).toStringAsFixed(1)}'));
    }
    if (item.year != null) chips.add(_MetaChip(label: '${item.year}'));
    if (item.quality != null && item.quality!.trim().isNotEmpty) {
      chips.add(_MetaChip(label: item.quality!));
    }
    for (final g in item.genres.take(2)) {
      chips.add(_MetaChip(label: g));
    }
    return chips;
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
        // Gesture surface. With a preview up it is the TikTok layout: double
        // tap left/right thirds to jump ±10s, double tap the middle to play or
        // pause, single tap toggles sound (long press would fight the swipe).
        // Before a preview resolves, a tap simply opens the title. Sits below
        // the rail so the rail buttons stay independent.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: controller != null ? widget.onToggleMute : widget.onOpen,
              onDoubleTapDown: controller != null
                  ? (d) => _onDoubleTapDown(d, constraints.maxWidth)
                  : null,
              onDoubleTap: () {},
            ),
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
        // Transient seek badge, centred like the ±10s feedback every modern
        // reels player shows.
        if (_seekFlash != null)
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Text(
                  _seekFlash!,
                  style: AppText.title.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        // Paused affordance: a soft play glyph over the frame so a paused
        // preview reads as paused, not frozen.
        if (controller != null && _paused && _seekFlash == null)
          const Center(
            child: Icon(
              Icons.play_arrow_rounded,
              size: 72,
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
              // The title doubles as a route to the full page: the tap surface
              // above only toggles sound, so without this the name was the one
              // bit of the card that looked tappable and wasn't.
              GestureDetector(
                onTap: widget.onOpen,
                child: Text(
                  item.title,
                  style: AppText.title.copyWith(color: Colors.white),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
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
              // The episode the preview resolved, so a swipe into a drama shows
              // which part is playing rather than a bare title.
              if (_episodeLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  _episodeLabel!,
                  style: AppText.caption.copyWith(color: Colors.white60),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // Enrichment: the facts a viewer uses to decide whether to keep
              // watching — score, year, quality, live state, genres — as one
              // compact chip row, so the card reads like a discovery card and
              // not just a title over a video.
              if (_metaChips(item).isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: _metaChips(item)),
              ],
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
        // Thin scrub bar pinned to the very bottom edge: the reels equivalent
        // of the player's timeline. It reads the position stream itself, so a
        // frame-by-frame tick never rebuilds the video widget above it.
        if (controller != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FeedProgressBar(player: controller.player),
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

/// A hairline scrub bar for the reels page. It listens to the player's own
/// position and duration streams so the surrounding page never rebuilds per
/// frame; only this thin strip repaints.
class _FeedProgressBar extends StatelessWidget {
  const _FeedProgressBar({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.position,
      builder: (context, posSnap) {
        return StreamBuilder<Duration>(
          stream: player.stream.duration,
          builder: (context, durSnap) {
            final position = posSnap.data ?? Duration.zero;
            final duration = durSnap.data ?? Duration.zero;
            final progress = duration.inMilliseconds <= 0
                ? 0.0
                : (position.inMilliseconds / duration.inMilliseconds).clamp(
                    0.0,
                    1.0,
                  );
            return SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: 0.18),
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent),
              ),
            );
          },
        );
      },
    );
  }
}

/// A small translucent pill for the fact row on a reels card. [live] tints it
/// with the accent so a live badge reads as live, not as another genre tag.
class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.live = false});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: live
            ? AppColors.accent.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: live
              ? AppColors.accent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: live ? AppColors.accent : Colors.white,
            fontWeight: live ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
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

/// The Reels feed's preloader: a full-bleed placeholder shaped like one reel
/// page (art block, name strip, action rail) with a single shared shimmer.
///
/// It exists so the page is "fully populated" on mount: the dock prewarms the
/// feed while the tab is off-screen (see [ShortsScreen.prewarm]) and this is
/// what paints in the meantime — the same shape the real page will have, not a
/// spinner floating in a black void.
class _ReelsPreloader extends StatefulWidget {
  const _ReelsPreloader();

  @override
  State<_ReelsPreloader> createState() => _ReelsPreloaderState();
}

class _ReelsPreloaderState extends State<_ReelsPreloader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final shimmer = AppColors.surface2.withValues(
          alpha: 0.18 + 0.12 * _ctrl.value,
        );
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: AppColors.bg),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 96, 56),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _bar(shimmer, width: 220, height: 20),
                    const SizedBox(height: 10),
                    _bar(shimmer, width: 140, height: 14),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, bottom: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 4; i++) ...[
                      ClipOval(
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: ColoredBox(color: shimmer),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bar(Color color, {required double width, required double height}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: width,
          height: height,
          child: ColoredBox(color: color),
        ),
      );
}
