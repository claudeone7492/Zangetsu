import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../models/video_source.dart';
import 'net_tuning.dart';

/// A refined source list plus the slowest probe that produced it.
typedef ProbeSweep = ({List<VideoSource> sources, bool slow, String host});

/// The playable form of a URL: the direct stream and the container it uses.
class StreamProbeResult {
  const StreamProbeResult({
    required this.url,
    required this.container,
    this.contentType,
    this.statusCode,
    this.elapsedMs = 0,
  });

  final String url;
  final SourceContainer container;
  final String? contentType;
  final int? statusCode;

  /// How long the probe took, including any wrapper hops.
  final int elapsedMs;

  /// True when the host answered slowly enough to explain buffering.
  bool get slow => elapsedMs >= StreamProbe.slowThresholdMs;

  /// Host that served (or wrapped) the stream.
  String get host => Uri.tryParse(url)?.host ?? '';
}

/// Resolves a provider's wrapper page to a direct stream before playback.
///
/// Providers sometimes hand back the embed page rather than the stream, and a
/// direct URL without an extension gives the player nothing to sniff. A probe
/// reads only the first 16 KB, follows up to three HTML hops, and caches the
/// answer for five minutes. A 4xx/5xx marks the URL bad so a later failover
/// skips it instead of trying the same dead host again.
class StreamProbe {
  const StreamProbe._();

  static const int _maxDepth = 3;
  static const int _headBytes = 16 * 1024;
  static const Duration _ttl = Duration(minutes: 5);

  /// A probe slower than this is worth explaining to the viewer: the host, not
  /// their Wi-Fi, is the likeliest reason the stream keeps stalling.
  static const int slowThresholdMs = 2500;

  static final Map<String, _Entry> _cache = {};
  static final Set<String> _bad = {};

  static bool knownBad(String url) => _bad.contains(url);

