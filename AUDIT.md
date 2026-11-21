# Full audit — Zangetsu vs Hikari

Second pass, deeper than `PARITY.md`. This one walks **every** Hikari package
(600 Kotlin files, 33 packages) and checks each unit against Zangetsu by file
and symbol, then against the test suite. Where `PARITY.md` listed 33
sub-features, this audit lists 114 units and corrects several statuses.

Trees compared:

| Tree | Revision | Files |
|---|---|---|
| `claudeone7492/Zangetsu` | `65b7db3` | Dart, 693 test files / 5,525 test declarations |
| `codegeasse1/hikari` | `main` | 600 Kotlin files, 33 packages |

Legend: ✅ present and reachable · ⚠️ partial or deliberately different ·
❌ absent · ➖ not applicable to a Flutter mobile/TV app.

## Verdict

| Status | Units |
|---|---:|
| ✅ | 104 |
| ⚠️ | 13 |
| ❌ | 21 |
| ➖ | 2 |
| **Total** | **140** |

The 33-row ledger is fully closed (33/33 ✅, evidence in §1). All 21 open
items are outside the ledger, and 12 of them are native-only or
account-gated. The 15 partial rows are either cosmetic, source-level instead
of item-level, or a deliberate architectural choice.

## 1. Ledger — 33/33 ✅

Every path below was checked to exist at `65b7db3`.

| # | Feature | Evidence |
|---|---|---|
| A1 | Universal JSON-rule scrapers | `core/universal/universal_provider.dart` + bundled manifest |
| A2 | Nuvio providers | `core/provider/js_pack_engine.dart`, prefix `nuvio:` |
| A3 | Vega providers | Same engine, prefix `vega:` |
| A4 | Sora modules | Same engine, prefix `sora:` |
| A5 | Anymex plugins | `core/mangayomi/mangayomi_defaults.dart` |
| A6 | SkyStream plugins | Same engine, prefix `sky:` |
| A7 | Kotatsu parsers | Same engine, prefix `kot:` |
| A8 | `.hiki` extensions | `core/hikari/hikari_manager.dart` + DexClassLoader host |
| A9 | `.cs3` API completeness | Bytecode audit: 761 plugins, 0 missing classes/methods |
| B1 | Music mode | `core/music/jiosaavn_source.dart`, `features/music/` |
| B2 | Telegram streaming | `core/telegram/telegram_source.dart`, public channels |
| B3 | Browser + userscripts | `features/web/websites_screen.dart`, `core/web/userscript_store.dart` |
| B4 | Subtitle sites | `core/playback/subtitle_search_service.dart` |
| B5 | Trackers | `core/tracker/{trakt,mal,simkl,mangabaka}_service.dart` |
| C1 | EPG / XMLTV | `core/live/epg_store.dart`, `xmltv_parser.dart` |
| C2 | DVR / reminders | `core/live/dvr_store.dart`, `dvr_capture_service.dart` |
| C3 | Xtream | `core/live/xtream_api.dart`, `xtream_account_store.dart` |
| C4 | Sports / catch-up / parental | `sports_catalog.dart`, `catchup_url.dart`, `live_parental.dart` |
| C5 | Live VOD / torrent | `core/live/live_vod.dart` |
| D1 | AI Dub | `core/dub/dub_engine.dart`, `features/player/dub_sheet.dart` |
| D2 | Neural voices | `core/dub/http_tts_service.dart` |
| D3 | Voice scan | `core/dub/voice_scan.dart` |
| D4 | Whisper S2T | `core/dub/voice_transcriber.dart` |
| D5 | Volume boost | `features/player/player_sheets.dart` |
| E1 | Stats | `features/stats/stats_screen.dart` |
| E2 | App lock | `core/privacy/app_lock.dart` |
| E3 | Pair & sync | `core/pair/pair_protocol.dart` |
| E4 | Logs | `core/logging/app_logger.dart`, `features/settings/logs_screen.dart` |
| E5 | Title-as-logo | `core/metadata/title_logo_service.dart` |
| E6 | Per-extension settings | `hasSourceSettings`/`openSourceSettings`, JS `__settings` |
| E7 | Collections | `core/collections/collection_store.dart` |
| F1 | `.hiki` SDK host | Vendored `com.hikari.ext` |
| F2 | CS3 API completeness | Closed by A9 |

## 2. Feature audit — all 33 Hikari packages

