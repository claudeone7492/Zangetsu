/// Public stream relay used as a hidden fallback when a direct live stream is
/// blocked by the viewer's region or ISP.
///
/// This is the same NetWeb gateway the bundled VidSrc provider already uses.
/// It passes the upstream body through and rewrites HLS playlists so every
/// variant/segment line points back at the relay, which means a live sports
/// playlist keeps working after the first request.
///
/// It is a fallback only: the player opens the provider's direct URL first and
/// swaps to this URL if the direct stream never starts or errors. Nothing is
/// relayed on a normal connection, so playback latency is unchanged.
class RelayProxy {
  RelayProxy._();

  static const String base = 'https://netweb-cvu7.onrender.com/proxy?url=';

  /// True when [url] is a remote HTTP(S) stream that can be relayed.
  static bool canWrap(String url) {
    final value = url.trim();
    if (value.isEmpty) return false;
    if (isRelayed(value)) return false;
    final uri = Uri.tryParse(value);
    if (uri == null) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.endsWith('.local')) {
      return false;
    }
    return true;
  }

  static String wrap(String url) => '$base${Uri.encodeComponent(url)}';

  /// Returns the relay URL for [url], or null when it cannot be relayed.
  static String? wrapIfPossible(String url) => canWrap(url) ? wrap(url) : null;

  static bool isRelayed(String url) {
    final value = url.trim();
    return value.startsWith(base) ||
        value.contains('netweb-cvu7.onrender.com/proxy?url=');
  }
}
