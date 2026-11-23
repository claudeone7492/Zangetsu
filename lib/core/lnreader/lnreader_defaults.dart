import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'lnreader_extension_service.dart';

/// The actively maintained LNReader plugin index.
///
/// The repo publishes a built index plus one bundled `.js` per plugin, so the
/// app can install a source without cloning or transpiling the repository.
const String kDefaultLnReaderRepoUrl =
    'https://raw.githubusercontent.com/lnreader/lnreader-plugins/'
    'plugins/v3.0.0/.dist/plugins.min.json';

const String _seededKey = '__default_plugins_v1__';
const String _seededBox = 'lnreader_defaults';
const String _reposBox = 'lnreader_repos';

/// Installs every English plugin from [kDefaultLnReaderRepoUrl] that is not
/// already present. Returns how many were newly installed.
///
/// Runs once. A marker in the `lnreader_defaults` box means a second boot does
/// not re-download 200+ plugins; a partial failure leaves the marker unset so
/// the next boot retries only the missing ones.
Future<int> seedDefaultLnReaderPlugins(
  LnReaderExtensionService service, {
  String language = 'English',
  int concurrency = 4,
  bool force = false,
}) async {
  final repos = Hive.isBoxOpen(_reposBox) ? Hive.box<String>(_reposBox) : null;
  final marker = Hive.isBoxOpen(_seededBox)
      ? Hive.box<String>(_seededBox)
      : null;
  if (!force && marker?.get(_seededKey) == 'done') return 0;

  final List<LnReaderPluginMeta> index;
  try {
    index = await service.fetchIndex(kDefaultLnReaderRepoUrl);
  } catch (e) {
    debugPrint('[lnreader] default plugin index failed: $e');
    return 0;
  }
  final installed = service.installed().map((m) => m.id).toSet();
  final pending = index
      .where((m) => m.lang == language && !installed.contains(m.id))
      .toList();

  var added = 0;
  var failed = 0;
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= pending.length) return;
      try {
        await service.install(pending[i]);
        added++;
      } catch (e) {
        failed++;
        debugPrint('[lnreader] default plugin ${pending[i].id} failed: $e');
      }
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);

  if (repos != null) {
    await repos.put(kDefaultLnReaderRepoUrl, kDefaultLnReaderRepoUrl);
  }
  if (marker != null && failed == 0) await marker.put(_seededKey, 'done');
  debugPrint(
    '[lnreader] default plugins: $added installed, $failed failed, '
    '${pending.length} pending',
  );
  return added;
}
