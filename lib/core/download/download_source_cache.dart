import '../models/episode.dart';
import '../models/video_source.dart';
import 'download_size_estimate.dart';

/// Session-wide memo for everything the download picker would otherwise have
/// to fetch AFTER the viewer taps Download.
///
/// Playback already resolves an episode's mirrors before anyone asks to
/// download it, so the same list is stashed here on the way through and the
/// picker opens on a ready grid instead of a spinner. Same for the title id
/// the queue keys on, the estimated size of each mirror, and the alt-cut
/// episode lists — all of it is background-only: nothing here blocks a tap,
/// and every entry expires so a dead mirror is never offered forever.
class DownloadSourceCache {
  DownloadSourceCache._();

  static final DownloadSourceCache instance = DownloadSourceCache._();

  /// How long a resolved mirror list stays usable. Long enough to cover
  /// "watch, then download what I'm watching"; short enough that a provider
  /// rotating its CDN links refreshes on the next open.
  static Duration ttl = const Duration(minutes: 10);

  /// Sizes change only when the file does, so they outlive the link list.
  static Duration sizeTtl = const Duration(minutes: 30);

  final Map<String, _Entry<List<VideoSource>>> _sources = {};
  final Map<String, _Entry<Map<int, List<Episode>>>> _episodes = {};
  final Map<String, _Entry<SizeEstimate?>> _sizes = {};
  final Map<String, String> _showIds = {};

  /// Mirrors for [episodeUrl], or null when absent or expired.
  List<VideoSource>? sources(String episodeUrl, {bool allowStale = false}) {
    final entry = _sources[episodeUrl];
    if (entry == null) return null;
    if (!allowStale && entry.isOlderThan(ttl)) {
      _sources.remove(episodeUrl);
      return null;
    }
    return entry.value;
  }

  void storeSources(String episodeUrl, List<VideoSource> sources) {
    if (episodeUrl.isEmpty || sources.isEmpty) return;
    _sources[episodeUrl] = _Entry(List.unmodifiable(sources));
  }

  /// Episodes of an alt cut, grouped by season, keyed by title + category.
  Map<int, List<Episode>>? episodes(String key, {bool allowStale = false}) {
    final entry = _episodes[key];
    if (entry == null) return null;
    if (!allowStale && entry.isOlderThan(ttl)) {
      _episodes.remove(key);
      return null;
    }
    return entry.value;
  }

  void storeEpisodes(String key, Map<int, List<Episode>> episodes) {
    if (episodes.isEmpty) return;
    _episodes[key] = _Entry(episodes);
  }

  /// The catalogue id that keys a title's downloads, learned from a detail
  /// page or an earlier queue entry. Never expires within a session: a title
  /// does not change ids.
  String? showId(String sourceId, String showUrl) =>
      _showIds['$sourceId|$showUrl'];

  void storeShowId(String sourceId, String showUrl, String id) {
    if (id.isEmpty) return;
    _showIds['$sourceId|$showUrl'] = id;
  }

  /// True once [url] has been probed, even if the probe could only guess.
  bool hasSize(String url) => _sizes.containsKey(url);

  /// The probe result for [url]; null once probed and unknowable.
  SizeEstimate? size(String url) {
    final entry = _sizes[url];
    if (entry == null) return null;
    if (entry.isOlderThan(sizeTtl)) {
      _sizes.remove(url);
      return null;
    }
    return entry.value;
  }

  void storeSize(String url, SizeEstimate? estimate) {
    if (url.isEmpty) return;
    _sizes[url] = _Entry(estimate);
  }

  void clear() {
    _sources.clear();
    _episodes.clear();
    _sizes.clear();
    _showIds.clear();
  }

  /// Drop [episodeUrl]'s mirrors so the picker re-resolves on purpose.
  void invalidate(String episodeUrl) => _sources.remove(episodeUrl);
}

class _Entry<T> {
  _Entry(this.value) : at = DateTime.now();

  final T value;
  final DateTime at;

  bool isOlderThan(Duration ttl) => DateTime.now().difference(at) > ttl;
}
