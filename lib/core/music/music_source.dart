import 'music_models.dart';

/// A music catalogue the app can browse.
///
/// An interface rather than a concrete client so the whole music mode can be
/// exercised in tests without a network, and so a second catalogue can be added
/// without touching the service, the cubit or the UI. Only [JioSaavnSource]
/// ships today.
abstract class MusicSource {
  /// Stable id, also stamped on every [MusicTrack.sourceId] it produces.
  String get id;

  /// Human-readable name for the settings row and error messages.
  String get displayName;

  /// Whether this source can currently be used. Lets the UI hide an entry
  /// rather than fail after a tap.
  bool get isConfigured;

  /// The home rows. Order is display order; empty rows are dropped by callers.
  Future<List<MusicSection>> home();

  /// Free-text search. Never returns a bare null — an empty list means "no
  /// matches", and a failure throws so the caller can show the reason.
  Future<List<MusicTrack>> search(String query, {int page = 1});

  /// A fresh, playable URL for [track].
  ///
  /// Separate from the listing call because catalogue URLs are signed and
  /// expire: a track remembered from yesterday's home still needs a fresh link
  /// before it will play.
  Future<String?> streamFor(MusicTrack track);
}

/// A catalogue failure with a message fit to show the viewer.
class MusicSourceException implements Exception {
  MusicSourceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'MusicSourceException: $message';
}