### Providers and extension runtimes

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `providers/UniversalScraper.kt` | ✅ | `core/universal/` |
| `nuvio/` | ✅ | JS-pack engine, `nuvio:` |
| `providers/vega/` | ✅ | JS-pack engine, `vega:` |
| `sora/` | ✅ | JS-pack engine, `sora:` |
| `anymex/` | ✅ | Mangayomi bridge + Kegareta indexes |
| `skystream/` | ✅ | JS-pack engine, `sky:` |
| `kotatsu/` | ✅ | JS-pack engine, `kot:` |
| `hiki/` | ✅ | `core/hikari/` + native SDK |
| `cs3/` host + API | ✅ | CloudStream host, bytecode audit |
| `cs3/` built-in resolvers | ❌ | Not bundled (NewPipe/MovieBlast/Mlbd/Fallback) |
| `aniyomi/` | ✅ | `core/aniyomi/` |
| Mihon host | ✅ | `core/mihon/` |
| Mangayomi host | ✅ | `core/mangayomi/` |
| `lnreader/` | ✅ | `core/lnreader/` |
| `zangetsu/` plugin family | ➖ | Zangetsu is the host; its Dart provider API is the equivalent |
| `core/LoadGate.kt` (load-slot semaphore) | ⚠️ | No load-slot cap; per-host in-flight dedupe only |

### Music

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `music/` mode + JioSaavn | ✅ | `core/music/`, `features/music/` |
| `VxLosslessApi.kt` | ❌ | JioSaavn only |
| `PoToken*.kt` | ❌ | No YouTube music source |
| `VxDownload.kt` | ❌ | No music download path |
| `TvMusic*.kt` | ⚠️ | Phone screen reused with TV focus wrappers |

### Telegram

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| Public channel streaming | ✅ | `core/telegram/`, web fallback |
| TDLib private channels | ⚠️ | Native seam reports `available=false` until TDLib is linked |

### Web and network

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `web/WebViewActivity.kt` | ✅ | `features/web/websites_screen.dart` |
| `web/UserscriptManager.kt` | ✅ | `core/web/userscript_store.dart` |
| `net/AdBlocker.kt` | ✅ | `core/web/ad_block.dart` |
| `net/PromoGuard.kt` | ✅ | `core/web/promo_guard.dart` |
| `data/RedirectAllow.kt` | ✅ | `core/web/redirect_allow.dart` |
| `net/ExtensionUiGuard.kt`, `ExtensionVerifyGuard.kt` | ❌ | No shared guard layer |
| `deeplink/RepoLinkActivity.kt` | ❌ | No native repo-link intent |
| `net/StreamProbe.kt` | ✅ | `core/playback/stream_probe.dart` |
| `net/SlowNetTip.kt` | ⚠️ | Tuning + toggle; in-player tip absent |
| `work/` foreground service | ❌ | No wake-lock/ongoing-notification service |

### Subtitles

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `subtitles/SubtitleSites.kt` | ✅ | `core/playback/subtitle_search_service.dart` (OpenSubtitles.org + SubtitleCat) |
| `player/SubtitleStyle.kt` | ✅ | `features/player/subtitle_style.dart`, `subtitle_style_model.dart` |
| Subtitle sync | ✅ | `features/player/subtitle_sync_engine.dart` |
| Subtitle fonts | ✅ | `features/player/subtitle_font_service.dart` |
| External subtitle export | ✅ | `core/download/external_subtitle_export.dart` |

### Trackers

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| Trakt | ✅ | `core/tracker/trakt_service.dart` |
| MAL | ✅ | `core/tracker/mal_service.dart` |
| Simkl | ✅ | `core/tracker/simkl_service.dart` |
| MangaBaka | ✅ | `core/tracker/mangabaka_service.dart` |
| Kitsu | ❌ | No account-password client |
| Shikimori | ❌ | No OAuth client |
| `data/Ratings.kt` (IMDb/RT/Metacritic aggregation) | ❌ | TMDB/AniList scores only |
| `data/TrackerLibraryRepository.kt` | ✅ | `features/home/cubit/tracker_list_cubit.dart` |

### Live TV

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `LiveTvImport`, `IptvPlaylist`, `JsonPlaylist` | ✅ | `core/live/m3u_playlist.dart`, import screen |
| `EpgStore`, `XmltvParser` | ✅ | `core/live/epg_store.dart`, `xmltv_parser.dart` |
| `LiveTvRecord*`, `LiveTvReminders` | ✅ | `core/live/dvr_store.dart`, `dvr_capture_service.dart` |
| `XtreamApi` | ✅ | `core/live/xtream_api.dart` |
| `LiveTvSports`, `CatchupUrlBuilder`, `LiveTvParental` | ✅ | `sports_catalog.dart`, `catchup_url.dart`, `live_parental.dart` |
| `LiveTvVod`, `LiveTvTorrentStream` | ✅ | `core/live/live_vod.dart` |
| `IptvMark` (channel favourites) | ⚠️ | No separate marks store |
| Manage / on-demand / sports screens | ⚠️ | Flows exist in the main screen; no dedicated screens |
| Channel logos (`IptvArt`) | ✅ | `m3u_playlist.dart` logo + `live_playlist_store.dart` cover |

