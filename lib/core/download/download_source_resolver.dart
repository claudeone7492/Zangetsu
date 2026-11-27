import '../di/injector.dart';
import '../models/video_source.dart';
import '../repository/catalogue_repository.dart';
import '../zmode/metadata_repository.dart';

/// Download-capable sources for [episodeUrl], gathered from every source that
/// can answer for it.
///
/// The owning provider is asked first, because its links are the ones the
/// viewer is already playing. When it throws or comes back empty the sweep
/// asks the rest of the installed sources — the same path the download queue
/// takes when a mirror dies mid-file, so the picker offers exactly what the
/// downloader would fall back to on its own.
///
/// Never throws: a picker that opens on an empty state is recoverable with
/// Retry, while an exception here used to surface as "Couldn't load download
/// options" with nothing the viewer could do about it.
Future<List<VideoSource>> resolveDownloadSources(
  String episodeUrl, {
  String? sourceId,
  bool fast = false,
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
