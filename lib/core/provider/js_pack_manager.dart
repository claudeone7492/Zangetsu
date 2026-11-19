import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import '../models/episode.dart';
import '../models/home_section.dart';
import '../models/media_detail.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../models/video_source.dart';
import 'base_provider.dart';
import 'js_pack_engine.dart';
import 'js_pack_module.dart';
import 'provider_manager.dart';

/// Owns every installed JS plugin-pack source for ONE family (`nuvio:`,
/// `vega:`, `sora:`, `sky:`, `hiki:`, `kot:`).
///
/// The six families are the same thing — a repo of JS modules, each module a
/// source — so they share this manager rather than each re-implementing
/// install/persist/route. What differs per family is the repo index shape and
/// the module's export dialect; both are absorbed by [JsPackModule.parseRepo]
/// and `wrapJsPackModule`, so this class stays family-agnostic.
///
/// Sources run on the app's shared QuickJS host ([ProviderManager]) under their
/// full prefixed id (`nuvio:tmdb`), so the Cloudflare bridge, call scheduler,
/// settings push and health tracking all apply with no extra work.
class JsPackManager extends ChangeNotifier {
  JsPackManager({required this.engine, required ProviderManager runtime})
    : _runtime = runtime;

  final JsPackEngine engine;
  final ProviderManager _runtime;
  final Dio _dio = Dio();

  final Map<String, JsPackModule> _modules = {};
  final List<String> _repositories = [];
  var _initialized = false;

  /// Bumped on every install/uninstall so `SourceRepository`'s change
  /// detection rebuilds the source list.
  var revision = 0;

  Future<void> init() async {
    if (_initialized) return;
    final box = Hive.isBoxOpen(engine.box)
        ? Hive.box(engine.box)
        : await openBoxSafely<dynamic>(engine.box);
    for (final key in box.keys) {
      if (key == '__repos__') continue;
      final raw = box.get(key);
      if (raw is Map) {
        try {
          _modules['$key'] = JsPackModule.fromJson(
            Map<String, dynamic>.from(raw),
          );
        } catch (e) {
          debugPrint('[${engine.prefix}] stored module "$key" invalid: $e');
        }
      }
    }
    final repos = box.get('__repos__');
    if (repos is List) _repositories.addAll(repos.map((e) => e.toString()));
    _initialized = true;
  }

  List<JsPackModule> get all => List.unmodifiable(_modules.values);
  List<String> get repositories => List.unmodifiable(_repositories);
  bool get isEmpty => _modules.isEmpty;

  JsPackModule? moduleFor(String sourceId) =>
      _modules[engine.moduleIdOf(sourceId)];

  /// A live provider for [sourceId] — the [JsProvider] the shared host
  /// registered when the module was loaded.
  JsProvider? providerFor(String sourceId) =>
      _runtime.get('${engine.prefix}${engine.moduleIdOf(sourceId)}');

  /// Ensures [sourceId]'s module is loaded into the runtime, installing it
  /// from its persisted code (or fetching it once) if this boot hasn't yet.
  Future<JsProvider?> ensureLoaded(String sourceId) async {
    final mod = moduleFor(sourceId);
    if (mod == null) return null;
    final runtimeId = mod.sourceId;
    final existing = _runtime.get(runtimeId);
    if (existing != null) return existing;
    var code = mod.code;
    if (code.isEmpty) {
      try {
        code = await _fetch(mod.file);
      } catch (e) {
        debugPrint('[${engine.prefix}] module fetch failed ${mod.id}: $e');
        return null;
      }
      await _persist(mod.copyWith(code: code));
    }
    try {
      return await _runtime.load(
        sourceId: runtimeId,
        jsSource: code,
        originRepoUrl: mod.repoUrl,
        displayName: mod.name,
      );
    } catch (e) {
      debugPrint('[${engine.prefix}] module load failed ${mod.id}: $e');
      return null;
    }
  }

  /// Install a repo: parse its index, fetch each module's code, persist both.
  /// A repo that fails to fetch throws; a single bad module is skipped.
  Future<List<String>> addRepository(String url) async {
    final body = await _fetch(url);
    final modules = JsPackModule.parseRepo(
      body,
      engine: engine,
      repoUrl: url,
    );
    return installAll(modules, repoUrl: url);
  }

