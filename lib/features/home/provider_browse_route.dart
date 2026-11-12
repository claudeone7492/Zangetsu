import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/models/episode.dart';
import '../../core/models/media_item.dart';
import '../../core/playback/resume_store.dart';
import '../../core/repository/catalogue_repository.dart';
import '../detail/detail_screen.dart';
import '../player/player_screen.dart';
import 'see_all_screen.dart';

/// True when [url] is a provider-extension handle rather than a playable title:
/// a `browse:` category row (a streaming platform or a filter shortcut) or a
/// `live:` sports stream. Both are produced by the MovieBox provider's home
/// rows; every other source yields ordinary title urls, so this is inert there.
bool isProviderExtensionUrl(String url) =>
    url.startsWith('browse:') || url.startsWith('live:');

/// The bare `platform|<name>` / `filter|<spec>` handle `browseFilter` expects —
/// the `browse:` scheme prefix is the app's own, not the provider's.
String browseSpecOf(String url) =>
    url.startsWith('browse:') ? url.substring('browse:'.length) : url;

/// Opens a provider-extension [item], or returns false when it is an ordinary
/// title and the caller should take its normal detail path.
///
/// A `browse:` row is a handle to a paginated listing, so it opens a grid that
/// pages through [CatalogueRepository.browseCategory]. A `live:` row is a
/// single always-on stream, so it opens the player directly — there is no show
/// to browse.
Future<bool> openProviderExtensionItem(
  BuildContext context,
  MediaItem item, {
  CatalogueRepository? repository,
}) async {
  final url = item.url;
  if (!isProviderExtensionUrl(url)) return false;
  final repo = repository ?? sl<CatalogueRepository>();
  if (url.startsWith('live:')) {
    _openLive(context, item, repo);
    return true;
  }
  final first = await repo.browseCategory(
    browseSpecOf(url),
    sourceId: item.sourceId,
    page: 1,
  );
  if (!context.mounted) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SeeAllScreen(
        title: item.title,
        items: first,
        onTap: (m) => Navigator.of(context).push(DetailScreen.route(m)),
        onLoadMore: (page) => repo.browseCategory(
          browseSpecOf(url),
          sourceId: item.sourceId,
          page: page,
        ),
      ),
    ),
  );
  return true;
}

void _openLive(BuildContext context, MediaItem item, CatalogueRepository repo) {
  final ep = Episode(id: item.url, title: item.title, url: item.url);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        sourceId: item.sourceId,
        episodes: [ep],
        startIndex: 0,
        resume: sl<ResumeStore>(),
        resolveSources: (_) =>
            repo.sources(item.url, sourceId: item.sourceId, fast: true),
        showTitle: item.title,
        cover: item.cover,
        coverHeaders: item.coverHeaders,
      ),
    ),
  );
}
