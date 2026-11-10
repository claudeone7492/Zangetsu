import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/video_source.dart';
import 'dash_manifest.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Download size estimates. Shown with a "~" and used only for display + the
// low-storage warning — never for decisions that must be exact. Anything
// unknowable returns null, and callers treat null as "no estimate", not zero.
//
// Direct files: HEAD content-length. HLS master playlists: variant bitrate ×
// episode runtime. DASH, media playlists and missing runtimes: null.
// ─────────────────────────────────────────────────────────────────────────────

/// One variant from an HLS master playlist.
typedef HlsVariant = ({int bandwidth, int? height});

/// Variants listed in an HLS master playlist, fastest first. Media playlists
/// (no `#EXT-X-STREAM-INF`) yield nothing — their bitrate isn't stated.
List<HlsVariant> parseHlsVariants(String manifest) {
  final out = <HlsVariant>[];
  final lines = manifest.split('\n');
  for (final raw in lines) {
    final line = raw.trim();
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    final bw = RegExp(r'(?:^|[:,])BANDWIDTH=(\d+)').firstMatch(line);
    if (bw == null) continue;
    final res = RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(line);
    out.add((
      bandwidth: int.parse(bw.group(1)!),
      height: res == null ? null : int.tryParse(res.group(1)!),
    ));
  }
  out.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
  return out;
}

/// Total bitrate (bits/s) of the DASH tracks an episode download would fetch:
/// the video representation closest to [quality] plus the best audio
/// representation. Null when the manifest states no usable bandwidth.
///
/// Reuses [parseDashManifest] so the estimate matches what the downloader will
/// actually pick; it is only a display estimate, never a decision.
int? dashTotalBitrate(String mpd, String? quality) {
  final manifest = parseDashManifest(
    mpd,
    'https://estimate.invalid/',
    quality: quality ?? 'best',
  );
  if (manifest == null || manifest.isEmpty) return null;
  final total =
      (manifest.video?.bandwidth ?? 0) + (manifest.audio?.bandwidth ?? 0);
  return total > 0 ? total : null;
}

