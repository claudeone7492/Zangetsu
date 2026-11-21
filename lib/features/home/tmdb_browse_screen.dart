import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/tmdb_browse.dart';
import '../../core/ui/content_row.dart';
import '../../core/ui/poster_card.dart';
import '../../l10n/l10n.dart';
import 'search_screen.dart';

/// Hikari's `TmdbBrowse` catalogue as a screen: six TMDB rails, each a
/// paginated endpoint, with a tap that shows the title and hands it to the
/// app's own search.
class TmdbBrowseScreen extends StatefulWidget {
  const TmdbBrowseScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const TmdbBrowseScreen());

  @override
  State<TmdbBrowseScreen> createState() => _TmdbBrowseScreenState();
}

class _TmdbBrowseScreenState extends State<TmdbBrowseScreen> {
  late final TmdbBrowse _browse = TmdbBrowse(sl());
  final Map<String, List<TmdbBrowseItem>> _rows = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      for (final row in TmdbBrowse.generalRows)
        _browse.items(row.catalogId).then((items) => (row, items)),
    ]);
    if (!mounted) return;
    setState(() {
      for (final (row, items) in results) {
        _rows[row.id] = items;
      }
      _loading = false;
    });
  }

  String _title(TmdbBrowseRow row) {
    final l10n = context.l10n;
    return switch (row.titleKey) {
      'tmdbTrending' => l10n.tmdbTrending,
      'tmdbPopularMovies' => l10n.tmdbPopularMovies,
      'tmdbTopRatedMovies' => l10n.tmdbTopRatedMovies,
      'tmdbPopularSeries' => l10n.tmdbPopularSeries,
      'tmdbTopRatedSeries' => l10n.tmdbTopRatedSeries,
      'tmdbOnTv' => l10n.tmdbOnTv,
      'tmdbPopularAnime' => l10n.tmdbPopularAnime,
      'tmdbTopRatedAnime' => l10n.tmdbTopRatedAnime,
      'tmdbNewAnime' => l10n.tmdbNewAnime,
      'tmdbAnimeMovies' => l10n.tmdbAnimeMovies,
      'tmdbPopularKoreanDramas' => l10n.tmdbPopularKoreanDramas,
      'tmdbPopularHindiMovies' => l10n.tmdbPopularHindiMovies,
      'tmdbPopularFrenchMovies' => l10n.tmdbPopularFrenchMovies,
      'tmdbPopularPersianMovies' => l10n.tmdbPopularPersianMovies,
      _ => row.titleKey,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.tmdbBrowse)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              children: [
                for (final row in TmdbBrowse.generalRows)
                  if ((_rows[row.id] ?? const []).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ContentRow(
                        title: _title(row),
                        itemCount: _rows[row.id]!.length,
                        itemBuilder: (context, i) {
                          final item = _rows[row.id]![i];
                          return PosterCard(
                            title: item.title,
                            imageUrl: item.poster,
                            cellWidth: 124,
                            onTap: () => _open(item),
                          );
                        },
                      ),
                    ),
              ],
            ),
    );
  }

  Future<void> _open(TmdbBrowseItem item) async {
    final full = await _browse.meta(item);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                full.title,
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (full.year != null) '${full.year}',
                  if (full.rating != null) '★ ${full.rating!.toStringAsFixed(1)}',
                  if (full.originalTitle != null) full.originalTitle!,
                ].join(' · '),
                style: Theme.of(sheet).textTheme.bodySmall,
              ),
              if (full.overview != null) ...[
                const SizedBox(height: 12),
                Text(full.overview!, maxLines: 8, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.search),
                label: Text(context.l10n.search),
                onPressed: () {
                  Navigator.pop(sheet);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SearchScreen(initialQuery: full.title),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
