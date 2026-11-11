import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:zangetsu_source_bridge/zangetsu_source_bridge.dart';

import '../mangayomi/mangayomi_source_id.dart';
import '../models/provider_info.dart';
import '../provider/provider_registry.dart';

/// The app-wide content mode. Anime is the default and covers the whole
/// existing video app (anime + movie sources); manga/novel are reading modes.
enum ContentMode { anime, manga, novel }

/// Content kind a source id belongs to, when it can be told from the id alone.
///
/// Two id families carry their type IN the id and need no lookup:
///   • Mangayomi's `mg:` keys encode the declared type (see
///     [mangayomiContentTypeOf]);
///   • Mihon/LNReader extensions use dedicated `mihon:`/`lnr:` prefixes
///     (spec Decision 1 — `ani:` is hardcoded video, so reusing it would type
///     every manga source as anime).
///
/// Everything else — the app's own JS providers (`mangakakalot`, `gutenberg`,
/// …), CloudStream (`cs:`), Aniyomi (`ani:`), Stremio — declares its type in a
/// manifest instead. [typeFromManifest] is that lookup, supplied by the caller
/// so this stays a pure function the mode cubit can call without a DI lookup.
typedef SourceTypeResolver = ProviderType? Function(String sourceId);

/// Whether [sourceId] belongs in [mode].
///
/// [typeFromManifest] resolves the manifest-declared type for ids that don't
/// encode it (the app's own JS providers). It is OPTIONAL: when null, such a
/// source is treated as video (anime), preserving the previous behaviour for
/// callers with no registry at hand (the pure-id unit tests). Pass a resolver
/// that reads [ProviderRegistry] to type the bundled manga/novel pack — without
/// it, `mangakakalot`/`gutenberg` resolve as anime and Manga/Novel mode wrongly
/// reports "no sources installed" on a fresh install.
bool sourceIdMatchesContentMode(
  String sourceId,
  ContentMode mode, {
  SourceTypeResolver? typeFromManifest,
}) {
  final mangayomiType = mangayomiContentTypeOf(sourceId);
  if (mangayomiType != null) {
    return switch (mode) {
      ContentMode.anime => mangayomiType == MangayomiContentType.video,
      ContentMode.manga => mangayomiType == MangayomiContentType.manga,
      ContentMode.novel => mangayomiType == MangayomiContentType.novel,
    };
  }
  // Prefix-encoded reading types first, so the mode cubit's cheap id-only check
  // stays correct even when no resolver is passed.
  if (sourceId.startsWith('mihon:')) return mode == ContentMode.manga;
  if (sourceId.startsWith('lnr:')) return mode == ContentMode.novel;
  final declared = typeFromManifest?.call(sourceId);
  if (declared != null) return mode.matchesProvider(declared);
  // Unknown id, no resolver: video. `cs:`/`ani:`/Stremio/`zm` are all video by
  // construction, so this is correct for every remaining real id.
  return mode == ContentMode.anime;
}

/// [sourceIdMatchesContentMode] with the manifest resolver already wired to the
/// live [ProviderRegistry]. The one to call from app code — it is what lets the
/// bundled `mangakakalot`/`gutenberg` pack (plain JS ids, no reading prefix)
/// land in Manga/Novel mode instead of falling back to anime.
///
/// Falls back to id-only classification when the registry isn't registered yet
/// (early boot, minimal test harnesses) rather than throwing, so a "no sources"
/// guide never flashes over a home that would otherwise show content.
///
/// For a LOOP over many ids build [manifestSourceTypes] once and use
/// [sourceInMode] instead: each manifest lookup deserializes the repo manifests,
/// so resolving per row is O(rows) deserializes.
bool sourceMatchesContentMode(String sourceId, ContentMode mode) =>
    sourceIdMatchesContentMode(
      sourceId,
      mode,
      typeFromManifest: manifestTypeResolver(),
    );

/// The [SourceTypeResolver] backed by the live [ProviderRegistry], or null when
/// the registry isn't registered yet (early boot, minimal test harnesses).
SourceTypeResolver? manifestTypeResolver() {
  if (!GetIt.I.isRegistered<ProviderRegistry>()) return null;
  final types = manifestSourceTypes();
  return (id) => types[id];
}

/// The manifest-declared [ProviderType] of every source the live registry
/// knows, built in ONE manifest pass. Empty when the registry isn't registered
/// yet. Loop callers build this once and pass it to [sourceInMode] so a whole
/// pass costs one deserialize rather than one per row.
Map<String, ProviderType> manifestSourceTypes() {
  if (!GetIt.I.isRegistered<ProviderRegistry>()) {
    return const <String, ProviderType>{};
  }
  final byName = ProviderType.values.asNameMap();
  final out = <String, ProviderType>{};
  for (final e in GetIt.I<ProviderRegistry>().typeMapOf().entries) {
    final t = byName[e.value];
    if (t != null) out[e.key] = t;
  }
  return out;
}

/// [sourceMatchesContentMode] against a prebuilt [types] map (see
/// [manifestSourceTypes]) — the loop-friendly form.
bool sourceInMode(
  String sourceId,
  ContentMode mode,
  Map<String, ProviderType> types,
) => sourceIdMatchesContentMode(sourceId, mode, typeFromManifest: (id) => types[id]);

extension ContentModeX on ContentMode {
  String get label => switch (this) {
    // "Streaming", not "Anime": this mode covers all video — anime, movies and
    // series — so the switcher/history read "Streaming" rather than the narrower
    // "Anime". (The enum value stays `anime` — only the user-facing label moved.)
    ContentMode.anime => 'Streaming',
    ContentMode.manga => 'Manga',
    ContentMode.novel => 'Novel',
  };

  IconData get icon => switch (this) {
    ContentMode.anime => Icons.play_circle_outline_rounded,
    ContentMode.manga => Icons.auto_stories_outlined,
    ContentMode.novel => Icons.menu_book_outlined,
  };

  bool get isReading => this != ContentMode.anime;

  /// Which provider types belong to this mode. Anime mode keeps both video
  /// types so today's mixed anime/movie source list is unchanged.
  bool matchesProvider(ProviderType t) => switch (this) {
    ContentMode.anime => t == ProviderType.anime || t == ProviderType.movie,
    ContentMode.manga => t == ProviderType.manga,
    ContentMode.novel => t == ProviderType.novel,
  };
}

/// Filters a source map to the entries visible in [mode]. In anime mode this
/// is a no-op over an anime/movie-only source set — the hard requirement that
/// today's anime-mode source list never changes.
Map<String, T> filterSourcesForMode<T>(
  Map<String, T> sources,
  ContentMode mode,
  ProviderType Function(T) typeOf,
) => Map.fromEntries(
  sources.entries.where((e) => mode.matchesProvider(typeOf(e.value))),
);
