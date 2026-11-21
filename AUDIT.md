# Full audit — Zangetsu vs Hikari

Second pass, deeper than `PARITY.md`. This one walks **every** Hikari package
(600 Kotlin files, 33 packages) and checks each unit against Zangetsu by file
and symbol, then against the test suite. Where `PARITY.md` listed 33
sub-features, this audit lists 114 units and corrects several statuses.

Trees compared:

| Tree | Revision | Files |
|---|---|---|
| `claudeone7492/Zangetsu` | `main` (post-wiring) | Dart, 708 test files / 5,551 test declarations |
| `codegeasse1/hikari` | `main` | 600 Kotlin files, 33 packages |

Legend: ✅ present and reachable · ⚠️ partial or deliberately different ·
❌ absent · ➖ not applicable to a Flutter mobile/TV app.

## Verdict

| Status | Units |
|---|---:|
| ✅ | 125 |
| ⚠️ | 11 |
| ❌ | 2 |
| ➖ | 2 |
| **Total** | **140** |

The 33-row ledger is fully closed (33/33 ✅, evidence in §1). Both remaining
❌ rows are outside the ledger: a shared extension guard layer, and offline
Piper/Sherpa voice packs (no models are bundled). The 11 partial rows are
built-but-unwired helpers, account- or server-gated APIs, or a deliberate
architectural choice — see §3.

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
| `cs3/` built-in resolvers | ✅ | `parity/Cs3BuiltInResolvers.kt`, last resort in `PluginHost.builtInSources` |
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
| `VxLosslessApi.kt` | ⚠️ | `core/music/lossless_source.dart` registered in the injector; needs a user endpoint (Parity tools), so it stays hidden until configured |
| `PoToken*.kt` | ⚠️ | `core/music/potoken.dart` built; no caller yet |
| `VxDownload.kt` | ✅ | `core/music/music_download.dart`, download action in the music player sheet |
| `TvMusic*.kt` | ✅ | `features/music/music_screen_tv.dart` on the TV shell |

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
| `deeplink/RepoLinkActivity.kt` | ✅ | `parity/RepoLinkActivity.kt`, manifest filters, handed to `addRepo` in `MainActivity` |
| `net/StreamProbe.kt` | ✅ | `core/playback/stream_probe.dart` |
| `net/SlowNetTip.kt` | ✅ | `core/playback/slow_net_tip.dart`, shown after the probe in `player_controller` |
| `work/` foreground service | ⚠️ | `parity/WorkService.kt` ships and compiles; nothing starts it yet |

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
| Kitsu | ✅ | `core/tracker/kitsu_service.dart` |
| Shikimori | ✅ | `core/tracker/shikimori_service.dart` |
| `data/Ratings.kt` (IMDb/RT/Metacritic aggregation) | ⚠️ | `core/metadata/rating_aggregator.dart` built; no keyless source, so nothing calls it |
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
| `IptvMark` (channel favourites) | ✅ | `core/live/iptv_mark_store.dart`, star on every channel card |
| Manage / on-demand / sports screens | ✅ | `features/live/live_manage_screens.dart`, routed from the Live TV overflow |
| Channel logos (`IptvArt`) | ✅ | `m3u_playlist.dart` logo + `live_playlist_store.dart` cover |

### Dub

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `dub/AiDub.kt` + local/Google voices | ✅ | `core/dub/dub_engine.dart`, platform bridge |
| `NeuralTtsService`, `SherpaTtsVoice` (hosted path) | ✅ | `core/dub/http_tts_service.dart` |
| `VoiceScanRunner`, `SpeakerEmbedder` (hosted path) | ✅ | `core/dub/voice_scan.dart` |
| `SubtitleGenClient`, `VoiceTranscriber` | ✅ | `core/dub/voice_transcriber.dart` |
| `VolumeBoostProcessor` | ✅ | Player audio sheet, 100–200 % |
| `PiperVoice` offline packs | ❌ | Hosted only; `parity/OfflineVoicePack.kt` reports none bundled |
| `HardSubDub` | ⚠️ | `parity/HardSubBurner.kt` compiles; no caller and needs a device to verify |
| `AudioFx` | ✅ | `core/playback/audio_fx.dart` chain applied to mpv `af` |

