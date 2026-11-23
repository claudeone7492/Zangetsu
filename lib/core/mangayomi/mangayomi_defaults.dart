import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

import 'mangayomi_manager.dart';

/// Mangayomi-format repositories seeded on first launch, so the Anymex plugin
/// catalogue (Kegareta Sauces: one index for manga, one for anime) is browsable
/// with nothing for the user to paste — the same zero-input contract as the JS
/// pack families' defaults.
///
/// They stay ordinary Mangayomi repositories: the bridge already speaks their
/// manifest shape and both code languages, so their sources install as `mg:`
/// and reach every existing path (routing, settings, updates, backup). A
/// separate `amx:` prefix would only fork that routing for no gain.
///
/// A repo that is unreachable is skipped, never fatal to boot: an empty
/// catalogue is a cosmetic loss, a boot failure is not.
const List<String> kDefaultMangayomiRepoUrls = [
  // Manga (272 sources, Dart + JS).
  'https://raw.githubusercontent.com/gato404/kegareta-sauces/main/index.json',
  // Anime (JS).
  'https://raw.githubusercontent.com/gato404/kegareta-sauces/main/anime_index.json',
  // Actively maintained upstream catalogue (335 sources). Carries the fixed
  // MangaHere implementation that the bundled JS provider no longer matches.
  'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json',
];

const String _seededBox = 'mangayomi_defaults';
const String _seededKey = '__default_sources_v1__';

/// Register every default repo [manager] doesn't already track.
///
/// Idempotent across boots and per-repo resilient. Returns how many repos were
/// newly added. Never throws.
Future<int> seedDefaultMangayomiRepos(MangayomiManager manager) async {
  var added = 0;
  final known = manager.repositories.map((u) => u.toString()).toSet();
  for (final raw in kDefaultMangayomiRepoUrls) {
    if (known.contains(raw)) continue;
    try {
      await manager.addRepository(Uri.parse(raw));
      added++;
    } catch (e) {
      debugPrint('[boot] mangayomi default repo failed ($raw): $e');
    }
  }
  return added;
}

/// Installs the English manga/novel sources from the default catalogues.
///
/// This is the zero-input twin of [seedDefaultMangayomiRepos]: a repo entry is
/// only a catalogue row until it is installed, and the bundled JS pack cannot
/// be fixed for a site that changed its markup. The upstream catalogue is
/// maintained, so installing its English entries gives the app working
/// replacements without porting selectors by hand.
///
/// Runs once (marker in `mangayomi_defaults`); partial failures leave the
/// marker unset so the next boot retries only the missing sources.
Future<int> provisionDefaultMangayomiSources(
  MangayomiManager manager, {
  String language = 'en',
  Set<MangayomiContentType> types = const {
    MangayomiContentType.manga,
    MangayomiContentType.novel,
  },
  int concurrency = 1,
  bool force = false,
}) async {
  final box = Hive.isBoxOpen(_seededBox) ? Hive.box<String>(_seededBox) : null;
  if (!force && box?.get(_seededKey) == 'done') return 0;

  final installed = manager.installed.map((i) => i.source.key).toSet();
  final pending = <MangayomiSource>[];
  var repoFailures = 0;
  for (final raw in kDefaultMangayomiRepoUrls) {
    final tracked = manager.repositories.any((u) => u.toString() == raw);
    if (!tracked) {
      repoFailures++;
      continue;
    }
    final url = Uri.parse(raw);
    var catalogue = manager.catalogueFor(url);
    if (catalogue.isEmpty) {
      try {
        catalogue = await manager.refreshRepository(url);
      } catch (e) {
        repoFailures++;
        debugPrint('[boot] mangayomi catalogue failed ($url): $e');
        continue;
      }
    }
    for (final source in catalogue) {
      if (source.language.toLowerCase() != language) continue;
      if (!types.contains(source.contentType)) continue;
      if (installed.contains(source.key)) continue;
      if (pending.any((s) => s.key == source.key)) continue;
      pending.add(source);
    }
  }

  var added = 0;
  var failed = 0;
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= pending.length) return;
      try {
        await manager.install(pending[i]);
        added++;
      } catch (e) {
        failed++;
        debugPrint('[boot] mangayomi install ${pending[i].name} failed: $e');
      }
    }
  }

  await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);

  if (box != null && failed == 0 && repoFailures == 0) {
    await box.put(_seededKey, 'done');
  }
  debugPrint(
    '[boot] mangayomi default sources: $added installed, $failed failed, '
    '${pending.length} pending, $repoFailures repo failure(s)',
  );
  return added;
}
