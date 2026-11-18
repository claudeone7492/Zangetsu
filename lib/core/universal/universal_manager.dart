import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';

import 'universal_config.dart';
import 'universal_provider.dart';

/// A universal-scraper repo: a JSON document with a `sources` array, each
/// entry a full [UniversalConfig] (inline) or a URL to one. One repo URL is
/// enough to install many sources — the "add a whole collection in one tap"
/// shape Hikari's extension repos use.
///
/// The format is deliberately ours (`index.json`), not Hikari's, so the app's
/// own community directory can serve it and the bundled pack can ship it.
class UniversalRepo {
  const UniversalRepo({required this.url, required this.configs});

  final String url;
  final List<UniversalConfig> configs;
}

/// Owns every installed universal scraper — the config-driven twin of
/// `MihonManager` / `AniyomiManager` / `MangayomiManager`.
///
/// Like every other engine manager it is an in-memory registry + a persisted
/// list, registered in DI, walked by `SourceRepository` for the source picker
/// and search fan-out. A universal source needs no runtime and no native
/// channel: it is pure Dart (`dio` + `html`), so it works on every platform
/// including iOS/tvOS where the APK-extension engines can't.
class UniversalManager extends ChangeNotifier {
  UniversalManager({required Dio dio}) : _dio = dio;

  static const String boxName = 'universal_scrapers';

  final Dio _dio;
  final Map<String, UniversalConfig> _configs = {};
  final Map<String, UniversalProvider> _providers = {};
  final List<String> _repositories = [];
  var _initialized = false;

  /// Bumped on every install/uninstall so `SourceRepository`'s
  /// change-detection rebuilds the source list.
  var revision = 0;

  Future<void> init() async {
    if (_initialized) return;
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely<dynamic>(boxName);
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        try {
          _configs['$key'] = UniversalConfig.fromJson(
            Map<String, dynamic>.from(raw),
          );
        } catch (e) {
          debugPrint('[universal] stored config "$key" invalid, dropping: $e');
        }
      }
    }
    _repositories.addAll(_readRepositories(box));
    _initialized = true;
  }

  List<String> _readRepositories(Box box) {
    final raw = box.get('__repos__');
    return raw is List ? raw.map((e) => e.toString()).toList() : const [];
  }

  List<UniversalConfig> get all => List.unmodifiable(_configs.values);
  List<String> get repositories => List.unmodifiable(_repositories);
  bool get isEmpty => _configs.isEmpty;

  UniversalProvider? get(String sourceId) {
    final id = sourceId.startsWith(UniversalProvider.idPrefix)
        ? sourceId.substring(UniversalProvider.idPrefix.length)
        : sourceId;
    final config = _configs[id];
    if (config == null) return null;
    return _providers.putIfAbsent(
      id,
      () => UniversalProvider(config: config, fetch: _fetch),
    );
  }

  UniversalConfig? configFor(String id) => _configs[id];

  /// The `dio`-backed fetch every provider shares — the one HTTP client the
  /// app already configures (timeouts + browser UA), so a universal source
  /// behaves like every other network call in the app.
  Future<String> _fetch(String url, {Map<String, String>? headers}) async {
    final res = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: headers,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    return res.data ?? '';
  }

  /// Fetch a repo, parse every source config, persist and register them.
  /// Returns the installed ids. A repo whose body is unreachable throws so
  /// the caller can report it; a single bad entry is skipped, not fatal.
  Future<List<String>> addRepository(String url) async {
    final configs = await _fetchRepo(url);
    return installAll(configs, repoUrl: url);
  }

  Future<List<UniversalConfig>> _fetchRepo(String url) async {
    final body = await _fetch(url);
    return parseRepoBody(body);
  }

  /// Parse a repo body into configs. Public + static so it is unit-testable
  /// without a network. Accepts:
  ///  * `{ "sources": [ {…config…}, … ] }`  (ours)
  ///  * `{ "plugins": [ {…config…}, … ] }`  (Hikari-shaped, tolerated)
  ///  * a bare `[ {…config…} ]`
  static List<UniversalConfig> parseRepoBody(String body) {
    final decoded = jsonDecode(body);
    final List raw = decoded is List
        ? decoded
        : (decoded is Map
              ? (decoded['sources'] ?? decoded['plugins'] ?? const [])
              : const []);
    final out = <UniversalConfig>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(UniversalConfig.fromJson(Map<String, dynamic>.from(e)));
      } catch (err) {
        debugPrint('[universal] skipping bad config: $err');
      }
    }
    return out;
  }

  /// Install a set of configs. Idempotent: an already-installed id is
  /// replaced (so an updated repo takes effect on the next boot).
  Future<List<String>> installAll(
    List<UniversalConfig> configs, {
    String repoUrl = '',
  }) async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely<dynamic>(boxName);
    final installed = <String>[];
    for (final config in configs) {
      _configs[config.id] = config;
      _providers.remove(config.id);
      await box.put(config.id, config.toJsonForStore());
      installed.add(config.id);
    }
    if (repoUrl.isNotEmpty && !_repositories.contains(repoUrl)) {
      _repositories.add(repoUrl);
      await box.put('__repos__', _repositories);
    }
    if (installed.isNotEmpty) {
      revision++;
      notifyListeners();
    }
    return installed;
  }

  /// Install the bundled default configs shipped in the APK, so a fresh install
  /// has working universal sources with nothing for the user to configure —
  /// the same zero-input contract as the JS provider pack. Reinstalled on every
  /// boot (the shipped copy is the source of truth) so an updated app version
  /// refreshes them. Idempotent; a parse failure leaves the installed set as-is.
  Future<List<String>> installBundled(String body) async {
    final configs = parseRepoBody(body);
    if (configs.isEmpty) return const [];
    return installAll(configs, repoUrl: 'bundled://universal');
  }

  Future<void> uninstall(String id) async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely<dynamic>(boxName);
    _configs.remove(id);
    _providers.remove(id);
    await box.delete(id);
    revision++;
    notifyListeners();
  }

  /// Restore a backup's configs without re-fetching their repos (a backup
  /// carries the config bodies themselves). Union-only: an already-installed
  /// id is left as-is so a restore never clobbers a newer local edit.
  Future<void> restore(
    List<UniversalConfig> configs, {
    List<String> repoUrls = const [],
  }) async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely<dynamic>(boxName);
    var changed = false;
    for (final config in configs) {
      if (_configs.containsKey(config.id)) continue;
      _configs[config.id] = config;
      _providers.remove(config.id);
      await box.put(config.id, config.toJsonForStore());
      changed = true;
    }
    for (final url in repoUrls) {
      if (url.isEmpty || _repositories.contains(url)) continue;
      _repositories.add(url);
      changed = true;
    }
    if (changed) {
      await box.put('__repos__', _repositories);
      revision++;
      notifyListeners();
    }
  }

  Future<void> removeRepository(String url) async {
    _repositories.remove(url);
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely<dynamic>(boxName);
    await box.put('__repos__', _repositories);
    notifyListeners();
  }
}
