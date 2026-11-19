import 'package:flutter/foundation.dart';

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
];

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