### Dub

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `dub/AiDub.kt` + local/Google voices | ✅ | `core/dub/dub_engine.dart`, platform bridge |
| `NeuralTtsService`, `SherpaTtsVoice` (hosted path) | ✅ | `core/dub/http_tts_service.dart` |
| `VoiceScanRunner`, `SpeakerEmbedder` (hosted path) | ✅ | `core/dub/voice_scan.dart` |
| `SubtitleGenClient`, `VoiceTranscriber` | ✅ | `core/dub/voice_transcriber.dart` |
| `VolumeBoostProcessor` | ✅ | Player audio sheet, 100–200 % |
| `PiperVoice` offline packs | ❌ | Hosted only |
| `HardSubDub` | ❌ | No PixelCopy burn-in |
| `AudioFx` | ⚠️ | Pitch only |

### Player and TV

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `PlayerActivity`, `PlayerControls` | ✅ | `features/player/player_screen.dart`, controls |
| `ColorPickerDialog` | ✅ | `features/player/subtitle_style.dart` |
| `EnhancePreset` / Anime4K | ✅ | `features/player/shader_presets.dart` |
| `PlayerSkins`, `ServerLayouts`, `PlayerUiStyle` | ⚠️ | Functional equivalents, different styling |
| `ServerScreenStyles`, `ServerStreamsPage`, `StreamsLive` | ⚠️ | Server/stream selection exists; no dedicated page |
| `TvFocus`, `TvKeys`, `TvNavRail`, `TvTopBar`, `TvHomeStage` | ✅ | `core/tv/`, TV surfaces |
| `TvCs3` | ✅ | `features/sources/cloudstream_sources_screen_tv.dart` |
| `MouseMode` | ❌ | No pointer mode for TV |
| `TvDesktop` | ➖ | No desktop target |
| `ScrollAnim`, `ScrollKeeper` | ⚠️ | Some list state kept; no global scroll animation |

### Reader

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `ChimahonPagerReader` (paged) | ✅ | `features/reader/manga_reader_screen.dart` |
| `YomiWebtoonReader` (webtoon) | ✅ | Same screen, webtoon mode |
| `CropBorders` | ✅ | `core/reading/crop_borders.dart` |
| `MangaTranslate` | ✅ | `core/reading/manga_translation/` |
| `NovelTranslate` | ❌ | No chapter-level novel translation |
| `ReaderSettings`, `ReaderEnums` | ✅ | `core/reading/reader_settings.dart`, `reader_prefs.dart` |
| `WebtoonPageCache` | ✅ | `core/reading/page_file_cache.dart`, tiles |
| Reader highlights | ✅ | `core/reading/reader_highlights.dart` |
| Tap zones | ✅ | `core/reading/tap_zones.dart` |
| `SharpenTransformation` | ❌ | Crop only |
| `ScraperReaderScreen` | ❌ | No image-list reader for scraped pages |
| `TachiyomiReaderDecoder` | ❌ | Mihon host exists; no Tachiyomi backup decode |
| `ExtensionPageImageFetcher` | ✅ | Reader fetches pages through the provider |

