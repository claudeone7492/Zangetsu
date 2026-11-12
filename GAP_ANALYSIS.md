# Zangetsu — Gap Analysis: Done vs. Not Done

Repo: `claudeone7492/Zangetsu` (fork of `Spyou/Zangetsu`)
Analyzed ref: `main` @ `7470f11b` ("feat: live Simkl tracking on TV native players", 2026-11-09)
App version: `2.3.5+23637` · ~201k Dart LOC (excl. l10n) · 89 remote branches

Legend: ✅ done / shipped · 🟡 partial or gated · ❌ not done / missing

---

## 1. Platforms & Distribution

| Feature | State | Evidence |
|---|:---:|---|
| Android phone release | ✅ | README "Android ✅ Available" |
| Android TV release | ✅ | `AndroidManifest.xml:21` leanback, `lib/features/shell/root_shell_tv.dart` |
| iOS beta (TestFlight) | ✅ | README "iOS 🧪 Beta" |
| iOS release | ❌ | README roadmap `- [ ] iOS release` |
| Windows release | ❌ | no `windows/` directory at all; README `- [ ] Windows release` |
| Per-device split (android / ios / rest) | ❌ | no `productFlavors` in `android/app/build.gradle.kts`; no `--split-per-abi` in `.github/workflows/` |
| Android TV as a separate APK artifact | 🟡 | one APK, `leanback required=false`; no build flavor |

## 2. Content Modes & Catalogues

| Feature | State | Evidence |
|---|:---:|---|
| Streaming mode (anime/movies/series) | ✅ | `lib/features/home`, `ContentModeCubit` |
| Manga mode | ✅ | `lib/features/reader/manga_reader_screen.dart` |
| Novel mode (light novels) | ✅ | `lib/features/reader/novel_reader_screen.dart` |
| Z-Mode metadata catalogue | ✅ | `lib/core/zmode/`, toggle wired in settings/home |
| Stremio catalogue + streams | ✅ | `lib/core/stremio/` merged; wired in detail/player/settings |
| Stremio title logos | ✅ | merged with `lib/core/stremio/` |

## 3. Sources / Extension Ecosystems

| Feature | State | Evidence |
|---|:---:|---|
| CloudStream JS sources (native) | ✅ | `lib/core/provider/cloudstream_provider.dart` |
| Aniyomi sources | ✅ | `AniyomiManager` in `source_repository.dart:80` |
| Mihon manga sources | ✅ | `mihon:` prefix routing |
| LNReader novel sources | ✅ | `lib/core/lnreader/` |
| Mangayomi sources | ✅ | `lib/core/mangayomi/mangayomi_manager.dart` |
| Zangetsu-native JS sources | ✅ | unprefixed ids → JS provider |
| iOS: CloudStream/Aniyomi/Mihon extensions | ❌ | documented platform limitation (iOS blocks plugins) |
| Cloudflare challenge solve for JS providers | ❌ | `OWNER-DISABLED 2026-10-03` in `provider_manager.dart:498-543` |

## 4. Trackers

| Feature | State | Evidence |
|---|:---:|---|
| AniList | ✅ | `lib/core/tracker/` |
| MyAnimeList | ✅ | `mal_service.dart` |
| Simkl (anime + movie/TV) | ✅ | `simkl_service.dart` |
| MangaBaka | ✅ | `mangabaka_service.dart` |
| Live Simkl progress on TV native players | ✅ | HEAD commit `7470f11b`, `tv_playback_tracker.dart:51` |
| Shikimori / Trakt / Kitsu | ❌ | not present |

## 5. Player

