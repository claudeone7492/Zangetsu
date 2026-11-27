import '../di/injector.dart';
import '../models/video_source.dart';
import '../repository/catalogue_repository.dart';
import '../zmode/metadata_repository.dart';
import 'download_size_estimate.dart';
import 'download_source_cache.dart';

/// Requests already on the wire, so a preload and the picker that follows it
/// share one resolve instead of hitting the provider twice.
final Map<String, Future<List<VideoSource>>> _inFlight = {};

/// Download-capable sources for [episodeUrl], gathered from every source that
/// can answer for it.
///
/// Answers from [DownloadSourceCache] when the same episode was already
/// resolved for playback, so the picker opens on a ready grid. Otherwise the
/// owning provider is asked first, because its links are the ones the viewer
/// is already playing; when it throws or comes back empty the sweep asks the
/// rest of the installed sources — the same path the download queue takes when
/// a mirror dies mid-file, so the picker offers exactly what the downloader
/// would fall back to on its own.
///
/// Never throws: a picker that opens on an empty state is recoverable with
/// Retry, while an exception here used to surface as "Couldn't load download
/// options" with nothing the viewer could do about it.
Future<List<VideoSource>> resolveDownloadSources(
  String episodeUrl, {
  String? sourceId,
  bool fast = false,
  bool refresh = false,
}) async {
  final cache = DownloadSourceCache.instance;
  if (!refresh) {
    final hit = cache.sources(episodeUrl);
    if (hit != null && hit.isNotEmpty) return hit;
  }

  final key = '${sourceId ?? ''}|$episodeUrl';
  final pending = _inFlight[key];
  if (pending != null) return pending;

  final job = _gather(episodeUrl, sourceId: sourceId, fast: fast);
  _inFlight[key] = job;
  try {
    final sources = await job;
    // Sizes are warmed by the callers that know the episode runtime (playback,
    // the detail page's preload), so a probe is never wasted on a guess.
    if (sources.isNotEmpty) cache.storeSources(episodeUrl, sources);
    return sources;
  } finally {
    if (identical(_inFlight[key], job)) _inFlight.remove(key);
  }
}

/// Warm the cache for later: a viewer who opens the picker next should never
/// see a spinner. Silent by design — nothing here is worth an error surface.
Future<void> preloadDownloadSources(
  String episodeUrl, {
  String? sourceId,
  int? runtimeMinutes,
  bool force = false,
}) async {
  final cache = DownloadSourceCache.instance;
  final cached = cache.sources(episodeUrl, allowStale: true);
  if (!force && cached != null && cached.isNotEmpty) {
    return warmDownloadSizes(cached, runtimeMinutes: runtimeMinutes);
  }
  final sources = await resolveDownloadSources(
    episodeUrl,
    sourceId: sourceId,
    refresh: true,
  );
  await warmDownloadSizes(sources, runtimeMinutes: runtimeMinutes);
}

/// Probe every mirror that has no size yet, four at a time, storing each
/// result so the picker can paint it without asking again.
Future<void> warmDownloadSizes(
  List<VideoSource> sources, {
  int? runtimeMinutes,
}) async {
  final cache = DownloadSourceCache.instance;
  final pending = [
    for (final source in sources)
      if (source.url.isNotEmpty && !cache.hasSize(source.url)) source,
  ];
  var next = 0;
  Future<void> worker() async {
    while (next < pending.length) {
      final source = pending[next++];
      SizeEstimate? estimate;
      try {
        estimate = await estimateEpisodeBytes(
          source,
          runtimeMinutes: runtimeMinutes,
        );
      } catch (_) {
        estimate = null;
      }
      cache.storeSize(source.url, estimate);
    }
  }

  await Future.wait([
    for (var i = 0; i < 4 && i < pending.length; i++) worker(),
  ]);
}

Future<List<VideoSource>> _gather(
  String episodeUrl, {
  String? sourceId,
  required bool fast,
}) async {
  final own = await _ownSources(episodeUrl, sourceId: sourceId, fast: fast);
  if (own.isNotEmpty) return own;
  final swept = await _sweptSources(episodeUrl);
  return swept.isNotEmpty ? swept : own;
}

Future<List<VideoSource>> _ownSources(
  String episodeUrl, {
  String? sourceId,
  required bool fast,
}) async {
  if (!sl.isRegistered<CatalogueRepository>()) return const [];
  try {
    return await sl<CatalogueRepository>().sources(
      episodeUrl,
      sourceId: sourceId,
      fast: fast,
    );
  } catch (_) {
    return const [];
  }
}

Future<List<VideoSource>> _sweptSources(String episodeUrl) async {
  if (!sl.isRegistered<MetadataRepository>()) return const [];
  try {
    final swept = await sl<MetadataRepository>().sourcesWhere(
      episodeUrl,
      (streams) => streams.isNotEmpty,
    );
    return swept.streams;
  } catch (_) {
    return const [];
  }
}
