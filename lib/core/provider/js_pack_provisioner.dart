import 'package:flutter/foundation.dart';

import 'js_pack_engine.dart';
import 'js_pack_manager.dart';

/// Default plugin repos per family, installed on first launch and re-seeded on
/// every boot so a fresh install already has these sources with nothing for the
/// user to paste — the same zero-input contract as [kDefaultRepoUrls] and the
/// bundled provider pack.
///
/// An entry may be unreachable (an upstream repo gets renamed or deleted); the
/// provisioner skips it and installs the rest. A family with an empty list
/// simply has no default — it stays available through the Extensions hub.
const Map<JsPackEngine, List<String>> kDefaultPackRepoUrls = {
  JsPackEngine.nuvio: [
    'https://raw.githubusercontent.com/tapframe/nuvio-providers/main/index.json',
    'https://raw.githubusercontent.com/Gowaru/nuvio-providers/main/index.json',
  ],
  JsPackEngine.vega: [
    'https://raw.githubusercontent.com/Zenda-Cross/vega-providers/main/manifest.json',
    'https://raw.githubusercontent.com/DHR-Store/vega-providers/main/manifest.json',
  ],
  JsPackEngine.sora: [
    'https://raw.githubusercontent.com/xdfkenny/Sora-Modules/main/index.json',
    'https://raw.githubusercontent.com/justbbcr/streamex/main/index.json',
    'https://raw.githubusercontent.com/CPRmichel/sora-movie2k-module/main/index.json',
  ],
  JsPackEngine.skystream: [
    'https://raw.githubusercontent.com/akashdh11/skystream-plugins/main/index.json',
  ],
  JsPackEngine.hiki: [
    'https://raw.githubusercontent.com/codegeasse1/hikari-extensions/main/index.json',
  ],
  JsPackEngine.kotatsu: [
    'https://raw.githubusercontent.com/KotatsuApp/kotatsu-parsers/main/index.json',
  ],
};

/// Outcome of one family's provisioning pass.
class PackProvisionResult {
  const PackProvisionResult({
    required this.engine,
    required this.installedIds,
    required this.repoCount,
  });

  final JsPackEngine engine;
  final List<String> installedIds;
  final int repoCount;

  bool get isEmpty => installedIds.isEmpty;
}

/// Install every default repo for [engine] into [manager].
///
/// Idempotent and per-repo resilient: a repo that is unreachable or a module
/// that won't fetch is skipped so the rest still land. Never throws — a family
/// with no reachable default is a family with no sources, not a boot failure.
Future<PackProvisionResult> provisionPackDefaults({
  required JsPackManager manager,
  List<String>? repoUrls,
}) async {
  final urls = repoUrls ?? kDefaultPackRepoUrls[manager.engine] ?? const [];
  final installed = <String>[];
  var reposWithSources = 0;

  for (final url in urls) {
    try {
      final ids = await manager.addRepository(url);
      if (ids.isEmpty) continue;
      reposWithSources++;
      for (final id in ids) {
        if (!installed.contains(id)) installed.add(id);
      }
    } catch (e) {
      debugPrint('[${manager.engine.prefix}] repo unreachable, skipping: $url ($e)');
    }
  }

  return PackProvisionResult(
    engine: manager.engine,
    installedIds: installed,
    repoCount: reposWithSources,
  );
}