### Player and TV

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `PlayerActivity`, `PlayerControls` | ✅ | `features/player/player_screen.dart`, controls |
| `ColorPickerDialog` | ✅ | `features/player/subtitle_style.dart` |
| `EnhancePreset` / Anime4K | ✅ | `features/player/shader_presets.dart` |
| `PlayerSkins`, `ServerLayouts`, `PlayerUiStyle` | ✅ | `features/player/player_skins.dart`, picker in the audio sheet, applied in the overlay |
| `ServerScreenStyles`, `ServerStreamsPage`, `StreamsLive` | ✅ | `features/player/server_streams_page.dart`, opened from the stream picker |
| `TvFocus`, `TvKeys`, `TvNavRail`, `TvTopBar`, `TvHomeStage` | ✅ | `core/tv/`, TV surfaces |
| `TvCs3` | ✅ | `features/sources/cloudstream_sources_screen_tv.dart` |
| `MouseMode` | ⚠️ | `core/tv/mouse_mode.dart` built; no settings toggle yet |
| `TvDesktop` | ➖ | No desktop target |
| `ScrollAnim`, `ScrollKeeper` | ⚠️ | `core/ui/scroll_keeper.dart` built; not wired into the lists |

### Reader

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `ChimahonPagerReader` (paged) | ✅ | `features/reader/manga_reader_screen.dart` |
| `YomiWebtoonReader` (webtoon) | ✅ | Same screen, webtoon mode |
| `CropBorders` | ✅ | `core/reading/crop_borders.dart` |
| `MangaTranslate` | ✅ | `core/reading/manga_translation/` |
| `NovelTranslate` | ✅ | `core/reading/novel_translate.dart`, chapter action in the novel reader |
| `ReaderSettings`, `ReaderEnums` | ✅ | `core/reading/reader_settings.dart`, `reader_prefs.dart` |
| `WebtoonPageCache` | ✅ | `core/reading/page_file_cache.dart`, tiles |
| Reader highlights | ✅ | `core/reading/reader_highlights.dart` |
| Tap zones | ✅ | `core/reading/tap_zones.dart` |
| `SharpenTransformation` | ✅ | `core/reading/sharpen_provider.dart`, reader pref, page pipeline |
| `ScraperReaderScreen` | ⚠️ | `features/reader/scraper_reader_screen.dart` built; no entry point yet |
| `TachiyomiReaderDecoder` | ✅ | `core/mihon/tachiyomi_backup.dart`, import in Parity tools |
| `ExtensionPageImageFetcher` | ✅ | Reader fetches pages through the provider |

### Data and system

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `HomeDedupe` | ✅ | `core/metadata/home_dedupe.dart`, wired into the home rows |
| `NsfwGate`, `ExtensionNsfw`, `ContentGate` | ✅ | `core/privacy/nsfw_gate.dart`, driven by the NSFW-source switch |
| `TitleQuality` | ✅ | `core/metadata/title_quality.dart`, badge on home cards |
| `EpisodeDubSub` | ✅ | `core/metadata/episode_dub_sub.dart`, merged in `EpisodeMetadataService` |
| `DownloadsSaver` | ✅ | `parity/MediaExporter.kt` + `core/platform/media_export.dart`, Export in the downloads menu |
| `PerfMode` | ✅ | `core/performance/perf_mode.dart` |
| `MemoryReport` | ✅ | `core/diagnostics/memory_report.dart` |
| `Translator` | ✅ | `core/translation/plain_text_translation_service.dart` |
| `i18n/TagTranslator` | ✅ | `core/i18n/tag_translator.dart` |
| `nuvio/BangumiMeta` | ✅ | `core/metadata/bangumi.dart` |
| `TvdbArt` | ✅ | `core/metadata/tvdb_art.dart` |
| `NuvioCatalogImport`, `NuvioCollectionsImport` | ✅ | `core/collections/nuvio_import.dart`, import in Parity tools |
| `TmdbStills`, `TmdbScreenshots` | ✅ | `core/ui/stills_rail.dart` under the detail synopsis |
| `DonghuaDetails` | ✅ | `core/metadata/donghua_details.dart`, facts block on CN titles |
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
| `CustomBackground` | ⚠️ | `core/theme/background_pref.dart` built; no picker yet |
| `UiScale` | ✅ | `core/ui/ui_scale.dart`, slider in Parity tools |
| `AppIconManager` | ✅ | `core/app_icon/app_icon_service.dart` |
| `AppLockGate` | ✅ | `features/privacy/app_lock_gate.dart` |
| `PairScreen` | ✅ | `features/backup/pair_sync_screen.dart` |
| `ProfilesScreen` | ✅ | `features/profiles/` |
| `SettingsScreen`, `SettingsChrome` | ✅ | `features/settings/` |
| `TrackerLoginDialog` | ✅ | Tracker hub connect sheets |
| `TelegramScreen`, `TelegramDialog` | ✅ | `features/telegram/` |
| `UpdateDialog` | ✅ | `core/update/` |
| `HelpText` | ✅ | `core/ui/help_sheet.dart`, opened from Parity tools |
| `FlagIcon`, `LangTag`, `SourceLangs` | ✅ | `core/i18n/source_languages.dart`, `source_lang_prefs.dart` |
| `IptvArt` | ✅ | Channel logo from M3U |
| `GenresOverlay` | ✅ | Genre filter sheet |
| `ChoicePickers`, `Components`, `Color`, `Type`, `Artwork`, `PosterLoader` | ✅ | Equivalent shared widgets |

