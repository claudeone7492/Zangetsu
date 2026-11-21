import 'dart:io';

import 'package:dio/dio.dart';

import 'music_models.dart';

/// Saves a resolved track URL to the app's music folder.
class MusicDownload {
  MusicDownload(this._dio, {required this.directory});

  final Dio _dio;
  final Directory directory;

  Future<File> save(
    MusicTrack track,
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    if (!directory.existsSync()) await directory.create(recursive: true);
    final name = _safeName('${track.artist ?? 'Unknown'} - ${track.title}');
    final file = File('${directory.path}/$name.m4a');
    await _dio.download(
      url,
      file.path,
      onReceiveProgress: onProgress,
      options: Options(followRedirects: true, receiveTimeout: const Duration(minutes: 5)),
    );
    return file;
  }

  static String _safeName(String value) => value
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
