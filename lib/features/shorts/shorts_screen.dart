import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/models/media_item.dart';
import '../../core/models/provider_info.dart';
import '../../core/repository/catalogue_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/states.dart';
import '../../l10n/l10n.dart';
import '../detail/detail_screen.dart';

/// A vertical, swipeable feed of what the app's own sources are offering —
/// the "Shorts" destination.
///
/// The app installs its sources itself (see `bundled_pack.dart`), so this
/// screen never asks the user to pick one: it gathers rows from every
/// operational video source already installed and lays them out as a
/// full-bleed vertical feed, one title per swipe. Tapping a page opens the
/// title's Detail, where the real playback/reader is resolved — the same path
/// Home and search use, so nothing here can drift from them.
class ShortsScreen extends StatefulWidget {
  const ShortsScreen({super.key});

  @override
  State<ShortsScreen> createState() => _ShortsScreenState();
}

class _ShortsScreenState extends State<ShortsScreen> {
  /// How many sources to pull a feed from, and how long each may take. The
  /// feed must open quickly even if a source is slow, so the first rows in
  /// win and the rest are dropped rather than holding the screen.
  static const int _maxSources = 6;
  static const Duration _perSourceTimeout = Duration(seconds: 8);

  final _pageController = PageController();

  bool _loading = true;
  List<MediaItem> _items = const [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Video sources worth pulling a feed from, in install order. Reading modes
  /// are excluded: a vertical "short" feed is a video idea, and manga/novel
  /// pages belong in their own readers.
  List<String> _candidateSourceIds(CatalogueRepository repo) {
    final out = <String>[];
    for (final s in repo.loadedSources) {
      if (out.length >= _maxSources) break;
      out.add(s.id);
    }
    return out;
  }

  Future<void> _load() async {
    if (!sl.isRegistered<CatalogueRepository>()) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) setState(() => _loading = true);
    final repo = sl<CatalogueRepository>();
    final ids = _candidateSourceIds(repo);
    final seen = <String>{};
    final gathered = <MediaItem>[];
    for (final id in ids) {
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
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(DetailScreen.route(item));
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
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_items.isEmpty) {
      return EmptyState(
        icon: Icons.bolt_outlined,
        message: context.l10n.noResults,
        actionLabel: context.l10n.tryAgain,
        onAction: _load,
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _items.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) => _ShortPage(
            item: _items[i],
            onOpen: () => _open(_items[i]),
          ),
        ),
        // Position read-out — a long feed with no sense of place is
        // disorienting, and the dock hides the scrollbar.
        Positioned(
          right: 12,
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

/// One full-bleed page of the feed: the title's art, a scrim, and its name and
/// source. Tapping anywhere opens the title.
class _ShortPage extends StatelessWidget {
  const _ShortPage({required this.item, required this.onOpen});

  final MediaItem item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final art = item.banner?.trim().isNotEmpty == true
        ? item.banner!
        : item.cover;
    final sourceName = sl.isRegistered<CatalogueRepository>()
        ? sl<CatalogueRepository>().displayName(item.sourceId)
        : item.sourceId;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (art != null && art.isNotEmpty)
            CachedNetworkImage(
              imageUrl: art,
              httpHeaders: item.coverHeaders,
              fit: BoxFit.cover,
              placeholder: (_, _) => ColoredBox(color: AppColors.surface),
              errorWidget: (_, _, _) => ColoredBox(color: AppColors.surface),
            )
          else
            ColoredBox(color: AppColors.surface),
          // Bottom-up scrim so the title stays readable over any art.
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
            right: 20,
            bottom: 64,
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
        ],
      ),
    );
  }
}
