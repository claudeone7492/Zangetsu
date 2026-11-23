import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import '../models/home_section.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import 'm3u_playlist.dart';

/// One user-added IPTV playlist. [source] is the remote URL, or empty when
/// [inline] carries pasted text. Keeping the pasted text means a playlist that
/// was added from a file/chat still works after a restart without re-fetching.
class LivePlaylistEntry {
  const LivePlaylistEntry({
    required this.id,
    required this.name,
    required this.source,
    required this.kind,
    this.inline = '',
  });

  final String id;
  final String name;
  final String source;
  final String kind;
  final String inline;

  bool get isInline => inline.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'source': source,
    'kind': kind,
    'inline': inline,
  };

  factory LivePlaylistEntry.fromMap(Map<dynamic, dynamic> map) =>
      LivePlaylistEntry(
        id: (map['id'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        source: (map['source'] ?? '').toString(),
        kind: (map['kind'] ?? 'm3u').toString(),
        inline: (map['inline'] ?? '').toString(),
      );
}

/// The user's own M3U / JSON playlists, merged into Live TV beside the bundled
/// IPTV catalogue.
///
/// Channels are stored as parsed [M3uChannel]s only for inline playlists; a
/// remote playlist keeps its URL and is parsed on demand, with a session cache
/// so a page rebuild does not re-download a 5 MB playlist. A dead playlist is
/// skipped rather than failing the whole Live TV page.
class LivePlaylistStore {
  static const String boxName = 'live_playlists';

  /// Synthetic source id for imported channels. Live TV intercepts it and
  /// opens the player directly, so no provider registration is needed.
  static const String sourceId = 'liveplaylist';

  Box<dynamic>? _box;
  final Map<String, List<M3uChannel>> _cache = {};

  Future<void> init() async {
    _box ??= await openBoxSafely<dynamic>(boxName);
  }

  Box<dynamic> get _db {
    final box = _box;
    if (box == null) {
      throw StateError('LivePlaylistStore.init() must run before use');
    }
    return box;
  }

  List<LivePlaylistEntry> get entries {
    final out = <LivePlaylistEntry>[];
    for (final value in _db.values) {
      if (value is Map) out.add(LivePlaylistEntry.fromMap(value));
    }
    return out;
  }

  Future<LivePlaylistEntry> addUrl({
    required String name,
    required String url,
    required Dio dio,
  }) async {
    final text = await _fetch(dio, url);
    final channels = M3uPlaylist.parseAuto(text);
    if (channels.isEmpty) {
      throw const FormatException('The playlist has no playable channels');
    }
    final entry = LivePlaylistEntry(
      id: _newId(),
      name: name.trim().isEmpty ? _hostOf(url) : name.trim(),
      source: url.trim(),
      kind: _kindOf(text),
    );
    await _db.put(entry.id, entry.toMap());
    _cache[entry.id] = channels;
    return entry;
  }

  Future<LivePlaylistEntry> addText({
    required String name,
    required String text,
  }) async {
    final channels = M3uPlaylist.parseAuto(text);
    if (channels.isEmpty) {
      throw const FormatException('The playlist has no playable channels');
    }
    final entry = LivePlaylistEntry(
      id: _newId(),
      name: name.trim().isEmpty ? 'Playlist' : name.trim(),
      source: '',
      kind: _kindOf(text),
      inline: text,
    );
    await _db.put(entry.id, entry.toMap());
    _cache[entry.id] = channels;
    return entry;
  }

  Future<void> remove(String id) async {
    await _db.delete(id);
    _cache.remove(id);
  }

  /// Parsed channels for one playlist. A remote fetch failure yields an empty
  /// list, so one dead playlist never blanks the rest of Live TV.
  Future<List<M3uChannel>> channelsFor(LivePlaylistEntry entry, Dio dio) async {
    final cached = _cache[entry.id];
    if (cached != null) return cached;
    final List<M3uChannel> channels;
    if (entry.isInline) {
      channels = M3uPlaylist.parseAuto(entry.inline);
    } else {
      try {
        channels = M3uPlaylist.parseAuto(await _fetch(dio, entry.source));
      } catch (_) {
        return const [];
      }
    }
    _cache[entry.id] = channels;
    return channels;
  }

  /// Imported channels grouped into Home rows. The group title is the
  /// playlist's own `group-title` when present, otherwise the playlist name.
  Future<List<HomeSection>> sections(Dio dio) async {
    final groups = <String, List<MediaItem>>{};
    for (final entry in entries) {
      final channels = await channelsFor(entry, dio);
      for (var i = 0; i < channels.length; i++) {
        final channel = channels[i];
        final group = (channel.group?.trim().isNotEmpty ?? false)
            ? channel.group!.trim()
            : entry.name;
        groups
            .putIfAbsent(group, () => <MediaItem>[])
            .add(_item(entry, channel, i, group));
      }
    }
    return [
      for (final group in groups.entries)
        if (group.value.isNotEmpty)
          HomeSection(title: group.key, items: group.value),
    ];
  }

  Future<List<MediaItem>> search(String query, Dio dio) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final out = <MediaItem>[];
    for (final entry in entries) {
      final channels = await channelsFor(entry, dio);
      for (var i = 0; i < channels.length; i++) {
        final channel = channels[i];
        final haystack = [
          channel.name,
          channel.group ?? '',
          channel.tvgName ?? '',
        ].join(' ').toLowerCase();
        if (!haystack.contains(q) || !seen.add(channel.url)) continue;
        final group = (channel.group?.trim().isNotEmpty ?? false)
            ? channel.group!.trim()
            : entry.name;
        out.add(_item(entry, channel, i, group));
      }
    }
    return out;
  }

  Future<String> _fetch(Dio dio, String url) async {
    final res = await dio.get<String>(
      url.trim(),
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 20),
        headers: const {'User-Agent': 'Zangetsu/1.0'},
      ),
    );
    return res.data ?? '';
  }

  MediaItem _item(
    LivePlaylistEntry entry,
    M3uChannel channel,
    int index,
    String group,
  ) => MediaItem(
    id: '$sourceId:${entry.id}:$index',
    title: channel.name,
    cover: channel.logo,
    url: channel.url,
    type: ProviderType.movie,
    sourceId: sourceId,
    liveBadge: 'LIVE',
    liveInfo: group,
  );

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  static String _kindOf(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('[') || trimmed.startsWith('{') ? 'json' : 'm3u';
  }

  static String _hostOf(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host.isEmpty ? 'Playlist' : host;
  }
}