## 3. What is actually open

The 2 ❌ units, then the 11 ⚠️ rows that are still partial. Everything else in
§2 is present **and reachable from the UI**:

| Gap | Kind | Why it is open | Effort |
|---|---|---|---|
| Extension UI/verify guards | Dart | No shared guard layer; each caller still checks by hand | S |
| Offline Piper/Sherpa voices | Native | No model packs are bundled; `OfflineVoicePack` reports none, the hosted path is the shipped one | L |
| Load-slot semaphore (`LoadGate`) | Native | Replaced by per-host in-flight dedupe, not a global cap | M |
| Lossless music | API | `LosslessSource` is registered but needs a user-supplied endpoint, so it is hidden until configured | M |
| YouTube PoToken | API | `core/music/potoken.dart` built; no caller — the token service is server-dependent | L |
| Foreground work service | Native | `WorkService` compiles and ships; nothing starts it (downloads use the existing background service) | S |
| Hard-sub dub | Native | `HardSubBurner` compiles; no caller, and PixelCopy burn-in needs a device to verify | L |
| Multi-source ratings | API | `rating_aggregator.dart` built; no keyless IMDb/RT/Metacritic source, so nothing calls it | M |
| TDLib private channels | Native | The seam reports `available=false` until TDLib is linked | L |
| TV mouse mode | Dart | `core/tv/mouse_mode.dart` built; no settings toggle | S |
| Scroll keeper / animations | Dart | `core/ui/scroll_keeper.dart` built; not wired into the lists | S |
| Generic scraper reader | Dart | `features/reader/scraper_reader_screen.dart` built; no entry point yet | M |
| Custom background | Dart | `core/theme/background_pref.dart` built; no picker or persistence | S |

Everything else that used to be listed here — Kitsu, Shikimori, the CS3
built-in resolvers, repo-link intents, music downloads, novel translation,
sharpen, Nuvio import, the Tachiyomi decoder, download export, the stills rail,
donghua facts, UI scale, the help sheet, player skins, the server page, Live TV
marks and the manage/on-demand/sports screens — now has a call site, listed in
§2.

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

Counts from `test/` on `main` (`test(` + `testWidgets(` declarations):

| Area | Files | Tests |
|---|---:|---:|
| `test/core/playback` | 34 | 271 |
| `test/core/reading` | 23 | 211 |
| `test/core/tracker` | 18 | 179 |
| `test/core/live` | 8 | 143 |
| `test/core/dub` | 7 | 110 |
| `test/core/metadata` | 15 | 103 |
| `test/core/web` | 6 | 31 |
| `test/core/i18n` | 3 | 22 |
| `test/core/performance` | 1 | 3 |
| `test/core/diagnostics` | 1 | 2 |
| `test/features/reader` | 9 | 119 |
| **Whole suite** | **708** | **5,551** |

`flutter analyze` → No issues found. Suites are run per area in this sandbox
(a whole-suite run gets killed by the runtime restart); the results are in the
handoff notes. `flutter build apk --debug` builds, so the Kotlin in
`android/app/src/main/kotlin/.../parity/` compiles.

## 6. Bottom line

- The migration's ledger is complete: **33/33 ✅**, verified by path.
- Against the whole reference app, Zangetsu is at **125 ✅ / 140 units (89 %)**,
  or **136/138 applicable (99 %)** counting the partial rows as usable.
- The remaining ❌ set is two units: a shared extension guard layer and offline
  voice packs. The ⚠️ set is built-but-unwired helpers and account- or
  server-gated APIs, each named in §3.
- Nothing in the open set blocks an existing workflow.