  static StreamProbeResult? cached(String url) {
    final entry = _cache[url];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.at) > _ttl) {
      _cache.remove(url);
      return null;
    }
    return entry.result;
  }

  static void clearCache() {
    _cache.clear();
    _bad.clear();
  }

  /// A URL without a media extension may be a wrapper page; probing it is the
  /// only way to learn what it serves. Direct media and non-http URLs are left
  /// to the player.
  static bool needsResolve(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return false;
    }
    final path = uri.path.toLowerCase();
    const extensions = [
      '.m3u8',
      '.mpd',
      '.mp4',
      '.mkv',
      '.webm',
      '.ts',
      '.m4v',
      '.mov',
      '.avi',
      '.flv',
    ];
    return !extensions.any(path.endsWith);
  }

  static Future<StreamProbeResult?> resolve(
    String url, {
    Dio? dio,
    Map<String, String>? headers,
  }) async {
    final hit = cached(url);
    if (hit != null) return hit;
    if (knownBad(url)) return null;
    if (_cache.length > 200) _prune();

    final sw = Stopwatch()..start();
    final client = dio ?? Dio();
    var current = url;
    for (var depth = 0; depth < _maxDepth; depth++) {
      final Response<List<int>> res;
      try {
        res = await client.get<List<int>>(
          current,
          options: Options(
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (_) => true,
            headers: {
              ...?headers,
              'Range': 'bytes=0-${_headBytes - 1}',
            },
            receiveTimeout: NetTuning.timeout(const Duration(seconds: 8)),
            sendTimeout: NetTuning.timeout(const Duration(seconds: 8)),
          ),
        );
      } catch (_) {
        return null;
      }
      final status = res.statusCode ?? 0;
      if (status >= 400) {
        _bad.add(current);
        return null;
      }
      final bytes = res.data ?? const <int>[];
      final head = utf8.decode(bytes, allowMalformed: true);
      final contentType = res.headers.value(Headers.contentTypeHeader);
      final result = _classify(
        current,
        head,
        contentType,
        status,
        sw.elapsedMilliseconds,
      );
      if (result != null) {
        _cache[current] = _Entry(result, DateTime.now());
        return result;
      }
      final next = _extractMedia(head, res.requestOptions.uri);
      if (next == null || next == current) return null;
      current = next;
    }
    return null;
  }

  static StreamProbeResult? _classify(
    String url,
    String head,
    String? contentType,
    int status,
    int elapsedMs,
  ) {
    final type = (contentType ?? '').toLowerCase();
    if (head.trimLeft().startsWith('#EXTM3U') || type.contains('mpegurl')) {
      return StreamProbeResult(
        url: url,
        container: SourceContainer.hls,
        contentType: contentType,
        statusCode: status,
        elapsedMs: elapsedMs,
      );
    }
    if (head.contains('<MPD') || type.contains('dash')) {
      return StreamProbeResult(
        url: url,
        container: SourceContainer.unknown,
        contentType: contentType,
        statusCode: status,
        elapsedMs: elapsedMs,
      );
    }
    if (type.startsWith('video/') || head.contains('ftyp')) {
      return StreamProbeResult(
        url: url,
        container: SourceContainer.mp4,
        contentType: contentType,
        statusCode: status,
        elapsedMs: elapsedMs,
      );
    }
    return null;
  }

  static final RegExp _absoluteMedia = RegExp(
    r'''(?:https?:)?//[^\s"'<>\\]+?\.(?:m3u8|mpd|mp4|mkv|webm|ts|m4v|mov)(?:\?[^\s"'<>\\]*)?''',
    caseSensitive: false,
  );

  static final RegExp _jsonMedia = RegExp(
    r'''["'](?:file|src|url|stream)["']\s*:\s*["']([^"']+?\.(?:m3u8|mpd|mp4|mkv|webm|ts|m4v|mov)(?:\?[^"']*)?)["']''',
    caseSensitive: false,
  );

  static String? _extractMedia(String body, Uri base) {
    final json = _jsonMedia.firstMatch(body);
    if (json != null) {
      return _absolute(base, json.group(1)!);
    }
    final absolute = _absoluteMedia.firstMatch(body);
    if (absolute != null) {
      return _absolute(base, absolute.group(0)!);
    }
    return null;
  }

  static String _absolute(Uri base, String raw) {
    final unescaped = raw
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll('&amp;', '&');
    return base.resolve(unescaped).toString();
  }

  /// Probes the wrapper URLs in [sources] four at a time, drops the ones that
  /// answered with an error, and rewrites the rest to the direct stream. The
  /// original list is returned when every probe failed, so a probe outage can
  /// never leave the sheet empty.
  static Future<List<VideoSource>> refine(
    List<VideoSource> sources, {
    Dio? dio,
  }) async => (await refineNoted(sources, dio: dio)).sources;

  /// [refine], plus the slowest host it met. A host that took seconds to answer
  /// is the likeliest reason the stream keeps stalling, so the player can say
  /// so once instead of leaving the viewer to guess.
  static Future<ProbeSweep> refineNoted(
    List<VideoSource> sources, {
    Dio? dio,
  }) async {
    if (sources.isEmpty) {
      return (sources: sources, slow: false, host: '');
    }
    final client = dio ?? Dio();
    final out = <VideoSource>[];
    StreamProbeResult? slowest;
    for (var i = 0; i < sources.length; i += 4) {
      final chunk = sources.sublist(i, math.min(i + 4, sources.length));
      final resolved = await Future.wait(
        chunk.map((source) async {
          if (!needsResolve(source.url)) {
            final live = !knownBad(source.url);
            return (live ? source : null, null as StreamProbeResult?);
          }
          final result = await resolve(
            source.url,
            dio: client,
            headers: source.headers,
          );
          if (result == null) {
            return (null as VideoSource?, null as StreamProbeResult?);
          }
          return (
            source.withUrlAndContainer(result.url, result.container),
            result,
          );
        }),
      );
      for (final (source, probe) in resolved) {
        if (source != null) out.add(source);
        if (probe != null &&
            (slowest == null || probe.elapsedMs > slowest.elapsedMs)) {
          slowest = probe;
        }
      }
    }
    return (
      sources: out.isEmpty ? sources : out,
      slow: slowest?.slow ?? false,
      host: slowest?.host ?? '',
    );
  }

  static void _prune() {
    final now = DateTime.now();
    _cache.removeWhere((_, entry) => now.difference(entry.at) > _ttl);
  }
}

class _Entry {
  _Entry(this.result, this.at);

  final StreamProbeResult result;
  final DateTime at;
}