/// Height parsed from a quality label like "1080p" or "720p60", else null
/// (covers 'best'/'auto' and label-less sources).
int? qualityHeight(String? quality) {
  if (quality == null) return null;
  final m = RegExp(r'(\d{3,4})').firstMatch(quality);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// Total seconds stated by an HLS *media* playlist (EXTINF segments), or
/// null when the body isn't a media playlist at all. Guards the assumed-
/// bitrate fallback so an error page can never fabricate a size.
int? parseHlsMediaDurationSec(String manifest) {
  if (!manifest.contains('#EXTM3U') || !manifest.contains('#EXTINF')) {
    return null;
  }
  var total = 0.0;
  var found = false;
  for (final raw in manifest.split('\n')) {
    final m = RegExp(r'#EXTINF:([\d.]+)').firstMatch(raw.trim());
    if (m != null) {
      total += double.tryParse(m.group(1)!) ?? 0;
      found = true;
    }
  }
  return found && total > 0 ? total.round() : null;
}

/// Assumed bits-per-second per height, used ONLY for media playlists that
/// state no bitrate. Deliberately coarse — callers mark these low-confidence
/// (shown, but never trigger the storage warning).
int? assumedBitrateForHeight(int? height) => switch (height) {
  null => null,
  >= 1080 => 8000000,
  >= 720 => 4000000,
  >= 480 => 2000000,
  _ => 1000000,
};

/// Estimate + whether it's solid enough to warn on. Direct sizes and master-
/// playlist math are high confidence; assumed bitrates are not.
typedef SizeEstimate = ({int bytes, bool solid});

/// Bytes for one episode at the wanted variant, or null when unknowable.
/// Prefers the variant matching [wantedHeight]; otherwise the fastest.
int? hlsVariantBytes(
  List<HlsVariant> variants, {
  int? wantedHeight,
  required int runtimeSec,
}) {
  if (variants.isEmpty || runtimeSec <= 0) return null;
  var pick = variants.first;
  if (wantedHeight != null) {
    for (final v in variants) {
      if (v.height == wantedHeight) {
        pick = v;
        break;
      }
    }
  }
  return pick.bandwidth ~/ 8 * runtimeSec;
}

String formatApproxBytes(int bytes) {
  if (bytes >= 1 << 30) return '~${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '~${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
  if (bytes >= 1 << 10) return '~${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
  return '~$bytes B';
}

/// Estimated bytes of ONE episode from [source], plus whether the number is
/// solid enough to warn on. Null when unknowable — callers hide the estimate
/// and skip the storage warning rather than guess.
Future<SizeEstimate?> estimateEpisodeBytes(
  VideoSource source, {
  int? runtimeMinutes,
  HttpClient? client,
}) async {
  final url = source.url.trim();
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;
  if (url.contains('.mpd')) {
    // DASH: the manifest states each representation's bandwidth, so a size is
    // bitrate × runtime — the same estimate HLS masters get. Parse it rather
    // than skip; a wrong-by-a-bit estimate beats "unknown" for the storage
    // warning. Falls back to null when the runtime or bitrate is missing.
    final headers = source.headers ?? const <String, String>{};
    final owned = client == null;
    final http = client ?? HttpClient();
    http.connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await http.getUrl(uri);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 400) return null;
      final bytes = await res.fold<List<int>>(<int>[], (buffer, chunk) {
        if (buffer.length + chunk.length > 2 * 1024 * 1024) {
          throw const FormatException('MPD too large for a size estimate');
        }
        return buffer..addAll(chunk);
      }).timeout(const Duration(seconds: 10));
      final runtimeSec = (runtimeMinutes ?? 0) * 60;
      final bitrate = dashTotalBitrate(utf8.decode(bytes), source.quality);
      if (bitrate == null || runtimeSec <= 0) return null;
      return (bytes: bitrate ~/ 8 * runtimeSec, solid: false);
    } catch (_) {
      return null;
    } finally {
      if (owned) http.close(force: true);
    }
  }
  final isHls =
      source.container == SourceContainer.hls || url.contains('.m3u8');
  final owned = client == null;
  final http = client ?? HttpClient();
  http.connectionTimeout = const Duration(seconds: 8);
  try {
    final headers = source.headers ?? const <String, String>{};
    if (!isHls) {
      final req = await http.openUrl('HEAD', uri);
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 8));
      await res.drain<void>().timeout(const Duration(seconds: 8));
      if (res.statusCode != HttpStatus.ok) return null;
      final len = res.contentLength;
      return len > 0 ? (bytes: len, solid: true) : null;
    }
    final req = await http.getUrl(uri);
    headers.forEach(req.headers.set);
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode < 200 || res.statusCode >= 400) return null;
    final bytes = await res
        .fold<List<int>>(<int>[], (buffer, chunk) {
          if (buffer.length + chunk.length > 1024 * 1024) {
            throw const FormatException(
              'Playlist too large for a size estimate',
            );
          }
          return buffer..addAll(chunk);
        })
        .timeout(const Duration(seconds: 10));
    final body = utf8.decode(bytes);
    final runtimeSec = (runtimeMinutes ?? 0) * 60;
    final fromVariants = hlsVariantBytes(
      parseHlsVariants(body),
      wantedHeight: qualityHeight(source.quality),
      runtimeSec: runtimeSec,
    );
    if (fromVariants != null) return (bytes: fromVariants, solid: true);
    // Media playlist: durations are stated, bitrate isn't — assume one for
    // the quality and mark it low-confidence (shown, never warns).
    final mediaSec = parseHlsMediaDurationSec(body);
    final assumed = assumedBitrateForHeight(qualityHeight(source.quality));
    if (mediaSec == null || assumed == null) return null;
    return (bytes: assumed ~/ 8 * mediaSec, solid: false);
  } catch (_) {
    return null;
  } finally {
    if (owned) http.close(force: true);
  }
}
