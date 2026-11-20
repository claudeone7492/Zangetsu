/// Wire-format mapping for `.hiki` (Hikari) extensions.
///
/// Kept pure and free of platform calls so it can be tested without a device.
/// The native side (`HikariJson.kt`) writes exactly these keys; the two files
/// are a pair and a key renamed on one side silently drops a field, which is
/// why every key below has a test.
///
/// The Hikari SDK has no notion of "episode url" — an episode is addressed by
/// its id plus the media it belongs to. Our [BaseProvider] contract is
/// url-addressed, so [hikariEpisodeUrl] packs both into one opaque string and
/// [hikariEpisodeFromUrl] unpacks it. The media payload travels with it because
/// `getStreams(media, episode)` needs the full media object, not just an id.
library;

import 'dart:convert';

import '../models/episode.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';

/// Separator inside a packed Hikari episode url. A control character, so it
/// cannot collide with anything an extension puts in a real id.
const String hikariUrlSeparator = '\u0001';

/// Prefix marking a Hikari media/episode id as ours.
const String hikariIdPrefix = 'hiki:';

/// Packs [media] and [episode] into the single opaque url our contract passes
/// around. `episode` is null for a movie (Hikari models those as
/// `getStreams(media, null)`).
String hikariEpisodeUrl(Map<String, dynamic> media, Map<String, dynamic>? episode) {
  final payload = <String, dynamic>{'m': media, 'e': episode};
  return '$hikariIdPrefix${_encode(payload)}';
}

/// Inverse of [hikariEpisodeUrl]. Returns null when [url] isn't one of ours,
/// so a caller can fall through to another engine instead of throwing.
({Map<String, dynamic> media, Map<String, dynamic>? episode})? hikariEpisodeFromUrl(
  String url,
) {
  if (!url.startsWith(hikariIdPrefix)) return null;
  final decoded = _decode(url.substring(hikariIdPrefix.length));
  if (decoded is! Map) return null;
  final media = decoded['m'];
  if (media is! Map) return null;
  final episode = decoded['e'];
  return (
    media: Map<String, dynamic>.from(media),
    episode: episode is Map ? Map<String, dynamic>.from(episode) : null,
  );
}

// Base64url keeps the packed url free of characters a query string or a route
// would mangle; no padding because it can appear in a url segment.
String _encode(Object value) =>
    base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');

Object? _decode(String value) {
  try {
    final padded = value.padRight((value.length + 3) & ~3, '=');
    return jsonDecode(utf8.decode(base64Url.decode(padded)));
  } catch (_) {
    return null;
  }
}

/// Maps a Hikari media row to our [MediaItem].
///
/// `type` comes from the extension's declared media type; anything unrecognised
/// falls back to [ProviderType.movie] because Hikari extensions are
/// overwhelmingly film/TV scrapers and a wrong "movie" still opens a detail
/// page, whereas a wrong "manga" routes into the reader.
MediaItem hikariMediaItem(
  Map<String, dynamic> json, {
  required String sourceId,
  required String providerName,
}) {
  final media = _mediaJson(json);
  final type = _providerType(json['type']);
  return MediaItem(
    id: hikariMediaId(media, sourceId: sourceId),
    title: (json['title'] as String?)?.trim().isNotEmpty == true
        ? (json['title'] as String).trim()
        : 'Untitled',
    cover: _nonEmpty(json['posterUrl']),
    banner: _nonEmpty(json['backdropUrl']),
    url: hikariDetailUrl(media),
    type: type,
    sourceId: sourceId,
    genres: _stringList(json['genres']),
    year: json['year'] is int ? json['year'] as int : null,
  );
}

/// Maps a Hikari media row plus its episodes to our [MediaDetail].
MediaDetail hikariMediaDetail(
  Map<String, dynamic> json, {
  required String sourceId,
  required List<Episode> episodes,
}) {
  final media = _mediaJson(json);
  return MediaDetail(
    id: hikariMediaId(media, sourceId: sourceId),
    title: (json['title'] as String?)?.trim().isNotEmpty == true
        ? (json['title'] as String).trim()
        : 'Untitled',
    cover: _nonEmpty(json['posterUrl']),
    banner: _nonEmpty(json['backdropUrl']),
    url: hikariDetailUrl(media),
    description: _nonEmpty(json['overview']),
    genres: _stringList(json['genres']),
    episodes: episodes,
    year: json['year'] is int ? '${json['year']}' : null,
    type: _providerType(json['type']),
    sourceId: sourceId,
  );
}