  /// Install parsed modules, fetching any that carry only a [JsPackModule.file].
  /// Idempotent: an already-installed id is replaced so an updated repo takes
  /// effect on the next boot.
  Future<List<String>> installAll(
    List<JsPackModule> modules, {
    String repoUrl = '',
  }) async {
    final installed = <String>[];
    for (final mod in modules) {
      var ready = mod;
      if (ready.code.isEmpty) {
        try {
          ready = ready.copyWith(code: await _fetch(ready.file));
        } catch (e) {
          debugPrint('[${engine.prefix}] skip ${mod.id} (fetch failed: $e)');
          continue;
        }
      }
      await _persist(ready);
      // Load it now so the source is usable without waiting for a first tap.
      await ensureLoaded(ready.sourceId);
      installed.add(ready.id);
    }
    if (repoUrl.isNotEmpty && !_repositories.contains(repoUrl)) {
      _repositories.add(repoUrl);
      final box = await _box();
      await box.put('__repos__', _repositories);
    }
    if (installed.isNotEmpty) {
      revision++;
      notifyListeners();
    }
    return installed;
  }

  /// Restore a backup's modules without re-fetching their repos. Union-only so
  /// a restore never clobbers a newer local install.
  Future<void> restore(
    List<JsPackModule> modules, {
    List<String> repoUrls = const [],
  }) async {
    var changed = false;
    for (final mod in modules) {
      if (_modules.containsKey(mod.id)) continue;
      await _persist(mod);
      changed = true;
    }
    for (final url in repoUrls) {
      if (url.isEmpty || _repositories.contains(url)) continue;
      _repositories.add(url);
      changed = true;
    }
    if (changed) {
      final box = await _box();
      await box.put('__repos__', _repositories);
      revision++;
      notifyListeners();
    }
  }

  Future<void> uninstall(String sourceId) async {
    final id = engine.moduleIdOf(sourceId);
    final mod = _modules.remove(id);
    if (mod != null) _runtime.remove(mod.sourceId);
    final box = await _box();
    await box.delete(id);
    revision++;
    notifyListeners();
  }

  Future<void> removeRepository(String url) async {
    _repositories.remove(url);
    final box = await _box();
    await box.put('__repos__', _repositories);
    notifyListeners();
  }

  Future<void> _persist(JsPackModule mod) async {
    _modules[mod.id] = mod;
    final box = await _box();
    await box.put(mod.id, mod.toJson());
  }

  Future<Box> _box() async => Hive.isBoxOpen(engine.box)
      ? Hive.box(engine.box)
      : await openBoxSafely<dynamic>(engine.box);

  Future<String> _fetch(String url) async {
    if (url.isEmpty) throw ArgumentError('empty url');
    final res = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    return res.data ?? '';
  }
}

/// One installed pack module, presented to `SourceRepository` as an ordinary
/// provider. Delegates every call to the [JsProvider] the shared runtime
/// registered, so this is a thin naming/typing layer, not a second runtime.
class JsPackProvider implements BaseProvider {
  JsPackProvider({required this.module, required this.delegate});

  final JsPackModule module;
  final JsProvider delegate;

  @override
  String get sourceId => module.sourceId;

  @override
  String get displayName => module.name;

  ProviderType get providerType => module.providerType;

  @override
  Future<ProviderInfo> getInfo() async {
    try {
      return await delegate.getInfo();
    } catch (_) {
      // A module with no getInfo still needs a usable label in the picker.
      return ProviderInfo(
        name: module.name,
        lang: module.lang,
        baseUrl: module.baseUrl,
        logo: module.logo.isEmpty ? null : module.logo,
        type: module.providerType,
        version: module.version,
      );
    }
  }

  @override
  Future<List<HomeSection>?> getHome({String category = 'sub'}) =>
      delegate.getHome(category: category);

  @override
  Future<List<MediaItem>> popular({
    String category = 'sub',
    int dateRange = 7,
    int page = 1,
  }) => delegate.popular(category: category, dateRange: dateRange, page: page);

  @override
  Future<List<MediaItem>> search(
    String query,
    int page, {
    String category = '',
  }) => delegate.search(query, page, category: category);

  @override
  Future<MediaDetail> getDetail(String url, {String category = 'sub'}) =>
      delegate.getDetail(url, category: category);

  @override
  Future<List<Episode>> getEpisodes(String url, {String category = 'sub'}) =>
      delegate.getEpisodes(url, category: category);

  @override
  Future<List<VideoSource>> getVideoSources(
    String episodeUrl, {
    bool fast = false,
  }) => delegate.getVideoSources(episodeUrl, fast: fast);
}
