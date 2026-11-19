/// Live/VOD playback routing.
///
/// A live channel and a film look the same coming out of a provider — a title
/// and a URL — but they need different treatment before the player opens:
///
///   • A live channel plays the URL directly.
///   • A past programme needs a catch-up URL built from the channel's
///     declaration, and may not be available at all.
///   • A VOD item may be a torrent (magnet or `.torrent`) that has to go
///     through the torrent engine first, and only then has a local URL.
///
/// Deciding this is the part that gets subtly wrong, so it lives here as a pure
/// function with an explicit result rather than being spread through the
/// player's call sites.
library;

import 'catchup_url.dart';

/// What the caller should do with a media URL.
enum PlaybackRoute {
  /// Open the URL in the player as-is.
  direct,

  /// Hand the magnet/`.torrent` to the torrent engine, then play its local URL.
  torrent,

  /// Build a catch-up URL first (and fail cleanly when it isn't available).
  catchup,

  /// Nothing playable — say so instead of opening a dead player.
  unavailable,
}

/// A routing decision, with the reason carried for the UI.
class PlaybackPlan {
  const PlaybackPlan({
    required this.route,
    this.url = '',
    this.reason = '',
  });

  final PlaybackRoute route;

  /// The URL to use. For [PlaybackRoute.catchup] this is the built catch-up
  /// URL; for [PlaybackRoute.direct] the original; for [PlaybackRoute.torrent]
  /// the magnet/`.torrent` URI to hand to the engine.
  final String url;

  /// Human-readable reason, set for [PlaybackRoute.unavailable] so the UI can
  /// explain rather than show an empty player.
  final String reason;

  bool get canPlay =>
      route == PlaybackRoute.direct ||
      route == PlaybackRoute.torrent ||
      route == PlaybackRoute.catchup;

  static PlaybackPlan unavailable(String reason) =>
      PlaybackPlan(route: PlaybackRoute.unavailable, reason: reason);
}

/// True when [url] names a torrent rather than an HTTP stream.
bool isTorrentUri(String url) {
  final u = url.trim().toLowerCase();
  return u.startsWith('magnet:?') || u.endsWith('.torrent');
}

/// True when [url] is something a player can open directly.
bool isPlayableStream(String url) {
  final u = url.trim().toLowerCase();
  if (u.isEmpty) return false;
  if (isTorrentUri(u)) return false;
  return u.startsWith('http://') ||
      u.startsWith('https://') ||
      u.startsWith('rtsp://') ||
      u.startsWith('rtmp://') ||
      u.startsWith('udp://') ||
      u.startsWith('file://');
}

/// Choose a route for a media URL.
///
/// [catchup] is supplied when the channel declares catch-up support and the
/// caller is asking for a past airing ([airingStart] in the past). A live
/// request never routes to catch-up, even on a channel that supports it.
PlaybackPlan planPlayback({
  required String url,
  CatchupSpec? catchup,
  DateTime? airingStart,
  DateTime? now,
  int durationMinutes = 0,
}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return PlaybackPlan.unavailable('No stream available');

  if (isTorrentUri(trimmed)) {
    return PlaybackPlan(route: PlaybackRoute.torrent, url: trimmed);
  }

  if (!isPlayableStream(trimmed)) {
    return PlaybackPlan.unavailable('Unsupported stream format');
  }

  final spec = catchup ?? CatchupSpec.none;
  final when = airingStart?.toUtc();
  final ref = (now ?? DateTime.now()).toUtc();

  // Only a past airing on a catch-up channel takes the catch-up path.
  if (when != null && spec.isSupported && when.isBefore(ref)) {
    final built = buildCatchupUrl(
      liveUrl: trimmed,
      spec: spec,
      when: when,
      now: ref,
      durationMinutes: durationMinutes,
    );
    if (built == null) {
      return PlaybackPlan.unavailable(
        spec.hasArchive
            ? 'Catch-up is not available for that time'
            : 'This channel has no catch-up',
      );
    }
    return PlaybackPlan(route: PlaybackRoute.catchup, url: built);
  }

  return PlaybackPlan(route: PlaybackRoute.direct, url: trimmed);
}

/// The route a "play this now" tap should take for a live channel — always
/// [PlaybackRoute.direct] for a playable URL, since "now" is never a catch-up
/// request.
PlaybackPlan planLive({required String url}) => planPlayback(url: url);

/// The route for a film or episode that may be a torrent.
PlaybackPlan planVod({required String url}) => planPlayback(url: url);
