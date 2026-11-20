import 'package:flutter/foundation.dart';

import 'jiosaavn_source.dart';
import 'music_models.dart';
import 'music_source.dart';

/// The music catalogue facade the mode talks to.
///
/// Holds the registered [MusicSource]s and does the cross-source work the UI
/// shouldn't: interleaving sections, de-duplicating repeats, and resolving a
/// fresh stream URL at play time. Sources are injected so tests can drive the
/// whole mode against a fake catalogue with no network.
class MusicService {
  MusicService({List<MusicSource>? sources})
    : _sources = sources ?? <MusicSource>[JioSaavnSource()];

  final List<MusicSource> _sources;

  /// The sources that can currently be used. Empty means music mode has nothing
  /// to show, which the UI turns into a "not configured" state rather than an
  /// error.
  List<MusicSource> get availableSources =>
      _sources.where((s) => s.isConfigured).toList();

  bool get isAvailable => availableSources.isNotEmpty;

  /// Home rows across every available source, in source order.
  ///
  /// Sections from different sources are concatenated rather than merged by
  /// title: "Trending" from two catalogues are different lists and merging them
  /// would interleave unrelated songs. A source that fails contributes nothing
  /// so one outage can't blank the mode.
  Future<List<MusicSection>> home() async {
    final out = <MusicSection>[];
    for (final source in availableSources) {
      try {
        final sections = await source.home();
        for (final section in sections) {
          if (section.isEmpty) continue;
          final deduped = _dedupe(section.tracks);
          if (deduped.isNotEmpty) {
            out.add(MusicSection(title: section.title, tracks: deduped));
          }
        }
      } catch (e) {
        debugPrint('[music] ${source.id} home failed: $e');
      }
    }
    return out;
  }

  /// Search every available source and merge the results.
  ///
  /// Unlike [home], results ARE merged: a search for one song should not show
  /// the same track twice just because two catalogues both have it, and the
  /// caller wants one ranked list. Throws only when every source failed, so a
  /// single dead catalogue still returns the other's matches.
  Future<List<MusicTrack>> search(String query, {int page = 1}) async {
    final sources = availableSources;
    if (sources.isEmpty) return const [];
    final results = <MusicTrack>[];
    var failures = 0;
    Object? lastError;
    for (final source in sources) {
      try {
        results.addAll(await source.search(query, page: page));
      } catch (e) {
        failures++;
        lastError = e;
      }
    }
    if (failures == sources.length && lastError != null) {
      throw lastError is MusicSourceException
          ? lastError
          : MusicSourceException('Search failed.', cause: lastError);
    }
    return _dedupe(results);
  }

  /// A playable URL for [track], refreshed if the catalogue's is stale.
  ///
  /// Returns null when nothing playable could be resolved, which the player
  /// surfaces as a "can't play this" message rather than a crash.
  Future<String?> streamFor(MusicTrack track) async {
    final source = _sourceFor(track);
    if (source == null) return track.streamUrl;
    try {
      final url = await source.streamFor(track);
      return (url == null || url.isEmpty) ? null : url;
    } catch (e) {
      debugPrint('[music] stream resolve failed for ${track.id}: $e');
      return track.streamUrl;
    }
  }

  MusicSource? _sourceFor(MusicTrack track) {
    for (final source in _sources) {
      if (source.id == track.sourceId) return source;
    }
    return null;
  }

  /// Drops repeats by (sourceId, id), keeping first occurrence order.
  static List<MusicTrack> _dedupe(List<MusicTrack> tracks) {
    final seen = <String>{};
    final out = <MusicTrack>[];
    for (final track in tracks) {
      if (seen.add('${track.sourceId}:${track.id}')) out.add(track);
    }
    return out;
  }
}