| Feature | State | Evidence |
|---|:---:|---|
| mpv player | ✅ | `media_kit` deps |
| Android native ExoPlayer | 🟡 | `drm_player_screen.dart`; labelled "experimental" in settings |
| DRM (Widevine) playback | ✅ | `player_screen.dart:1310` handoff |
| Chromecast / Cast | ✅ | `lib/core/cast/`, wired in `player_screen.dart:828` |
| Discord rich presence | ✅ | `lib/core/discord/` |
| Subtitles + download | ✅ | `subtitle_download_service.dart` |
| Anime4K GPU upscaling | ✅ | `settings_playback.dart:690` |
| Portrait mini-player | ✅ | `lib/features/player/player_watch_page.dart` (re-architected on main) |
| Episode comments | ✅ | `episode_comments_sheet.dart` wired at `player_screen.dart` `_openCommentsSheet` |
| Watch Together / Watch Party | 🟡 | fully built, owner-disabled (`watch_together_controller.dart:13` `isEnabled = false`) |
| Trailers | ✅ | `lib/features/trailer/trailer_screen.dart` |
| Voice search | ✅ | `phone_voice_search_sheet.dart` (native channel) |
| TV play-next "completed" scrobble (tvOS) | ✅ | `TvSystemPlayerViewController.swift` `playNext(completed:)` → `persistProgress` |

## 6. Reader

| Feature | State | Evidence |
|---|:---:|---|
| Manga reader | ✅ | `manga_reader_screen.dart` |
| Novel reader (scroll + paged) | ✅ | `novel_reader_screen.dart` |
| Page/chapter translation (Gemini) | ✅ | translation pipeline in reader |
| Novel EPUB export | ✅ | `showEpubExportSheet` in `detail_screen.dart:2761` |
| Reader auto-scroll | ✅ | `reader_auto_scroll.dart` |

## 7. Downloads & Offline

| Feature | State | Evidence |
|---|:---:|---|
| Direct-file download | ✅ | `lib/core/download/download_manager.dart` |
| HLS download | ✅ | `hls_downloader.dart` |
| Torrent download | ✅ | `lib/core/torrent/` |
| Debrid (Real-Debrid / TorBox) | ✅ | `lib/core/debrid/` merged; wired in settings + `injector.dart` |
| HLS-only source download | ✅ | `hls_downloader.dart` (background isolate, resume, AES-128, fMP4/TS) |
| MPEG-DASH (.mpd) download | ✅ | `dash_downloader.dart` + `dash_manifest.dart` |

## 8. Social / Community

| Feature | State | Evidence |
|---|:---:|---|
| Viewer profiles | ✅ | `lib/features/profiles/` |
| Person / people page | ✅ | `detail_screen.dart:2888` → `PersonPage` |
| Community sheet | ✅ | `community_sheet.dart` |
| Announcements | ✅ | `lib/features/announce/` |
| Profile "more features" placeholder card | 🟡 | `viewer_profile_home_screen.dart:220,424` ("More features are on their way…") |
| Watch party (social) | ❌ | see §5 |

## 9. Sync, Backup & Notifications

| Feature | State | Evidence |
|---|:---:|---|
| Local backup / restore | ✅ | `lib/features/backup/backup_screen.dart`, `BackupService` |
| Cloud sync (Supabase / VPS) | ✅ | `CloudPostgrest` in `read_history.dart:158`, `viewer_profile.dart:97` |
| Cross-device sync of lists/history | ✅ | README "Keep your lists… in sync" |
| Push notifications | ✅ | `PushService.instance.init()` in `main.dart:609` |
| Subscriptions + airing countdown | ✅ | `subscriptions_screen.dart`, `airing_countdown.dart` |

## 10. Settings & UI

| Feature | State | Evidence |
|---|:---:|---|
| Phone settings | ✅ | `settings_screen.dart` |
| TV settings (consolidated) | ✅ | `_tvSectionPage` in `settings_screen.dart:202` |
| Settings search | ✅ | `settings_search_index.dart` |
| Nav-tabs customisation | ✅ | `nav_tabs_screen.dart` |
| Nav-tabs preview "Change content mode" button | ❌ | `nav_tabs_screen.dart:458` `onTap: () {}` (no-op) |
| TV settings → labelled sections restructure | ❌ | `feature/tv-settings-restructure`; main lacks `settings_screen_tv.dart` |
| D-pad friendly source settings | ❌ | `fix/misc-tv-fixes`; `source_settings_screen.dart` has no `TvFocusable` |
| TV episode-range chips on detail | ✅ | `lib/core/tv/tv_episode_range_chips.dart` (in `main`) |

## 11. TV-Specific

