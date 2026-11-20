import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../hive/safe_box.dart';
import 'hikari_manager.dart';
import 'hikari_provider.dart';
import 'hikari_repo.dart';

/// Hive box holding the repository index URLs the user has added.
const String kHikariReposBox = 'hikari_repos';

/// The catalogue Hikari ships against. Its index lives on the `builds` branch
/// — `main/index.json` 404s — and lists 203 extensions.
const String kDefaultHikariRepo =
    'https://raw.githubusercontent.com/codegeasse1/hikari-extensions/builds/repo.json';

/// A `.hiki` file installed on disk.
class HikariInstalled {
  const HikariInstalled({
    required this.name,
    required this.path,
    required this.version,
    required this.providerId,
    required this.sourceId,
    this.iconUrl,
    this.mainUrl = '',
    this.repoUrl = '',
  });

  final String name;
  final String path;
  final int version;

  /// The provider's own id (from the extension's Kotlin code).
  final String providerId;

  /// Our namespaced source id (`hiki:<providerId>`).
  final String sourceId;

  final String? iconUrl;
  final String mainUrl;

  /// The `.hiki` URL this extension was downloaded from, when it came from a
  /// repository. Backup restore re-downloads from here: the index names a
  /// plugin independently of the provider id the archive declares, so there is
  /// no reliable way to match a restored id back to a catalogue entry.
  final String repoUrl;

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'version': version,
    'providerId': providerId,
    'sourceId': sourceId,
    if (iconUrl != null) 'iconUrl': iconUrl,
    'mainUrl': mainUrl,
    if (repoUrl.isNotEmpty) 'repoUrl': repoUrl,
  };

  factory HikariInstalled.fromJson(Map<String, dynamic> j) => HikariInstalled(
    name: (j['name'] ?? '').toString(),
    path: (j['path'] ?? '').toString(),
    version: j['version'] is int ? j['version'] as int : 1,
    providerId: (j['providerId'] ?? '').toString(),
    sourceId: (j['sourceId'] ?? '').toString(),
    iconUrl: j['iconUrl'] as String?,
    mainUrl: (j['mainUrl'] ?? '').toString(),
    repoUrl: (j['repoUrl'] ?? '').toString(),
  );
}

/// Installs, loads and removes `.hiki` extensions.
///
/// The `.hiki` file is downloaded to app support storage and handed to the
/// native host, which does the actual `DexClassLoader` work and returns the
/// provider's metadata. Nothing here can load an extension on its own — the
/// Dart side only ever holds a path and a description of what that path
/// yielded.
class HikariExtensionService {
  HikariExtensionService({Dio? dio}) : _dio = dio;

  final Dio? _dio;

  /// Installed extensions, keyed by our `hiki:<providerId>` source id.
  static const String installedBoxName = 'hikari_installed';

  static Future<void> init() async {
    if (!Hive.isBoxOpen(installedBoxName)) {
      await openBoxSafely<dynamic>(installedBoxName);
    }
  }

  Box<dynamic>? get _box =>
      Hive.isBoxOpen(installedBoxName) ? Hive.box(installedBoxName) : null;

