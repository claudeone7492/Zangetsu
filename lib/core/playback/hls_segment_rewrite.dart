import 'dart:convert';

/// Pure line-level rewriting for [HlsSegmentProxy].
///
/// Kept dependency-free (no Flutter, no I/O) so the wrapper-unwrapping rules
/// are unit-testable in isolation.

/// Rewrites a P2P-wrapped HLS body so every segment line routes through
/// [proxify], which is handed the segment's real media URL and returns the
/// loopback URL to emit. Returns null when no line needed rewriting (a plain
/// playlist is opened unchanged).
String? proxyRewriteHlsBody(
  String body,
  Uri base,
  String Function(String mediaUrl) proxify,
) {
  var changed = false;
  final out = <String>[];
  for (final line in const LineSplitter().convert(body)) {
    final target = proxySegmentTarget(line, base);
    if (target == null) {
      out.add(line);
    } else {
      changed = true;
      out.add(proxify(target));
    }
  }
  return changed ? out.join('\n') : null;
}

/// The media URL behind one playlist line, or null when the line is already
/// directly playable (or is a comment/blank/playlist line).
String? proxySegmentTarget(String rawLine, Uri base) {
  final line = rawLine.trim();
  if (line.isEmpty || line.startsWith('#')) return null;
  Uri uri;
  try {
    uri = base.resolve(line);
  } catch (_) {
    return null;
  }
  // A nested playlist: leave it to FFmpeg (StreamFree serves a media playlist,
  // so this is only a guard).
  if (uri.path.toLowerCase().endsWith('.m3u8')) return null;
  // The media URL a P2P wrapper names in its `#sf=` fragment. A plain media
  // line (`.ts`/`.m4s`/…) has no fragment and is left for FFmpeg to fetch
  // directly, headers and all.
  return _sfFragment(uri);
}

/// Decodes a segment's `#sf=` fragment into the absolute media URL it names.
String? _sfFragment(Uri uri) {
  final frag = uri.fragment;
  if (frag.isEmpty || !frag.startsWith('sf=')) return null;
  var target = Uri.decodeComponent(frag.substring(3));
  if (target.isEmpty) return null;
  if (!target.contains('://')) {
    // Path-only target: it lives on the stream host, not the CDN.
    target =
        'https://cdn1.strmfree.st${target.startsWith('/') ? '' : '/'}$target';
  }
  return target;
}
