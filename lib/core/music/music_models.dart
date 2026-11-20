/// Music catalogue models.
///
/// Kept separate from `MediaItem` on purpose. A track has an artist, an album
/// and a playable audio URL; a video title has episodes, servers and qualities.
/// Forcing one shape over both would leave half the fields null in every use and
/// make the player guess which kind of thing it was handed.
library;

import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import 'music_config.dart';

/// One playable song.
class MusicTrack {
  const MusicTrack({
    required this.id,
    required this.title,
    required this.sourceId,
    this.artist,
    this.album,
    this.artwork,
    this.duration,
    this.year,
    this.language,
    this.streamUrl,
    this.streamExpiresAt,
  });

  /// Stable id within [sourceId]. Doubles as the player's media id.
  final String id;
  final String title;

  /// The provider that produced this track — `jiosaavn` today.
  final String sourceId;

  final String? artist;
  final String? album;
  final String? artwork;
  final Duration? duration;
  final int? year;
  final String? language;

  /// Direct audio URL, when the catalogue handed one out with the listing.
  /// JioSaavn does, but those URLs are signed and expire, so
  /// [MusicService.streamFor] refreshes them before playback rather than
  /// trusting a track cached from yesterday.
  final String? streamUrl;

  /// When [streamUrl] stops working, if the source said. Null means "no stated
  /// expiry" — still refreshed before play, since an unstated expiry is not a
  /// promise.
  final DateTime? streamExpiresAt;

  /// True when [streamUrl] can be played as-is right now.
  bool get hasFreshStream =>
      streamUrl != null &&
      (streamExpiresAt == null || streamExpiresAt!.isAfter(DateTime.now()));

  /// True when the catalogue gave no artist, so the UI can show a localised
  /// placeholder instead of a hardcoded English one.
  bool get hasArtist => artist != null && artist!.isNotEmpty;

  MusicTrack copyWith({
    String? streamUrl,
    DateTime? streamExpiresAt,
    String? artwork,
  }) => MusicTrack(
    id: id,
    title: title,
    sourceId: sourceId,
    artist: artist,
    album: album,
    artwork: artwork ?? this.artwork,
    duration: duration,
    year: year,
    language: language,
    streamUrl: streamUrl ?? this.streamUrl,
    streamExpiresAt: streamExpiresAt ?? this.streamExpiresAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'sourceId': sourceId,
    'artist': artist,
    'album': album,
    'artwork': artwork,
    'durationMs': duration?.inMilliseconds,
    'year': year,
    'language': language,
  };

  static MusicTrack? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    if (id is! String || title is! String) return null;
    final ms = json['durationMs'];
    return MusicTrack(
      id: id,
      title: title,
      sourceId: (json['sourceId'] as String?) ?? kMusicSourceId,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      artwork: json['artwork'] as String?,
      duration: ms is int ? Duration(milliseconds: ms) : null,
      year: json['year'] is int ? json['year'] as int : null,
      language: json['language'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MusicTrack && other.id == id && other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash(id, sourceId);
}

/// The artist line for [track], with a localised placeholder when the
/// catalogue gave none. An extension rather than a getter on [MusicTrack] so
/// the model stays free of the Flutter/l10n layer.
extension MusicTrackLabels on MusicTrack {
  String artistLabel(BuildContext context) =>
      hasArtist ? artist! : context.l10n.musicUnknownArtist;
}

/// The heading for [section], localised when the row is one of the standard
/// ones ([kMusicHomeRows]) and the source's own title otherwise. Keyed by id
/// rather than by matching the English title, so a catalogue that words its
/// rows differently still gets the app's translation.
extension MusicSectionLabels on MusicSection {
  String titleLabel(BuildContext context) => switch (id) {
    'trending' => context.l10n.musicRowTrending,
    'newReleases' => context.l10n.musicRowNewReleases,
    'lofi' => context.l10n.musicRowLofi,
    _ => title,
  };
}

/// A named row of tracks on the music home — "Trending", "New releases", …
class MusicSection {
  const MusicSection({required this.title, this.id, required this.tracks});

  /// Stable row id from [kMusicHomeRows] when the row is one of the standard
  /// ones, else null. The UI localises by this id and only falls back to
  /// [title] for a row the app does not know, so a source can invent a row
  /// without the app needing a string for it.
  final String? id;

  /// The source's own heading. Used as-is when [id] is null or unrecognised.
  final String title;

  final List<MusicTrack> tracks;

  bool get isEmpty => tracks.isEmpty;
}
