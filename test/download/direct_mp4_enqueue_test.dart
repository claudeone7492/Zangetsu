import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/download/download_manager.dart';
import 'package:watch_app/core/download/download_prefs.dart';
import 'package:watch_app/core/download/download_record.dart';
import 'package:watch_app/core/hive/safe_box.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/core/models/video_source.dart';
import 'package:watch_app/core/repository/catalogue_repository.dart';

/// Regression test for the "nothing downloads" report: a direct-file source
/// (a plain `.mp4`, no HLS/DASH) must actually leave the queue and start
/// downloading. The MP4 path goes through `background_downloader`'s TaskQueue
/// rather than the HLS/DASH foreground service, so a defect there shows up as a
/// record wedged at `queued` forever with no progress and no error — exactly
/// the symptom the user described.
///
/// The downloader runs against a loopback HTTP server so the whole path
/// (enqueue → resolve → queue advance → bytes on disk) is exercised for real,
/// with no mocks.
class _Catalogue implements CatalogueRepository {
  _Catalogue(this.source);
  final VideoSource source;
  @override
  Future<List<VideoSource>> sources(
    String episodeUrl, {
    String? sourceId,
    bool fast = false,
  }) async => [source];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestDownloaderStorage implements PersistentStorage {
  final _resume = <String, ResumeData>{};
  final _paused = <String, Task>{};
  @override
  Future<List<Task>> retrieveAllPausedTasks() async => _paused.values.toList();
  @override
  Future<Task?> retrievePausedTask(String taskId) async => _paused[taskId];
  @override
  Future<void> storePausedTask(Task task) async => _paused[task.taskId] = task;
  @override
  Future<void> removePausedTask(String? taskId) async {
    if (taskId == null) {
      _paused.clear();
    } else {
      _paused.remove(taskId);
    }
  }

  @override
  Future<ResumeData?> retrieveResumeData(String taskId) async => _resume[taskId];
  @override
  Future<List<ResumeData>> retrieveAllResumeData() async => _resume.values.toList();
  @override
  Future<void> storeResumeData(ResumeData resumeData) async =>
      _resume[resumeData.taskId] = resumeData;
  @override
  Future<void> removeResumeData(String? taskId) async {
    if (taskId == null) {
      _resume.clear();
    } else {
      _resume.remove(taskId);
    }
  }

  @override
  (String, int) get currentDatabaseVersion => ('test', 1);
  @override
  Future<(String, int)> get storedDatabaseVersion async =>
      currentDatabaseVersion;
  @override
  Future<void> initialize() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late HttpServer server;
  late Uri base;
  late DownloadManager manager;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FileDownloader(persistentStorage: _TestDownloaderStorage());
    hiveDir = await Directory.systemTemp.createTemp('direct_mp4_enqueue');
    hiveBoxDir = hiveDir.path;
    Hive.init(hiveDir.path);
    await DownloadPrefs.init();
    await DownloadManager.init();

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = Uri(scheme: 'http', host: '127.0.0.1', port: server.port);
    server.listen((req) async {
      final body = List<int>.filled(2 * 1024 * 1024, 0x41);
      req.response.headers.contentType = ContentType('video', 'mp4');
      req.response.headers.contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });

    manager = DownloadManager(
      _Catalogue(VideoSource(url: '${base.replace(path: '/v/ep1.mp4')}')),
      DownloadPrefs(),
    )..setup();
  });

  tearDown(() async {
    manager.dispose();
    await server.close(force: true);
    await Hive.close();
    debugDefaultTargetPlatformOverride = null;
    hiveBoxDir = null;
    if (await hiveDir.exists()) await hiveDir.delete(recursive: true);
  });

  test('a direct MP4 download leaves the queued state', () async {
    await manager.enqueueSource(
      sourceId: 'src',
      showId: 'show',
      showTitle: 'Show',
      showUrl: 'https://example.com/show',
      category: 'sub',
      episode: const Episode(
        id: 'e1',
        title: 'Episode 1',
        url: 'https://example.com/ep1',
        number: 1,
      ),
      source: VideoSource(url: '${base.replace(path: '/v/ep1.mp4')}'),
      qualityLabel: '1080p',
      nowMs: 1,
    );

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final rec = manager.all.single;
      if (rec.status != DownloadStatus.queued &&
          rec.status != DownloadStatus.resolving) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    final rec = manager.all.single;
    expect(
      rec.status,
      anyOf(DownloadStatus.downloading, DownloadStatus.done),
      reason: 'the task never left queued — the MP4 queue is not advancing',
    );
  });
}