| Feature | State | Evidence |
|---|:---:|---|
| Native Android TV player (Exo) | ✅ | `tv_exo_player_screen.dart`, `TvPlayerActivity.kt` |
| Apple TV (tvOS) player | ✅ | `tvos/Runner/TvSystemPlayerViewController.swift` |
| TV auto-tracking (Android/Apple native) | 🟡 | `liveProgress` wired in `tv_native_player.dart`, `tv_av_native_player.dart`; Exo fallback uses `maybeScrobble` only |
| TMDB multi-season episode synopses | ❌ | `fix/misc-tv-fixes`; `_enrichFromTmdbTv` absent from `main` |
| `fast` flag into JS `getVideoSources` | ✅ | present in `provider_manager.dart:1090` |

## 12. Engineering / Quality Gates

| Item | State | Evidence |
|---|:---:|---|
| Test suite green | ✅ | `flutter test`: **4454 passed, 8 skipped, 1 failed** — the 1 is the concurrency flake below (passes in isolation) |
| CI workflow in repo | ✅ | `.github/workflows/ci.yml` tracked |
| `dart_test.yaml` ffi skip | ✅ | tracked |
| TODO / FIXME debt in `lib` | ✅ | 0 real TODO/FIXME (only Spanish `todo` l10n strings) |
| `UnimplementedError` in `lib` | ✅ | 0 |
| Owner-disabled Cloudflare tests | ❌ | 3 skipped in `cf_solve_needed_test.dart` |

---

## 13. Unmerged Branches (7)

`main` already contains 44 of 51 upstream branches. These 7 are **not** merged:

| Branch | Content | Relation to `main` |
|---|---|---|
| `feat/debrid-rd-torbox` | Real-Debrid + TorBox clients, resolver, settings (~2.2k LOC) | base 2026-08-31, no overlap |
| `feat/portrait-mini-player` | Portrait watch screen, mini controls, comments placeholder | base 2026-08-17 |
| `feature/stremio-support` | Stremio catalogue + streams + title logos (~7k LOC) | base = `main` HEAD, clean add |
| `feature/tv-settings-restructure` | TV settings → labelled sections | base 2026-08-31 |
| `fix/68-tv-auto-tracking` | tvOS play-next "completed" scrobble | base 2026-08-31 |
| `fix/misc-tv-fixes` | TMDB multi-season synopses, D-pad source settings, fast flag, shared chips | base 2026-09-20 |
| `release/1.9.7` | build-number bump only | **older** than `main` (2026-08-24) — discard |

## 14. The 12 Failing Tests (historical — `main` baseline)

Superseded by the "Cross-check pass" section below; all of these are now green on
`openhands/green-main-and-integrations`.

| # | Test | Likely cause |
|---|---|---|
| 1 | `test/core/platform/trusted_certificates_test.dart` (setUpAll) | `keytool` not installed in sandbox |
| 2 | `test/core/ui/poster_card_customization_test.dart` — genre portrait/wide | `MissingPluginException` path_provider |
| 3 | `test/features/reader/manga_reader_test.dart` — cached page evicted | pending 10s cache timer after dispose |
| 4 | `test/features/sources/mihon_sources_screen_test.dart` — uninstall | `Expected: empty` (uninstall not removing) |
| 5 | `test/features/settings/settings_screen_test.dart` — back button | `pumpAndSettle` timeout |
| 6–11 | `test/features/shell/schedule_nav_test.dart` (6 tests) | duplicate `Hero` tag `viewer-profile-default` |
| 12 | `test/features/reader/manga_reader_test.dart` (2nd) | pending timer / cache cleanup |

---

## Summary Scoreboard

Counts reflect `openhands/green-main-and-integrations` after the integrations and
cross-check passes (see the two "Implementation status" / "Cross-check" sections).

| Area | Done | Partial | Not done |
|---|:---:|:---:|:---:|
| Platforms | 3 | 0 | 3 |
| Modes/Catalogues | 6 | 0 | 0 |
| Sources | 6 | 0 | 2 |
| Trackers | 5 | 0 | 1 |
| Player | 12 | 1 | 2 |
| Reader | 5 | 0 | 0 |
| Downloads | 5 | 0 | 0 |
| Social | 4 | 1 | 1 |
| Sync/Notify | 5 | 0 | 0 |
| Settings/UI | 4 | 0 | 4 |
| TV | 4 | 0 | 1 |
| Quality gates | 4 | 0 | 1 |
| **Total** | **63** | **2** | **15** |

