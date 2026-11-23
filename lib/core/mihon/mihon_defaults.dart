import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../aniyomi/aniyomi_repo.dart';
import 'mihon_extension_service.dart';
import 'mihon_manager.dart';
import 'mihon_repo.dart';

/// The actively maintained Mihon/Tachiyomi extension repo.
const String kDefaultMihonRepoUrl =
    'https://raw.githubusercontent.com/keiyoushi/extensions/repo';

/// Bundled manga providers whose sites changed enough that the in-tree JS
/// provider no longer finds results. These package names are the maintained
/// replacements in [kDefaultMihonRepoUrl].
const Set<String> kDefaultMihonPackages = {
  'eu.kanade.tachiyomi.extension.en.mangapandaonl',
  'eu.kanade.tachiyomi.extension.en.mangafox',
  'eu.kanade.tachiyomi.extension.en.mangahere',
  'eu.kanade.tachiyomi.extension.en.mangafoxfun',
  'eu.kanade.tachiyomi.extension.en.mangahereonl',
};

const String _seededBox = 'mihon_defaults';
const String _seededKey = '__default_extensions_v1__';
const String _reposBox = 'mihon_repos';

/// Adds [kDefaultMihonRepoUrl] to the repo list and installs the maintained
/// packages in [kDefaultMihonPackages] that aren't already on disk.
///
/// Runs once (marker in `mihon_defaults`). Failures leave the marker unset, so
/// the next boot retries only what is still missing. Never throws: the caller
/// is a boot microtask.
Future<int> seedDefaultMihonExtensions({
  MihonManager? manager,
  MihonExtensionService? service,
  Set<String> packages = kDefaultMihonPackages,
  bool force = false,
}) async {
  final repos = Hive.isBoxOpen(_reposBox) ? Hive.box<String>(_reposBox) : null;
  if (repos != null && !repos.values.contains(kDefaultMihonRepoUrl)) {
    await repos.put(kDefaultMihonRepoUrl, kDefaultMihonRepoUrl);
  }

  final marker = Hive.isBoxOpen(_seededBox)
      ? Hive.box<String>(_seededBox)
      : null;
  if (!force && marker?.get(_seededKey) == 'done') return 0;

  final installed = Hive.isBoxOpen(MihonExtensionService.installedBoxName)
      ? Hive.box<dynamic>(
          MihonExtensionService.installedBoxName,
        ).keys.cast<String>().toSet()
      : <String>{};

  final List<AniyomiRepoEntry> entries;
  try {
    entries = await MihonRepo.fetchIndex(kDefaultMihonRepoUrl);
  } catch (e) {
    debugPrint('[mihon] default repo index failed: $e');
    return 0;
  }
  final byPkg = {for (final e in entries) e.pkg: e};
  final pending = [
    for (final pkg in packages)
      if (!installed.contains(pkg) && byPkg[pkg] != null) byPkg[pkg]!,
  ];
  final missing = packages.where((p) => byPkg[p] == null).length;

  var added = 0;
  var failed = 0;
  final svc = service ?? MihonExtensionService();
  for (final entry in pending) {
    try {
      final providers = await svc.installFromRepo(entry, manager: manager);
      if (providers.isEmpty) {
        failed++;
      } else {
        added++;
      }
    } catch (e) {
      failed++;
      debugPrint('[mihon] default extension ${entry.pkg} failed: $e');
    }
  }

  if (marker != null && failed == 0) await marker.put(_seededKey, 'done');
  debugPrint(
    '[mihon] default extensions: $added installed, $failed failed, '
    '${pending.length} pending, $missing absent from repo',
  );
  return added;
}
