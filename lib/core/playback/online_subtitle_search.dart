import 'framex_subtitle_source.dart';
import 'subtitle_search_service.dart';

/// One subtitle offered by any online source, with the work of fetching it
/// attached.
///
/// The two providers answer in different shapes — OpenSubtitles returns a file
/// id that must be exchanged for a one-time link, FrameX returns a ready URL — so
/// the caller is given a [download] closure rather than the raw fields. That way
/// the sheet and the TV players can treat a row from either provider the same.
class OnlineSubtitleHit {
  OnlineSubtitleHit({
    required this.label,
    required this.language,
    required this.source,
    required this.download,
  });

  /// The release the caption was timed against, or the file name.
  final String label;

  /// The language, spelled out when the provider gives it that way.
  final String language;

  /// Which provider this came from, for display and for error messages.
  final String source;

  /// Fetches the caption and returns a local path, or null when the file could
  /// not be read as a subtitle.
  final Future<String?> Function() download;
}

/// Searches every online subtitle provider the app has, and merges the results.
///
/// OpenSubtitles is the better catalogue but needs an API key and a per-user
/// quota, so it is skipped when no key is set — the request would only fail.
/// FrameX is keyless but is looked up by TMDB id, so it is skipped when the id is
/// unknown. Either provider failing leaves the other's results in place; a
/// provider is only reported as an error when it was the sole source and it
/// failed.
class OnlineSubtitleSearch {
  OnlineSubtitleSearch({
    SubtitleSearchService? openSubtitles,
    FrameXSubtitleSource? framex,
  }) : _openSubtitles = openSubtitles ?? SubtitleSearchService(),
       _framex = framex ?? FrameXSubtitleSource();

  final SubtitleSearchService _openSubtitles;
  final FrameXSubtitleSource _framex;

  /// Whether an OpenSubtitles search is possible (an API key is set).
  bool get hasOpenSubtitlesKey => _openSubtitles.hasApiKey;

  /// Whether a FrameX lookup is possible for this title.
  static bool canUseFrameX(int? tmdbId) => tmdbId != null;

  /// Searches both providers for [query] and returns the merged list.
  ///
  /// [error] is set to a readable message when a provider that could have
  /// answered did not, so the UI can show why the list is short. FrameX rows come
  /// first so the keyless source is the one a viewer without a key sees at the
  /// top.
  Future<List<OnlineSubtitleHit>> search(
    String query, {
    String language = '',
    String? imdbId,
    int? tmdbId,
    String mediaType = 'movie',
    int? season,
    int? episode,
    void Function(String message)? onError,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final hits = <OnlineSubtitleHit>[];
    String? error;

    if (canUseFrameX(tmdbId)) {
      final framex = await _framex.subtitlesFor(
        '$tmdbId',
        type: mediaType,
        season: season,
        episode: episode,
      );
      for (final f in framex) {
        hits.add(
          OnlineSubtitleHit(
            label: f.displayName,
            language: (f.language ?? f.lang ?? '').trim(),
            source: 'FrameX',
            download: () => _framex.downloadToFile(
              f.url,
              name:
                  '${f.language ?? f.lang ?? 'sub'}_'
                  '${f.label ?? f.url.hashCode}',
            ),
          ),
        );
      }
    }

    if (hasOpenSubtitlesKey) {
      try {
        final results = await _openSubtitles.search(
          q,
          language: language.isEmpty ? '' : language,
          imdbId: imdbId,
          tmdbId: tmdbId,
        );
        for (final r in results) {
          hits.add(
            OnlineSubtitleHit(
              label: r.name,
              language: r.language,
              source: 'OpenSubtitles',
              download: () => _openSubtitles.download(r),
            ),
          );
        }
      } on SubtitleSearchException catch (e) {
        error = e.message;
      } catch (e) {
        error = 'OpenSubtitles search failed: $e';
      }
    }

    // Only surface a failure when nothing at all came back: with results in hand
    // a provider's error is noise, not something the viewer can act on.
    if (hits.isEmpty && error != null) onError?.call(error);

    return hits;
  }
}
