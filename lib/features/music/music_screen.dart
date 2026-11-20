import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/music/music_models.dart';
import '../../core/music/music_player_controller.dart';
import '../../core/music/music_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import 'music_player_sheet.dart';

/// Music mode's Home.
///
/// A screen of its own rather than a branch inside `HomeScreen`. The video Home
/// is built around sources, hero banners, tracker rows and per-source
/// catalogues; none of that has a meaning for a song, so sharing the widget
/// would mean every one of those sections asking "am I music?" before it draws.
///
/// [active] is false while the dock shows another tab. Rows already loaded are
/// kept so switching back is instant, but no request starts, because building
/// the music tab for a viewer who is watching something else is pure cost.
class MusicScreen extends StatefulWidget {
  const MusicScreen({super.key, this.active = true, this.searchOnOpen = false});

  final bool active;

  /// Opens straight into the search field and skips the Home rows. The dock's
  /// Search tab uses this so searching in music mode searches songs, not the
  /// movie metadata the shared Search screen would otherwise offer.
  final bool searchOnOpen;

  @override
  State<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends State<MusicScreen> {
  late final MusicService _service = sl<MusicService>();
  late final MusicPlayerController _player = sl<MusicPlayerController>();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  List<MusicSection>? _sections;
  bool _loading = false;
  String? _loadError;

  List<MusicTrack>? _results;
  bool _searching = false;
  String? _searchError;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryTextChanged);
    if (widget.searchOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    } else if (widget.active) {
      unawaited(_loadHome());
    }
  }

  @override
  void didUpdateWidget(MusicScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchOnOpen) return;
    if (widget.active && !oldWidget.active && _sections == null && !_loading) {
      unawaited(_loadHome());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Rebuilds for the clear button's visibility. Cheap: one header row.
  void _onQueryTextChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadHome() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final sections = await _service.home();
      if (!mounted) return;
      setState(() {
        _sections = sections;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = context.l10n.musicUnavailableBody;
        _loading = false;
      });
    }
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = null;
        _query = '';
        _searchError = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _searchError = null;
      _query = trimmed;
    });
    try {
      final results = await _service.search(trimmed);
      // A slower earlier query must not overwrite a newer one's results.
      if (!mounted || _query != trimmed) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || _query != trimmed) return;
      setState(() {
        _searchError = context.l10n.musicSearchFailed;
        _searching = false;
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() {
      _results = null;
      _query = '';
      _searchError = null;
    });
  }

  Future<void> _playTrack(List<MusicTrack> from, MusicTrack track) async {
    await _player.playFrom(from, track);
    if (!mounted) return;
    if (_player.error != null) {
      _player.clearError();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.musicCantPlayBody)));
      return;
    }
    await showMusicPlayerSheet(context, _player);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              title: widget.searchOnOpen
                  ? context.l10n.musicSearchSongs
                  : context.l10n.modeMusic,
              controller: _searchController,
              focusNode: _searchFocus,
              onSubmitted: _runSearch,
              onClear: _clearSearch,
            ),
            Expanded(child: _body()),
            _MiniPlayer(
              player: _player,
              onOpen: () => showMusicPlayerSheet(context, _player),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    // No usable catalogue is a different problem from an empty one: "No songs
    // here yet" would send the viewer looking for another row that cannot
    // exist. Ask the service first, before any request is attempted.
    if (!_service.isAvailable) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.musicUnavailable,
        body: context.l10n.musicUnavailableBody,
      );
    }
    if (_query.isNotEmpty) return _searchBody();

    if (_loading && _sections == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _loadError;
    if (error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.musicUnavailable,
        body: error,
        action: context.l10n.retry,
        onAction: _loadHome,
      );
    }
    final sections = _sections;
    if (sections == null) return const SizedBox.shrink();
    if (sections.isEmpty) {
      return _Message(
        icon: Icons.music_off_rounded,
        title: context.l10n.musicNoTracks,
        body: context.l10n.musicNoTracksBody,
        action: context.l10n.retry,
        onAction: _loadHome,
      );
    }
    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      onRefresh: _loadHome,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: sections.length,
        itemBuilder: (context, i) {
          final section = sections[i];
          return _Section(
            section: section,
            onTap: (track) => _playTrack(section.tracks, track),
          );
        },
      ),
    );
  }

  Widget _searchBody() {
    if (_searching) return const Center(child: CircularProgressIndicator());
    final error = _searchError;
    if (error != null) {
      return _Message(
        icon: Icons.cloud_off_rounded,
        title: error,
        action: context.l10n.retry,
        onAction: () => _runSearch(_query),
      );
    }
    final results = _results;
    if (results == null) {
      // Nothing typed yet: prompt rather than leaving the tab blank.
      return _Message(
        icon: Icons.search_rounded,
        title: context.l10n.musicSearchHint,
      );
    }
    if (results.isEmpty) {
      return _Message(
        icon: Icons.search_off_rounded,
        title: context.l10n.noResults,
      );
    }
    return _TrackList(
      tracks: results,
      onTap: (track) => _playTrack(results, track),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
  });

  final String title;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note_rounded, color: AppColors.accent, size: 26),
              const SizedBox(width: 10),
              Text(title, style: AppText.largeTitle),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            focusNode: focusNode,
            style: AppText.body,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: context.l10n.musicSearchHint,
              hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: AppColors.textTertiary,
              ),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: AppColors.textTertiary,
                      onPressed: onClear,
                    ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section, required this.onTap});

  final MusicSection section;
  final ValueChanged<MusicTrack> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
          child: Text(section.titleLabel(context), style: AppText.headline),
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: section.tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final track = section.tracks[i];
              return _TrackCard(track: track, onTap: () => onTap(track));
            },
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({required this.track, required this.onTap});

  final MusicTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 124,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MusicArtwork(url: track.artwork, size: 124),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              track.artistLabel(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Album art with a note glyph for a missing or broken image.
class MusicArtwork extends StatelessWidget {
  const MusicArtwork({super.key, required this.url, required this.size});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final artwork = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: size,
        height: size,
        child: artwork == null || artwork.isEmpty
            ? const _ArtworkFallback()
            : Image.network(
                artwork,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _ArtworkFallback(),
              ),
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface2,
      child: const Icon(
        Icons.music_note_rounded,
        color: AppColors.textTertiary,
        size: 32,
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.tracks, required this.onTap});

  final List<MusicTrack> tracks;
  final ValueChanged<MusicTrack> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: tracks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (context, i) {
        final track = tracks[i];
        return ListTile(
          onTap: () => onTap(track),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: MusicArtwork(url: track.artwork, size: 48),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.body,
          ),
          subtitle: Text(
            track.artistLabel(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: AppColors.textTertiary),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = action;
    final tap = onAction;
    final detail = body;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: AppText.body),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ],
            if (label != null && tap != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: tap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: Text(label),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bar above the dock while a song is loaded.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.player, required this.onOpen});

  final MusicPlayerController player;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        return GestureDetector(
          onTap: onOpen,
          behavior: HitTestBehavior.opaque,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                MusicArtwork(url: track.artwork, size: 42),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        track.artistLabel(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: player.togglePlayPause,
                  icon: Icon(
                    player.buffering
                        ? Icons.hourglass_top_rounded
                        : player.playing
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  onPressed: player.next,
                  icon: const Icon(
                    Icons.skip_next_rounded,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