  /// Every installed extension recorded in the box.
  List<HikariInstalled> installed() {
    final box = _box;
    if (box == null) return const [];
    final out = <HikariInstalled>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        out.add(HikariInstalled.fromJson(Map<String, dynamic>.from(raw)));
      }
    }
    return out;
  }

  /// Fetches and parses a repository index. Never throws — a bad or
  /// unreachable index degrades to null so the UI can say "couldn't load".
  Future<HikariRepo?> fetchRepo(String url) async {
    try {
      final dio = _dio ?? Dio();
      final res = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Cache-Control': 'no-cache'},
        ),
      );
      final body = res.data;
      if (body == null || body.isEmpty) return null;
      return HikariRepo.parse(body, baseUrl: url);
    } catch (e) {
      debugPrint('[hikari] repo fetch failed: $e');
      return null;
    }
  }

  /// Downloads [entry] and installs it.
  ///
  /// Returns the loaded extension on success, or null on failure. A
  /// [HikariRepoEntry.sha256Hex] mismatch aborts the install: the index
  /// publishes a digest and honouring it is the only integrity check available
  /// for code we are about to execute in-process.
  Future<HikariInstalled?> install(
    HikariRepoEntry entry, {
    Directory? directory,
    HikariManager? manager,
  }) async {
    try {
      final dir = directory ?? await _defaultDir();
      await dir.create(recursive: true);

      final safeName = _safeFileName(entry.name);
      final path = '${dir.path}/$safeName.hiki';
      final file = File(path);

      // A previous load marks the dex read-only inside the archive extraction,
      // not the archive itself, but a stale file would still be replaced.
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final dio = _dio ?? Dio();
      await dio.download(
        entry.url,
        path,
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
          headers: {'Cache-Control': 'no-cache'},
        ),
      );

      final expected = entry.sha256Hex;
      if (expected != null) {
        final actual = sha256.convert(await file.readAsBytes()).toString();
        if (actual.toLowerCase() != expected) {
          await file.delete().catchError((_) => file);
          debugPrint(
            '[hikari] hash mismatch for ${entry.name}: '
            'expected $expected, got $actual',
          );
          return null;
        }
      }

      return installFile(
        path,
        fallbackName: entry.name,
        manager: manager,
        repoUrl: entry.url,
      );
    } catch (e) {
      debugPrint('[hikari] install failed for ${entry.name}: $e');
      return null;
    }
  }

  /// Loads an already-downloaded `.hiki` from [path] and records it.
  ///
  /// Split from [install] so the "install from file" flow (a user-supplied
  /// `.hiki`) shares the exact same loading and persistence path as a repo
  /// install.
  Future<HikariInstalled?> installFile(
    String path, {
    String fallbackName = '',
    HikariManager? manager,
    String repoUrl = '',
  }) async {
    try {
      final info = await hikariLoad(path);
      if (info == null) {
        debugPrint('[hikari] load returned nothing for $path');
        return null;
      }
      final sourceId = 'hiki:${info.providerId.isEmpty ? info.name : info.providerId}';
      final record = HikariInstalled(
        name: info.providerName.isEmpty
            ? (info.name.isEmpty ? fallbackName : info.name)
            : info.providerName,
        path: path,
        version: info.version,
        providerId: info.providerId,
        sourceId: sourceId,
        iconUrl: info.iconUrl,
        mainUrl: info.mainUrl,
        repoUrl: repoUrl,
      );
      await _box?.put(sourceId, record.toJson());
      manager?.register(
        HikariProviderAdapter(path: path, info: info, lang: ''),
      );
      return record;
    } catch (e) {
      debugPrint('[hikari] installFile failed for $path: $e');
      return null;
    }
  }

  /// Uninstalls [sourceId]: unloads it natively, drops the record, deletes the
  /// file, and removes it from [manager].
  Future<void> uninstall(String sourceId, {HikariManager? manager}) async {
    final record = installed().where((e) => e.sourceId == sourceId).firstOrNull;
    await hikariUnload(record?.path ?? '');
    await _box?.delete(sourceId);
    manager?.removeWhere((p) => p.sourceId == sourceId);
    final path = record?.path;
    if (path != null && path.isNotEmpty) {
      try {
        final f = File(path);
        if (await f.exists()) await f.delete();
      } catch (e) {
        debugPrint('[hikari] could not delete $path: $e');
      }
    }
  }

  /// Reloads every recorded extension into [manager] on a cold start.
  ///
  /// A record whose file has vanished (cleared cache, user deleted it) is
  /// dropped instead of being retried forever.
  Future<void> loadInstalledInto(HikariManager manager) async {
    for (final record in installed()) {
      final file = File(record.path);
      if (!await file.exists()) {
        await _box?.delete(record.sourceId);
        continue;
      }
      final info = await hikariLoad(record.path);
      if (info == null) continue;
      manager.register(
        HikariProviderAdapter(path: record.path, info: info, lang: ''),
      );
    }
  }

  Future<Directory> _defaultDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}/hikari');
  }

  /// A filename that is safe on every filesystem and still recognisable.
  static String _safeFileName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'extension' : cleaned;
  }
}

/// JSON encoding helper kept next to the box writes so the two never drift.
String hikariRecordJson(HikariInstalled record) => jsonEncode(record.toJson());
