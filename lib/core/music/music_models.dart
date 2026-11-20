/// Music catalogue models.
///
/// Kept separate from `MediaItem` on purpose. A track has an artist, an album
/// and a playable audio URL; a video title has episodes, servers and qualities.
/// Forcing one shape over both would leave half the fields null in every use and
/// make the player guess which kind of thing it was handed.
library;

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

  String get displayArtist =>
      (artist == null || artist!.isEmpty) ? 'Unknown artist' : artist!;

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
      sourceId: (json['sourceId'] as String?) ?? 'jiosaavn',
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

/// A named row of tracks on the music home — "Trending", "New releases", …
class MusicSection {
  const MusicSection({required this.title, required this.tracks});

  final String title;
  final List<MusicTrack> tracks;

  bool get isEmpty => tracks.isEmpty;
}