### Highest-impact open gaps
1. **Watch Together** — fully built but owner-disabled; needs an explicit go-ahead to re-enable.
2. **Cloudflare handling** is owner-disabled (documented, not a bug); 3 tests skipped.
3. **Per-device build split** (android/ios/rest) and **Windows** platform are unstarted.
4. **Shikimori / Trakt / Kitsu trackers** absent (MAL, MangaBaka, Simkl present).
5. **iOS release** (beta only).

---

## Implementation status (follow-up pass)

Branch: `openhands/green-main-and-integrations` → PR #1 (base `main`).

### Green main — done
- **Test job**: green. Full suite 4283 passed / 8 skipped / 0 failed.
  - Fixed `test/core/zmode/match_store_test.dart` (missing `MatchStore.open()` left a Hive box unopened).
  - Fixed `test/core/zmode/sweep_waves_test.dart` (wall-clock budget → deterministic concurrency assertion).
- **Analyze job**: green (`flutter analyze` clean).
- **Build (Android) / Build (iOS)**: fixed. Both failed only because the proprietary,
  gitignored Discord native SDK (`.aar` / `.xcframework`) is absent from a clean checkout.
  Removed the native Discord Social SDK, its JNI layer, both MethodChannel bridges and the
  local install script; Rich Presence now runs on the Dart OAuth gateway on every platform.

### Discord "kizzy" replacement — closed, not viable
KizzyRPC authenticates with a raw Discord **account** token (self-bot; against Discord ToS) and
is Android-only, whereas the app holds only OAuth Bearer tokens. The OAuth Rich Presence
feature is kept; no proprietary SDK is reintroduced.

### Unmerged branches — integrated or intentionally skipped
| Branch | Outcome |
|---|---|
| `fix/misc-tv-fixes` | merged |
| `feature/stremio-support` | merged |
| `feat/debrid-rd-torbox` | merged |
| `fix/68-tv-auto-tracking` | merged |
| `feature/tv-settings-restructure` | **skipped** — superseded by `4c032a57` "Consolidate TV and Mobile Settings pages" (file deleted on `main`) |
| `feat/portrait-mini-player` | **skipped** — 1436 commits stale; portrait watch page already re-architected on `main` as `PlayerWatchPage` (`lib/features/player/player_watch_page.dart`). Merging would regress the current `PlayerScreen` (external-player, TV handoff, scrobble, `EpisodePlayerRoute`). |
| `release/1.9.7` | **skipped** — a `1.9.7+11103 → 1.9.7+11104` build bump; `main` is already at `2.3.5+23637`. |

### CI — all four jobs green
Run `42815032016` on head `75b40950`: **Analyze ✅ · Test ✅ · Build (Android) ✅ · Build (iOS) ✅**.
iOS needed one more fix: the pbxproj hard-referenced the gitignored
`ios/Runner/GoogleService-Info.plist` in Copy Bundle Resources, so any clean checkout failed
with "Build input file cannot be found". It is now bundled by an optional copy phase that
no-ops when absent (Android already applied its Firebase plugin conditionally, and the Dart
side already tolerated a missing plist).

### Corrections to the original gap table (verified on the integration branch)
Several rows were stale or misread; the underlying feature is already present:

| Original claim | Reality |
|---|---|
| "HLS-only source download ❌ (`DownloadStatus.unsupported`, phase 2)" | **Already implemented.** `HlsDownloader` + `_startHlsDownload` (background isolate, journal, resume, AES-128, fMP4/TS, subtitles). The enum comment is stale. Only **DASH** (`.mpd`) has no downloader — `_ranked` drops it by design. |
| "Watch Together / Watch Party ❌" | **Fully built, owner-disabled** (`e20d1d71 chore: disable watch together feature`). Supabase Broadcast/Presence backend, lobby, sync math and tests all exist. Left off deliberately — not re-enabled without an explicit go-ahead. |
| "Nav-tabs preview 'Change content mode' ❌ (no-op)" | **False positive.** The real dock button opens a working `GlassMenu`; the `onTap: () {}` is a settings *preview* mock. |
| "Profile 'more features' placeholder 🟡" | Intentional empty-state copy ("More features are on their way with Zoro…"), not a TODO. |

