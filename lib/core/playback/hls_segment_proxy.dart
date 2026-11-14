import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../download/hls_downloader.dart';
import '../logging/app_logger.dart';
import 'hls_segment_rewrite.dart';

/// Local HTTP proxy that makes a header-locked, P2P-wrapped HLS playlist
/// playable in mpv.
///
/// Some CDNs (StreamFree's live-sports feed is the motivating one) hand out a
/// playlist whose segment URIs are not directly playable. Each line points at a
/// P2P object on a CDN host and carries the real media URL in its `#sf=`
/// fragment; that real URL is itself header-gated (the CDN checks the embed
/// `Referer`). FFmpeg can't follow the fragment, and even the unwrapped URL
/// 403s without the headers — so a plain `player.open(playlist)` shows nothing.
///
/// [rewrite] fetches the playlist once, maps every segment line to its
/// unwrapped target, and returns a `127.0.0.1` playlist URL. Segments are then
/// fetched on demand through this server, which re-issues each request with the
/// source's headers (Referer / Origin / User-Agent). mpv only ever sees plain
/// loopback URLs, so no per-segment headers are needed on its side.
///
/// Pure Dart (`dart:io`), no dependency. One proxy per app; the token maps grow
/// with each playlist refresh and are pruned by age.
class HlsSegmentProxy {
  HlsSegmentProxy._();
  static final HlsSegmentProxy instance = HlsSegmentProxy._();

  HttpServer? _server;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20)
    ..autoUncompress = false;

  int _seq = 0;
  final Map<String, _Seg> _segments = {};

  /// A rewritten playlist's own token → the segment ids it owns, so a stale
  /// refresh can be pruned once its playlist is long gone.
  final Map<String, List<String>> _playlists = {};

  Future<int> _ensureStarted() async {
    final s = _server;
    if (s != null) return s.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle, onError: (_) {});
    _server = server;
    return server.port;
  }

  /// Fetches [playlistUrl] and returns a loopback URL serving a copy whose
  /// segment lines are proxied. Returns null when the playlist isn't
  /// segment-wrapped (nothing to do) or can't be read — the caller should then
  /// open [playlistUrl] as-is.
  Future<String?> rewrite(
    String playlistUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final body = await _fetchText(playlistUrl, headers);
      if (body == null || !body.contains('#EXTM3U')) return null;
      final ids = <String>[];
      final rewritten = proxyRewriteHlsBody(
        body,
        Uri.parse(playlistUrl),
        (url) {
          final id = '${_seq++}';
          _segments[id] = _Seg(url, headers ?? const {});
          ids.add(id);
          return '/s/$id';
        },
      );
      if (rewritten == null) return null;
      final port = await _ensureStarted();
      final token = 'p${_seq++}';
      _playlists[token] = ids;
      _prune();
      return 'http://127.0.0.1:$port/pl/$token.m3u8';
    } catch (e) {
      AppLogger.instance.log('[seg-proxy] rewrite failed: $e', level: 'W');
      return null;
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final segs = req.uri.pathSegments;
      if (segs.length == 2 && segs[0] == 's') {
        await _serveSegment(res, segs[1], req);
      } else if (segs.length == 2 && segs[0] == 'pl') {
        await _servePlaylist(res, segs[1]);
      } else {
        res.statusCode = HttpStatus.notFound;
        await res.close();
      }
    } catch (e) {
      AppLogger.instance.log('[seg-proxy] serve error: $e', level: 'E');
      try {
        res.statusCode = HttpStatus.badGateway;
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> _servePlaylist(HttpResponse res, String name) async {
    final token = name.contains('.') ? name.substring(0, name.indexOf('.')) : name;
    final ids = _playlists[token];
    if (ids == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final buffer = StringBuffer('#EXTM3U\n');
    for (final id in ids) {
      buffer.writeln('/s/$id');
    }
    res.statusCode = HttpStatus.ok;
    res.headers.contentType =
        ContentType('application', 'vnd.apple.mpegurl');
    res.write(buffer.toString());
    await res.close();
  }

  Future<void> _serveSegment(
    HttpResponse res,
    String id,
    HttpRequest req,
  ) async {
    final seg = _segments[id];
    if (seg == null) {
      res.statusCode = HttpStatus.notFound;
      await res.close();
      return;
    }
    final up = await _client.getUrl(Uri.parse(seg.url));
    seg.headers.forEach(up.headers.set);
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null) up.headers.set(HttpHeaders.rangeHeader, range);
    final upRes = await up.close();
    final raw = await _readBytes(upRes);
    if (upRes.statusCode >= 400) {
      res.statusCode = upRes.statusCode;
      await res.close();
      return;
    }
    final media = hlsUnwrapSegment(raw) ?? raw;
    res.statusCode = upRes.statusCode == HttpStatus.partialContent
        ? HttpStatus.partialContent
        : HttpStatus.ok;
    res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    res.headers.contentType = ContentType.parse(_mime(media));
    res.contentLength = media.length;
    res.add(media);
    await res.close();
  }

  String _mime(Uint8List data) {
    if (data.isNotEmpty && data[0] == 0x47) return 'video/mp2t';
    if (isoLooksLikeFmp4(data)) return 'video/mp4';
    return 'application/octet-stream';
  }

  Future<String?> _fetchText(String url, Map<String, String>? headers) async {
    final req = await _client.getUrl(Uri.parse(url));
    headers?.forEach(req.headers.set);
    req.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    final res = await req.close();
    if (res.statusCode >= 400) {
      await res.drain<void>();
      return null;
    }
    final raw = await _readBytes(res);
    return utf8.decode(raw, allowMalformed: true);
  }

  Future<Uint8List> _readBytes(HttpClientResponse res) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    final raw = builder.takeBytes();
    final enc =
        res.headers.value(HttpHeaders.contentEncodingHeader)?.toLowerCase();
    final gzipMagic = raw.length >= 2 && raw[0] == 0x1f && raw[1] == 0x8b;
    if (enc == 'gzip' || gzipMagic) return Uint8List.fromList(gzip.decode(raw));
    return raw;
  }

  /// Drops the oldest playlists (and their segments) once a session has piled
  /// up a few refreshes' worth, so a long live session doesn't leak.
  void _prune() {
    const keep = 8;
    while (_playlists.length > keep) {
      final oldest = _playlists.keys.first;
      for (final id in _playlists.remove(oldest) ?? const <String>[]) {
        _segments.remove(id);
      }
    }
  }
}

class _Seg {
  const _Seg(this.url, this.headers);
  final String url;
  final Map<String, String> headers;
}