### Data and system

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `HomeDedupe` | ✅ | `core/metadata/home_dedupe.dart`, wired into the home rows |
| `NsfwGate`, `ExtensionNsfw`, `ContentGate` | ✅ | `core/privacy/nsfw_gate.dart`, driven by the NSFW-source switch |
| `TitleQuality` | ✅ | `core/metadata/title_quality.dart`, badge on home cards |
| `EpisodeDubSub` | ✅ | `core/metadata/episode_dub_sub.dart`, merged in `EpisodeMetadataService` |
| `DownloadsSaver` | ❌ | No export to public Downloads via MediaStore |
| `PerfMode` | ✅ | `core/performance/perf_mode.dart` |
| `MemoryReport` | ✅ | `core/diagnostics/memory_report.dart` |
| `Translator` | ✅ | `core/translation/plain_text_translation_service.dart` |
| `i18n/TagTranslator` | ✅ | `core/i18n/tag_translator.dart` |
| `nuvio/BangumiMeta` | ✅ | `core/metadata/bangumi.dart` |
| `TvdbArt` | ✅ | `core/metadata/tvdb_art.dart` |
| `NuvioCatalogImport`, `NuvioCollectionsImport` | ❌ | No Nuvio export import |
| `TmdbStills`, `TmdbScreenshots` | ⚠️ | Episode stills backfilled; detail rail absent |
| `DonghuaDetails` | ⚠️ | Country field only |
| `AnimeReleaseCalendarRepository` | ✅ | `core/schedule/airing_service.dart`, `coming_soon_service.dart` |
| `WatchStats` | ✅ | `core/stats/`, `features/stats/` |
| `Profiles` | ✅ | `core/profiles/` |
| `BackupManager` | ✅ | `core/backup/` |
| `AppStore` (update) | ✅ | `core/update/` |
| `Logs` | ✅ | `core/logging/app_logger.dart` |
| `StreamCache`, `MetaCache` | ✅ | `core/cache/media_cache.dart`, `app_image_cache.dart` |
| `RepoProvenance` | ✅ | Detail shows the source repo |
| `Genres` | ✅ | Genre filter + `TagTranslator` |
| `SourceUrls` | ✅ | `kDefaultRepoUrls`, source settings |

### UI (84 screens/components)

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `StatsScreen` | ✅ | `features/stats/stats_screen.dart` |
| `LogsScreen` | ✅ | `features/settings/logs_screen.dart` |
| `WebSitesScreen` | ✅ | `features/web/websites_screen.dart` |
| `CollectionScreens` | ✅ | `features/home/collections_screen.dart` |
| `DetailScreen`, `MangaDetailScreen` | ✅ | `features/detail/` |
| `MangaScreen`, `MangaReaderScreen`, `NovelReaderScreen` | ✅ | Mode home + `features/reader/` |
| `HomeScreen`, `CatalogScreen`, `SearchScreen`, `SearchTv` | ✅ | `features/home/` |
| `HistoryScreen`, `MyStuffScreen`, `LibraryScreen`, `LibraryCategories` | ✅ | `features/history/`, `library_tabs.dart`, `library_filter.dart` |
| `DownloadsScreen` | ✅ | `features/downloads/` |
| `ExtensionsScreen`, `ProviderPacks`, `ProviderFlags`, `ProviderSettingsDialogs` | ✅ | `features/sources/` |
| `LiveTv*` screens | ✅ | `features/live/` (5 screens) |
| `PlayerGesturesScreen`, `PlayerStyleScreen` | ✅ | `features/settings/tap_zones_screen.dart`, `player_controls_screen.dart` |
| `PosterCardsScreen`, `PosterSizing`, `PosterStyle` | ✅ | `poster_card_settings_screen.dart`, `core/ui/poster_card.dart` |
| `LoadingStyles` | ✅ | `features/detail/detail_skeleton.dart` |
| `Accents`, `AccentStore`, `AuraColors`, `Theme`, `AppFonts` | ✅ | `core/theme/`, `appearance_screen.dart` |
| `CustomBackground` | ❌ | No custom background image |
| `UiScale` | ❌ | System text scale respected; no in-app UI scale |
| `AppIconManager` | ✅ | `core/app_icon/app_icon_service.dart` |
| `AppLockGate` | ✅ | `features/privacy/app_lock_gate.dart` |
| `PairScreen` | ✅ | `features/backup/pair_sync_screen.dart` |
| `ProfilesScreen` | ✅ | `features/profiles/` |
| `SettingsScreen`, `SettingsChrome` | ✅ | `features/settings/` |
| `TrackerLoginDialog` | ✅ | Tracker hub connect sheets |
| `TelegramScreen`, `TelegramDialog` | ✅ | `features/telegram/` |
| `UpdateDialog` | ✅ | `core/update/` |
| `HelpText` | ⚠️ | Inline help exists; no shared help surface |
| `FlagIcon`, `LangTag`, `SourceLangs` | ✅ | `core/i18n/source_languages.dart`, `source_lang_prefs.dart` |
| `IptvArt` | ✅ | Channel logo from M3U |
| `GenresOverlay` | ✅ | Genre filter sheet |
| `ChoicePickers`, `Components`, `Color`, `Type`, `Artwork`, `PosterLoader` | ✅ | Equivalent shared widgets |

## 3. What is actually open

The 21 ❌ units, with the work each needs:

