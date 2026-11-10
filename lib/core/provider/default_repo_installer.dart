import 'package:flutter/foundation.dart';

import '../app_config.dart';
import 'provider_registry.dart';
import 'provider_repo_registry.dart';

/// Outcome of a first-run provisioning pass over [kDefaultRepoUrls].
class ProvisionResult {
  const ProvisionResult({required this.installedIds, required this.repoCount});

  /// Source ids installed, in install order, across every repo that answered.
  final List<String> installedIds;

  /// How many of the default repos produced at least one installed source.
  final int repoCount;

  bool get isEmpty => installedIds.isEmpty;
}

/// Fetches every repo in [kDefaultRepoUrls] and installs all of its sources.
///
/// Each repo installs independently: a repo whose manifest is unreachable, or a
/// single source that fails to download/load, is skipped so the rest still land.
/// [onStatus] reports progress for the onboarding UI. Throws only when NOTHING
/// could be installed at all, so the caller can surface a retry.
Future<ProvisionResult> provisionDefaultRepos({
  required ProviderReposRegistry repos,
  required ProviderRegistry registry,
  required void Function(String name, int done, int total) onStatus,
}) async {
  final installedIds = <String>[];
  var reposWithSources = 0;

  for (final repoUrl in kDefaultRepoUrls) {
    ProviderRepo repo;
    try {
      repo = await repos.fetchAndCache(repoUrl);
    } catch (e) {
      debugPrint('[provision] repo unreachable, skipping: $repoUrl ($e)');
      continue;
    }

    final total = repo.sources.length;
    var installedHere = 0;
    for (final s in repo.sources) {
      onStatus(s.name, installedHere + 1, total);
      try {
        await registry.install(
          sourceId: s.id,
          fileUrl: repos.resolveFileUrl(repo, s),
          repoUrl: repo.url,
          displayName: s.name,
          version: s.version,
          logoUrl: ProviderReposRegistry.resolveLogoUrl(repo, s) ?? '',
          force: true,
        );
        installedHere++;
        if (!installedIds.contains(s.id)) installedIds.add(s.id);
      } catch (e) {
        debugPrint('[provision] source failed, skipping: ${s.id} ($e)');
      }
    }
    if (installedHere > 0) reposWithSources++;
  }

  if (installedIds.isEmpty) {
    throw Exception('No sources could be installed');
  }
  return ProvisionResult(
    installedIds: installedIds,
    repoCount: reposWithSources,
  );
}
