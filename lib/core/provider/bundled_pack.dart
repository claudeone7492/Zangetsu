import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'provider_registry.dart';
import 'provider_repo_registry.dart';

/// The default source pack, shipped INSIDE the app.
///
/// Sources used to be fetched from a manifest on the `main` branch at first
/// launch, which made a fresh install depend on a network fetch of a file that
/// had to exist on the right branch. It didn't, so provisioning installed
/// nothing and playback swept stale, dead sources ("not available, try
/// again later"). Bundling the pack removes that dependency entirely: every
/// source is present the moment the app installs, with nothing for the user to
/// configure.
///
/// The same `.js` files stay published in `provider-repo/` so the community
/// directory can still serve them; the asset copies are the source of truth
/// for what a new install runs.
const String kBundledPackRepoUrl = 'bundled://official-pack';
const String kBundledPackManifestAsset = 'assets/providers/manifest.json';
const String kBundledPackAssetBase = 'assets/providers/';

/// Installs every source in the bundled pack into [registry] (loading each
/// into the JS runtime) and caches the pack manifest in [repos] so the source
/// picker can show names, logos, types and the NSFW flag.
///
/// Idempotent: called on every launch, it re-seeds the in-memory JS (which
/// [ProviderRegistry.loadAll] needs) and upserts the persisted entries, so a
/// build that adds or drops a source takes effect on the next boot. A single
/// source that fails to load is skipped rather than sinking the rest.
Future<List<String>> installBundledPack({
  required ProviderRegistry registry,
  required ProviderReposRegistry repos,
}) async {
  final manifestBody = await rootBundle.loadString(kBundledPackManifestAsset);
  final repo = ProviderReposRegistry.parseManifest(
    kBundledPackRepoUrl,
    manifestBody,
  );
  await repos.cacheManifest(repo);

  // A device that installed one of these ids from a community repo (before it
  // shipped in the pack) has two entries for the same sourceId, and the JS
  // runtime holds only one slot — the repo copy, loaded last, used to win and
  // the app ran stale, dead JS. Drop those duplicates so the pack is what
  // actually runs.
  await registry.pruneSupersededByPack([for (final s in repo.sources) s.id]);

  final installed = <String>[];
  for (final s in repo.sources) {
    try {
      final jsSource = await rootBundle.loadString(
        '$kBundledPackAssetBase${s.file}',
      );
      await registry.installFromBundled(
        name: s.id,
        jsSource: jsSource,
        displayName: s.name,
        repoUrl: kBundledPackRepoUrl,
        version: s.version,
        logoUrl: ProviderReposRegistry.resolveLogoUrl(repo, s) ?? '',
        load: false,
      );
      installed.add(s.id);
    } catch (e) {
      debugPrint('[bundled-pack] source failed, skipping: ${s.id} ($e)');
    }
  }
  debugPrint(
    '[bundled-pack] installed ${installed.length}/${repo.sources.length} '
    'sources',
  );
  return installed;
}
