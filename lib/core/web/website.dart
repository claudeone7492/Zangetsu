import 'package:flutter/foundation.dart';

/// A site saved by the viewer and opened in the in-app browser.
@immutable
class Website {
  const Website({required this.id, required this.name, required this.url});

  final String id;
  final String name;
  final String url;

  String get host => Uri.tryParse(url)?.host ?? url;

  /// Adds `https://` when [raw] has no scheme and rejects anything that is not
  /// an http(s) address. Returns null when [raw] is not a usable URL.
  static String? normaliseUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty || uri.host.contains(RegExp(r'\s'))) return null;
    // A bare word is a search term, not a site. localhost stays usable.
    if (!uri.host.contains('.') && uri.host != 'localhost') return null;
    return uri.toString();
  }

  /// Stable identity: scheme and trailing slash do not make a second site.
  static String idFor(String url) {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '$host$path$query';
  }

  /// A readable fallback name when the viewer leaves the name blank.
  static String nameFor(String url) {
    final host = Uri.parse(url).host;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  factory Website.fromUrl(String name, String url) {
    final normalised = normaliseUrl(url)!;
    final trimmed = name.trim();
    return Website(
      id: idFor(normalised),
      name: trimmed.isEmpty ? nameFor(normalised) : trimmed,
      url: normalised,
    );
  }

  Map<String, String> toMap() => {'id': id, 'name': name, 'url': url};

  static Website? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String) return null;
    final normalised = normaliseUrl(url);
    if (normalised == null) return null;
    final id = raw['id'];
    final name = raw['name'];
    return Website(
      id: id is String && id.isNotEmpty ? id : idFor(normalised),
      name: name is String && name.trim().isNotEmpty
          ? name.trim()
          : nameFor(normalised),
      url: normalised,
    );
  }
}