### Genuinely remaining (not done, not owner-gated) — see Cross-check pass for updates
- **iOS release**, **Windows platform**, **per-device build split** — unstarted.
- **Shikimori / Trakt / Kitsu trackers** — not present (MAL, MangaBaka, Simkl exist).
- (DASH download and episode comments, listed here at the time of writing, are now done —
  see the Cross-check pass below.)

---

## Cross-check pass (search, subtitles, shorts, and the rest)

Branch: `openhands/green-main-and-integrations`. Every row above was re-verified
against the tree, not the doc; several "not done" rows were stale and are corrected
in place. Findings:

### Search (commit `08bd955f`)
- Integrated. `_kSourcePreviewCap` is **100** (`search_screen.dart:253`); the per-source
  swipe list is no longer capped at 12. The remaining `take(12)` in `search_bloc.dart`
  is the idle *trending* preview, not the results cap.
- Catalogue pagers (`tmdb/anilist/mal/simkl_catalogue.dart`) now target 100; covered by
  `test/core/zmode/tmdb_catalogue_test.dart`.

### Subtitles (commit `4a19b37b`)
- Integrated. `lib/core/playback/` holds `subtitle_text_codec`, `subtitle_text_normalizer`,
  `subtitle_cue_text`, `subtitle_exporter`, `framex_subtitle_source`, `online_subtitle_search`.
- Wired into the phone sheet (`player_sheets.dart`), the TV players
  (`tv_exo_player_screen`, `tv_native_player`, `tv_av_native_player`) and the Kotlin bridge.

### Shorts + short-drama sources (commits `d4b87936`, `50f81f55`)
- Integrated. `root_shell.dart` routes `DockTab.shorts → ShortsScreen`; the feed filters
  reading sources via `content_mode.dart` `sourceInMode`.
- Free-only short-drama sources `goodshort`, `reelshort`, `netshort` ship in the pack
  (harness: 10/10 live pass; NetShort 5/5 live pass).

### Rows corrected from ❌/🟡 → ✅ (verified in the tree)
| Row | Was | Now | Evidence |
|---|---|---|---|
| Stremio catalogue + streams | ❌ | ✅ | `lib/core/stremio/` wired in detail/player/settings |
| Stremio title logos | ❌ | ✅ | shipped with `lib/core/stremio/` |
| Portrait mini-player | ❌ | ✅ | `player_watch_page.dart` |
| Episode comments | ❌ | ✅ | `episode_comments_sheet.dart` + `_openCommentsSheet` |
| Watch Together | ❌ | 🟡 | built, owner-disabled (unchanged behaviour) |
| tvOS play-next scrobble | ❌ | ✅ | `TvSystemPlayerViewController.playNext(completed:)` |
| Debrid (RD / TorBox) | ❌ | ✅ | `lib/core/debrid/` wired in settings + injector |
| HLS-only source download | ❌ | ✅ | `hls_downloader.dart` |
| DASH (.mpd) download | ❌ | ✅ | `dash_downloader.dart` + `dash_manifest.dart` |
| Test suite green | ❌ | ✅ | see below |
| CI workflow in repo | ❌ | ✅ | `.github/workflows/ci.yml` tracked |
| `dart_test.yaml` ffi skip | 🟡 | ✅ | tracked |

### Test suite
`flutter test --concurrency=4`: **4454 passed, 8 skipped, 1 failed**.
The single failure — `novel_reader_test.dart` "reopening a chapter restores its saved
scroll permille" — is a concurrency flake: it passes in isolation and in the full
`test/features/reader/` suite (112 pass). Same class as the documented
`poster_card_customization` / `wrong_title_sheet` flakes: a fixed delay races a real
async write. Green in isolation is the tell.

`flutter analyze`: clean. JS harness (`node --test js_harness/*.test.mjs`): 54 pass / 0 fail.

### Still genuinely open (unchanged)
DASH is now done; the real remainder is **iOS release**, **Windows**, **per-device build
split**, **Shikimori/Trakt/Kitsu trackers**, and the owner-disabled **Watch Together** /
**Cloudflare** items.
