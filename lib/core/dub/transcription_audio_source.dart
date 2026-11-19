import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'voice_transcriber.dart';

/// Gets the audio bytes a transcription needs out of whatever the player is
/// playing.
///
/// A transcription endpoint wants a media file it can decode, but a player is
/// given a URL that may be a direct file, an HLS playlist, or a signed link that
/// expires. Only the direct-file case can be handed over whole — an HLS stream
/// is hundreds of segments, and reassembling them is a download job, not
/// something to do behind a menu tap. So this resolves what it can and refuses
/// the rest with a reason the viewer can act on, rather than failing mid-upload.
class TranscriptionAudioSource {
  TranscriptionAudioSource({Dio? dio, this.maxBytes = 200 * 1024 * 1024})
    : _dio = dio ?? Dio();

  final Dio _dio;

  /// Uploading a whole season's worth of video would fail at the endpoint and
  /// waste the viewer's data. The cap is generous for one episode and well under
  /// what hosted endpoints accept.
  final int maxBytes;

  /// Containers a Whisper endpoint decodes. A video container is fine — the
  /// audio track is what gets read.
  static const Set<String> supportedExtensions = {
    'mp3',
    'mp4',
    'm4a',
    'wav',
    'webm',
    'ogg',
    'flac',
    'mkv',
    'mov',
    'aac',
    'ts',
  };

  /// Whether [url] looks like a single file that can be uploaded.
  ///
  /// A playlist is rejected here rather than after a failed download: `.m3u8`
  /// and `master.txt` are the two shapes the app's sources use for HLS.
  static bool isDirectMediaUrl(String url) {
    final path = _pathOf(url);
    if (path.isEmpty) return false;
    final lower = path.toLowerCase();
    if (lower.endsWith('.m3u8') || lower.endsWith('.m3u')) return false;
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    return supportedExtensions.contains(lower.substring(dot + 1));
  }

  /// Resolves [url] — a local path or an http(s) URL — into uploadable bytes.
  ///
  /// Throws [TranscriptionException] when the source cannot be transcribed,
  /// with a message written for the viewer.
  Future<Uint8List> resolve(
    String url, {
    Map<String, String>? headers,
    void Function(double)? onProgress,
  }) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      throw const TranscriptionException('Nothing is playing to transcribe');
    }

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return _readLocal(trimmed);
    }
    if (!isDirectMediaUrl(trimmed)) {
      throw const TranscriptionException(
        'This source streams in segments, so it can\'t be transcribed',
      );
    }

    final Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(
        trimmed,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: (_) => true,
          receiveTimeout: const Duration(minutes: 10),
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
    } on DioException catch (e) {
      throw TranscriptionException(
        e.type == DioExceptionType.connectionError
            ? 'Couldn\'t download the audio to transcribe'
            : 'Downloading the audio failed',
      );
    }

    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw TranscriptionException('Downloading the audio failed ($status)');
    }
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (bytes.isEmpty) {
      throw const TranscriptionException('The source returned no audio');
    }
    if (bytes.length > maxBytes) {
      throw const TranscriptionException(
        'The episode is too large to upload for transcription',
      );
    }
    return bytes;
  }

  /// The filename to report to the endpoint, which uses the extension to pick a
  /// decoder.
  static String fileNameFor(String url) {
    final path = _pathOf(url);
    final name = path.isEmpty ? '' : path.split('/').last;
    if (name.isNotEmpty && name.contains('.')) return name;
    return 'audio.mp3';
  }

  Future<Uint8List> _readLocal(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const TranscriptionException('The audio file is missing');
    }
    final length = await file.length();
    if (length == 0) {
      throw const TranscriptionException('The audio file is empty');
    }
    if (length > maxBytes) {
      throw const TranscriptionException(
        'The episode is too large to upload for transcription',
      );
    }
    return file.readAsBytes();
  }

  /// The path part of [url], with the query and fragment removed — a signed
  /// link's signature would otherwise hide the extension.
  static String _pathOf(String url) {
    var path = url;
    final query = path.indexOf('?');
    if (query >= 0) path = path.substring(0, query);
    final fragment = path.indexOf('#');
    if (fragment >= 0) path = path.substring(0, fragment);
    final scheme = path.indexOf('://');
    if (scheme >= 0) {
      final slash = path.indexOf('/', scheme + 3);
      path = slash >= 0 ? path.substring(slash) : '';
    }
    return path;
  }
}
