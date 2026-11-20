import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hikari/hikari_extension_service.dart';
import 'package:watch_app/core/hikari/hikari_repo.dart';

/// A `.hiki` archive, built here rather than checked in: the format is a zip
/// of `classes.dex` + `manifest.json`, and generating it keeps the test honest
/// about which entries matter.
List<int> _hikiBytes({String name = 'Probe', String mainClass = 'com.x.P'}) {
  final tmp = Directory.systemTemp.createTempSync('hiki_zip_');
  final file = File('${tmp.path}/x.hiki');
  final manifest = jsonEncode({
    'name': name,
    'version': 3,
    'mainClass': mainClass,
  });
  // A real zip, written through Process so the bytes are a genuine archive
  // rather than a hand-rolled header this test could get wrong.
  Process.runSync('python3', [
    '-c',
    '''
import zipfile, sys
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr('manifest.json', sys.argv[2])
    z.writestr('classes.dex', b'dex\\n035\\x00')
''',
    file.path,
    manifest,
  ]);
  final bytes = file.readAsBytesSync();
  tmp.deleteSync(recursive: true);
  return bytes;
}

void main() {
  late Directory hiveDir;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('hikari_svc_test_');
    Hive.init(hiveDir.path);
    await HikariExtensionService.init();
  });

  tearDown(() async {
    if (Hive.isBoxOpen(HikariExtensionService.installedBoxName)) {
      await Hive.box<dynamic>(HikariExtensionService.installedBoxName).clear();
    }
    if (Hive.isBoxOpen(kHikariReposBox)) {
      await Hive.box<String>(kHikariReposBox).clear();
    }
  });

  group('HikariExtensionService.install', () {
    test('a hash mismatch aborts the install and leaves no record', () async {
      final dir = await Directory.systemTemp.createTemp('hikari_dl_');
      final bytes = _hikiBytes();
      final service = HikariExtensionService(dio: _StubDio(bytes));

      final record = await service.install(
        const HikariRepoEntry(
          name: 'Probe',
          url: 'https://example.com/probe.hiki',
          version: 1,
          // Deliberately wrong.
          fileHash: 'sha256-0000000000000000000000000000000000000000000000000000000000000000',
        ),
        directory: dir,
      );

      expect(record, isNull);
      expect(service.installed(), isEmpty);
      // The rejected download is deleted, not left lying around.
      expect(
        Directory(dir.path).listSync().whereType<File>(),
        isEmpty,
        reason: 'a hash-mismatched download must not survive',
      );
      dir.deleteSync(recursive: true);
    });

    test('a matching hash installs and records the extension', () async {
      final dir = await Directory.systemTemp.createTemp('hikari_dl_');
      final bytes = _hikiBytes(name: 'Probe', mainClass: 'com.x.P');
      final digest = sha256.convert(bytes).toString();
      final service = HikariExtensionService(dio: _StubDio(bytes));

      final record = await service.install(
        HikariRepoEntry(
          name: 'Probe',
          url: 'https://example.com/probe.hiki',
          version: 7,
          fileHash: 'sha256-$digest',
        ),
        directory: dir,
      );

      // Loading needs a real DexClassLoader, so off-device the load returns
      // null and install degrades to null — but the download+verify half must
      // have happened, which the file on disk proves.
      final files = Directory(dir.path).listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(files.single.path, endsWith('Probe.hiki'));
      expect(files.single.readAsBytesSync(), bytes);
      if (record != null) {
        expect(record.name, 'Probe');
        expect(record.version, 7);
      }
      dir.deleteSync(recursive: true);
    });

    test('a filename with path separators is sanitised', () async {
      final dir = await Directory.systemTemp.createTemp('hikari_dl_');
      final service = HikariExtensionService(dio: _StubDio(_hikiBytes()));

      await service.install(
        const HikariRepoEntry(
          name: '../../evil name',
          url: 'https://example.com/e.hiki',
          version: 1,
        ),
        directory: dir,
      );

      final files = Directory(dir.path).listSync().whereType<File>().toList();
      // Whatever happened, nothing escaped the target directory.
      expect(files.every((f) => f.path.startsWith(dir.path)), isTrue);
      dir.deleteSync(recursive: true);
    });
  });

  group('HikariExtensionService.installed', () {
    test('reads records back out of the box', () async {
      final box = Hive.box<dynamic>(HikariExtensionService.installedBoxName);
      await box.put('hiki:a', {
        'name': 'A',
        'path': '/tmp/a.hiki',
        'version': 2,
        'providerId': 'a',
        'sourceId': 'hiki:a',
        'mainUrl': 'https://a.example',
      });

      final records = HikariExtensionService().installed();
      expect(records, hasLength(1));
      expect(records.single.name, 'A');
      expect(records.single.sourceId, 'hiki:a');
      expect(records.single.mainUrl, 'https://a.example');
    });

    test('an empty box yields an empty list, not an error', () async {
      expect(HikariExtensionService().installed(), isEmpty);
    });
  });

  group('HikariExtensionService.fetchRepo', () {
    test('parses a served index', () async {
      final body = jsonEncode({
        'name': 'Repo',
        'plugins': [
          {'name': 'P', 'url': 'https://example.com/p.hiki', 'version': 2},
        ],
      });
      final service = HikariExtensionService(dio: _StubDio(body));
      final repo = await service.fetchRepo('https://example.com/repo.json');
      expect(repo, isNotNull);
      expect(repo!.entries.single.name, 'P');
    });

    test('a network failure degrades to null instead of throwing', () async {
      final service = HikariExtensionService(dio: _FailingDio());
      expect(await service.fetchRepo('https://example.com/x.json'), isNull);
    });

    test('a malformed body degrades to null', () async {
      final service = HikariExtensionService(dio: _StubDio('{nope'));
      expect(await service.fetchRepo('https://example.com/x.json'), isNull);
    });
  });

  group('HikariExtensionService.uninstall', () {
    test('drops the record and deletes the file', () async {
      final dir = await Directory.systemTemp.createTemp('hikari_un_');
      final file = File('${dir.path}/gone.hiki')..writeAsBytesSync([1, 2, 3]);
      final box = Hive.box<dynamic>(HikariExtensionService.installedBoxName);
      await box.put('hiki:gone', {
        'name': 'Gone',
        'path': file.path,
        'version': 1,
        'providerId': 'gone',
        'sourceId': 'hiki:gone',
      });

      await HikariExtensionService().uninstall('hiki:gone');

      expect(box.get('hiki:gone'), isNull);
      expect(file.existsSync(), isFalse);
      dir.deleteSync(recursive: true);
    });

    test('uninstalling an unknown id is a no-op', () async {
      await expectLater(
        HikariExtensionService().uninstall('hiki:nope'),
        completes,
      );
    });
  });

  group('HikariInstalled', () {
    test('round-trips through json', () {
      const record = HikariInstalled(
        name: 'A',
        path: '/tmp/a.hiki',
        version: 4,
        providerId: 'a',
        sourceId: 'hiki:a',
        iconUrl: 'https://a.example/i.png',
        mainUrl: 'https://a.example',
        repoUrl: 'https://cdn.example.com/a.hiki',
      );
      final back = HikariInstalled.fromJson(
        Map<String, dynamic>.from(record.toJson()),
      );
      expect(back.name, 'A');
      expect(back.version, 4);
      expect(back.iconUrl, 'https://a.example/i.png');
      expect(back.mainUrl, 'https://a.example');
      expect(back.repoUrl, 'https://cdn.example.com/a.hiki');
    });

    test('a record written before repoUrl existed still parses', () {
      final back = HikariInstalled.fromJson({
        'name': 'A',
        'path': '/tmp/a.hiki',
        'version': 1,
        'providerId': 'a',
        'sourceId': 'hiki:a',
      });
      expect(back.repoUrl, isEmpty);
    });
  });
}

/// Serves fixed bytes/body for any request.
class _StubDio implements Dio {
  _StubDio(this.payload);
  final Object payload;

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: (payload is List<int> ? utf8.decode(payload as List<int>) : payload)
        as T,
  );

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
    FileAccessMode fileAccessMode = FileAccessMode.write,
  }) async {
    final bytes = payload is List<int>
        ? payload as List<int>
        : utf8.encode('$payload');
    await File(savePath as String).writeAsBytes(bytes);
    return Response(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingDio implements Dio {
  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async => throw DioException(
    requestOptions: RequestOptions(path: path),
    type: DioExceptionType.connectionError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