/// Maps one Hikari episode to our [Episode].
///
/// Hikari's `number` is an `Int`, and movies carry no episode at all — a null
/// [episode] becomes a single synthetic "Full" entry so the detail screen has
/// something to tap.
Episode hikariEpisode(
  Map<String, dynamic> media,
  Map<String, dynamic>? episode, {
  required String sourceId,
}) {
  if (episode == null) {
    return Episode(
      id: hikariMediaId(media, sourceId: sourceId),
      title: 'Full',
      number: 1,
      url: hikariEpisodeUrl(media, null),
      thumbnail: _nonEmpty(media['posterUrl']),
      season: 1,
    );
  }
  final number = episode['number'] is int ? episode['number'] as int : null;
  final name = _nonEmpty(episode['name']);
  return Episode(
    id: '${hikariMediaId(media, sourceId: sourceId)}'
        '$hikariUrlSeparator${episode['id'] ?? ''}',
    title: name ?? (number != null ? 'Episode $number' : 'Episode'),
    number: number?.toDouble(),
    url: hikariEpisodeUrl(media, episode),
    thumbnail: _nonEmpty(episode['image']),
    season: episode['season'] is int ? episode['season'] as int : 1,
  );
}

/// Maps a Hikari stream to our [VideoSource].
///
/// Hikari models the playback kind with booleans (`isM3u8`, `isMpd`,
/// `isTorrent`) rather than a container enum, and a torrent is not a url at all
/// — it is an info hash plus trackers. A torrent stream is therefore rendered as
/// a magnet, which is what the existing torrent path already accepts.
VideoSource? hikariVideoSource(Map<String, dynamic> json) {
  final headers = _stringMap(json['headers']);
  final subtitles = <Subtitle>[];
  final rawSubs = json['subtitles'];
  if (rawSubs is List) {
    for (final s in rawSubs) {
      if (s is! Map) continue;
      final url = _nonEmpty(s['url']);
      if (url == null) continue;
      subtitles.add(
        Subtitle(
          url: url,
          lang: _nonEmpty(s['lang']) ?? 'und',
          format: url.toLowerCase().contains('.vtt') ? 'vtt' : null,
        ),
      );
    }
  }

  final name = _nonEmpty(json['name']);

  if (json['isTorrent'] == true) {
    final hash = _nonEmpty(json['infoHash']);
    if (hash == null) return null;
    final trackers = _stringList(json['trackers']);
    final magnet = StringBuffer('magnet:?xt=urn:btih:$hash');
    for (final t in trackers) {
      magnet.write('&tr=${Uri.encodeComponent(t)}');
    }
    final fileIdx = json['fileIdx'];
    return VideoSource(
      url: magnet.toString(),
      label: name,
      container: SourceContainer.torrent,
      kind: AudioKind.unknown,
      subtitles: subtitles,
      torrentFileIndex: fileIdx is int ? fileIdx : null,
    );
  }

  final url = _nonEmpty(json['url']);
  // A YouTube or "open externally" stream has no url we can hand to the player.
  if (url == null) return null;

  return VideoSource(
    url: url,
    label: name,
    container: json['isM3u8'] == true
        ? SourceContainer.hls
        : (json['isMpd'] == true
              ? SourceContainer.unknown
              : SourceContainer.mp4),
    headers: headers.isEmpty ? null : headers,
    kind: AudioKind.unknown,
    subtitles: subtitles,
  );
}

/// The opaque detail url for [media]. Hikari detail lookups take the media
/// object itself, so it is carried in the url.
String hikariDetailUrl(Map<String, dynamic> media) =>
    '$hikariIdPrefix${_encode(media)}';

/// Inverse of [hikariDetailUrl].
Map<String, dynamic>? hikariMediaFromDetailUrl(String url) {
  if (!url.startsWith(hikariIdPrefix)) return null;
  final decoded = _decode(url.substring(hikariIdPrefix.length));
  if (decoded is! Map) return null;
  return Map<String, dynamic>.from(decoded);
}

/// A stable id for [media], namespaced to the extension that produced it so two
/// extensions returning the same slug never collide in My List or history.
String hikariMediaId(Map<String, dynamic> media, {required String sourceId}) {
  final raw = _nonEmpty(media['id']) ?? _nonEmpty(media['title']) ?? '';
  return '$hikariIdPrefix$sourceId$hikariUrlSeparator$raw';
}

/// Normalises a media row. Extensions sometimes hand back a title-only object;
/// this fills the fields our models assume are present.
Map<String, dynamic> _mediaJson(Map<String, dynamic> json) => <String, dynamic>{
  'id': json['id'] ?? '',
  'title': json['title'] ?? '',
  'type': json['type'] ?? 'unknown',
  'posterUrl': json['posterUrl'],
  'backdropUrl': json['backdropUrl'],
  'overview': json['overview'],
  'year': json['year'],
  'genres': json['genres'] ?? const <String>[],
  'rawType': json['rawType'] ?? '',
};

ProviderType _providerType(Object? raw) => switch ('$raw'.toLowerCase()) {
  'series' || 'tv' || 'anime' => ProviderType.anime,
  _ => ProviderType.movie,
};

String? _nonEmpty(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final v in value)
      if (v is String && v.trim().isNotEmpty) v.trim(),
  ];
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return const {};
  return {
    for (final e in value.entries)
      if (e.key is String && e.value is String && (e.value as String).isNotEmpty)
        e.key as String: e.value as String,
  };
}
