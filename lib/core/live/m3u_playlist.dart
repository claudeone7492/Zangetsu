import 'dart:convert';

/// One channel parsed out of an M3U / JSON playlist.
class M3uChannel {
  const M3uChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.tvgId,
    this.tvgName,
  });

  final String name;
  final String url;
  final String? logo;
  final String? group;
  final String? tvgId;
  final String? tvgName;

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    if (logo != null) 'logo': logo,
    if (group != null) 'group': group,
    if (tvgId != null) 'tvgId': tvgId,
    if (tvgName != null) 'tvgName': tvgName,
  };

  factory M3uChannel.fromJson(Map<String, dynamic> json) => M3uChannel(
    name: (json['name'] ?? json['title'] ?? '').toString(),
    url: (json['url'] ?? json['link'] ?? json['stream'] ?? '').toString(),
    logo: _clean(json['logo'] ?? json['icon'] ?? json['tvg-logo']),
    group: _clean(json['group'] ?? json['category'] ?? json['group-title']),
    tvgId: _clean(json['tvgId'] ?? json['tvg-id']),
    tvgName: _clean(json['tvgName'] ?? json['tvg-name']),
  );

  static String? _clean(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

/// Parsers for the two playlist formats the IPTV sources hand out.
///
/// M3U is the de-facto format (`#EXTINF` attributes + a URL line); the JSON
/// form is the flat `[{name, url, logo, group}]` shape some panels export.
/// Both are parsed defensively: a malformed entry is skipped, never fatal,
/// because a playlist with 400 good channels and one bad line should still
/// import.
class M3uPlaylist {
  const M3uPlaylist._();

  static final RegExp _attribute = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

  /// Detects JSON by its first non-whitespace character, otherwise parses M3U.
  static List<M3uChannel> parseAuto(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      return parseJson(text);
    }
    return parse(text);
  }

  static List<M3uChannel> parse(String text) {
    final out = <M3uChannel>[];
    final seen = <String>{};
    String? name;
    String? group;
    String? logo;
    String? tvgId;
    String? tvgName;

    void reset() {
      name = null;
      group = null;
      logo = null;
      tvgId = null;
      tvgName = null;
    }

    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        final comma = _nameComma(line);
        name = comma >= 0 ? line.substring(comma + 1).trim() : '';
        final attrs = <String, String>{};
        for (final m in _attribute.allMatches(line)) {
          attrs[m.group(1)!.toLowerCase()] = m.group(2)!.trim();
        }
        group = _nonEmpty(attrs['group-title']) ?? group;
        logo = _nonEmpty(attrs['tvg-logo']);
        tvgId = _nonEmpty(attrs['tvg-id']);
        tvgName = _nonEmpty(attrs['tvg-name']);
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        group = _nonEmpty(line.substring('#EXTGRP:'.length));
        continue;
      }
      // #EXTVLCOPT, #KODIPROP, #PLAYLIST and plain comments carry no URL.
      if (line.startsWith('#')) continue;
      if (!_isStreamUrl(line)) {
        reset();
        continue;
      }
      final channelName = _nonEmpty(name) ?? tvgName ?? _nameFromUrl(line);
      if (!seen.add(line)) {
        reset();
        continue;
      }
      out.add(
        M3uChannel(
          name: channelName,
          url: line,
          logo: logo,
          group: group,
          tvgId: tvgId,
          tvgName: tvgName,
        ),
      );
      reset();
    }
    return out;
  }

  static List<M3uChannel> parseJson(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return const [];
    }
    final List<Object?> entries;
    if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map) {
      final list = decoded['channels'] ?? decoded['items'] ?? decoded['data'];
      if (list is! List) return const [];
      entries = list;
    } else {
      return const [];
    }
    final out = <M3uChannel>[];
    final seen = <String>{};
    for (final raw in entries) {
      if (raw is! Map) continue;
      final channel = M3uChannel.fromJson(Map<String, dynamic>.from(raw));
      if (channel.name.isEmpty || !_isStreamUrl(channel.url)) continue;
      if (!seen.add(channel.url)) continue;
      out.add(channel);
    }
    return out;
  }

  /// The first comma outside a quoted attribute value. `group-title="News,
  /// World"` must not be mistaken for the attributes/name separator.
  static int _nameComma(String line) {
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        quoted = !quoted;
      } else if (c == ',' && !quoted) {
        return i;
      }
    }
    return -1;
  }

  static bool _isStreamUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static String _nameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    final withoutExt = segment.replaceFirst(RegExp(r'\.[^.]+$'), '');
    return withoutExt.isNotEmpty ? withoutExt : uri.host;
  }
}