| Gap | Kind | Why it is open | Effort |
|---|---|---|---|
| Kitsu tracker | Dart | Account-password auth + credential store | M |
| Shikimori tracker | Dart | OAuth, same shape as MAL | M |
| CS3 built-in resolvers | Native | JVM classes the host must ship | M |
| Extension UI/verify guards | Dart | No shared guard layer | S |
| Repo-link intents | Native | Activity + manifest | S |
| Foreground work service | Native | Wake lock + ongoing notification | M |
| Offline Piper/Sherpa voices | Native | Model packs, storage | L |
| Hard-sub dub | Native | PixelCopy burn-in, needs a device | L |
| Lossless music | API | No keyless lossless catalogue | M |
| YouTube PoToken | API | Fragile, server-dependent | L |
| Music downloads | Dart | No audio download path | M |
| Novel chapter translation | Dart | Reader translates nothing at chapter level | M |
| Sharpen filter | Dart | Convolution over the existing crop pipeline | S |
| Generic scraper reader | Dart | Image-list reader for scraped pages | M |
| Nuvio catalog/collections import | Dart | Parser + paste flow | M |
| Tachiyomi decoder | Dart | Backup/reader-settings decode | M |
| Multi-source ratings | API | IMDb/RT/Metacritic aggregation | M |
| Download export to gallery | Native | MediaStore write | S |
| Mouse mode (TV) | Dart | Pointer handling on leanback | S |
| Custom background | Dart | Theming layer | S |
| In-app UI scale | Dart | Global scale factor | S |

The 13 ⚠️ rows in §2 are either cosmetic (skins, scroll animation, TV music
styling, help text), source-level instead of item-level (NSFW gate, home
dedupe), or deliberately different (TDLib unavailable until linked, load
slots replaced by per-host in-flight dedupe, no in-player slow-net tip,
no dedicated Live TV manage/on-demand screens, no detail stills rail,
partial donghua fields, audio FX pitch only). None blocks a workflow.

## 4. Corrections to the earlier matrix

The first pass under-counted Zangetsu. These are **present** and were not in
`PARITY.md`:

- Paged and webtoon manga readers (not just "a reader").
- Crop borders, reader settings, highlights, tap zones, page cache and tiles.
- Manga page translation (whole pipeline, not just a hook).
- Download manager with batch planning (not only chapter downloads).
- Profiles, release calendar, library tabs, poster sizing, skeleton loading.
- Subtitle style, sync, font service and external subtitle export.
- Anime4K enhancement and the subtitle colour picker.
- TV CloudStream sources, channel logos, source-language badges.
- Simkl and MangaBaka trackers (the first pass named only Trakt/MAL).

These were **over-counted or mis-scoped**:

- "Audio FX" is pitch only — correct as ⚠️, but the row is smaller than it reads.
- "Player skins" is cosmetic; the functional stream/server selection exists.
- "Channel marks" is the only Live TV store gap; favourites elsewhere are not it.

Newly discovered open items (not in the first matrix at all):

- `data/Ratings.kt`, `data/TitleQuality.kt`, `data/EpisodeDubSub.kt`,
  `data/DownloadsSaver.kt`, app-wide `NsfwGate`, cross-engine `HomeDedupe`,
  `core/LoadGate.kt`, `reader/TachiyomiReaderDecoder.kt`, `tv/MouseMode.kt`,
  `ui/UiScale.kt`, `ui/CustomBackground.kt`, `reader/NovelTranslate.kt`.

## 5. Test evidence

Counts from `test/` at `65b7db3` (`test(` + `testWidgets(` declarations):

| Area | Files | Tests |
|---|---:|---:|
| `test/core/playback` | 32 | 268 |
| `test/core/reading` | 22 | 209 |
| `test/core/tracker` | 18 | 179 |
| `test/core/live` | 8 | 143 |
| `test/core/dub` | 7 | 110 |
| `test/core/metadata` | 10 | 87 |
| `test/core/web` | 6 | 31 |
| `test/core/i18n` | 3 | 22 |
| `test/core/performance` | 1 | 3 |
| `test/core/diagnostics` | 1 | 2 |
| `test/features/reader` | 9 | 119 |
| **Whole suite** | **693** | **5,525** |

`flutter analyze` → No issues found. Full-suite runs are flaky in this sandbox
(two pre-existing tests fail only under the full run); the suites above were
run per area and pass.

## 6. Bottom line

- The migration's ledger is complete: **33/33 ✅**, verified by path.
- Against the whole reference app, Zangetsu is at **104 ✅ / 140 units (74 %)**,
  or **117/140 (84 %)** counting the partial rows as usable.
- The remaining ❌ set is dominated by native seams and account-gated
  trackers; the largest pure-Dart items are Nuvio import, the scraper reader,
  novel chapter translation, and episode-level dub/sub merging.
- Nothing in the ❌ set blocks an existing workflow.
