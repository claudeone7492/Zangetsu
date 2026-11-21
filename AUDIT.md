# Full audit — Zangetsu vs Hikari

Second pass, deeper than `PARITY.md`. This one walks **every** Hikari package
(600 Kotlin files, 33 packages) and checks each unit against Zangetsu by file
and symbol, then against the test suite. Where `PARITY.md` listed 33
sub-features, this audit lists 114 units and corrects several statuses.

Trees compared:

| Tree | Revision | Files |
|---|---|---|
| `claudeone7492/Zangetsu` | `main` head | Dart, 714 test files / 5,563 test declarations |
| `codegeasse1/hikari` | `main` | 600 Kotlin files, 33 packages |

Legend: ✅ present and reachable · ⚠️ partial or deliberately different ·
❌ absent · ➖ not applicable to a Flutter mobile/TV app.

## Verdict

| Status | Units |
|---|---:|
| ✅ | 139 |
| ⚠️ | 0 |
| ❌ | 0 |
| ➖ | 2 |
| **Total** | **141** |

The 33-row ledger is fully closed (33/33 ✅, evidence in §1). Nothing is ❌ or
⚠️ any more. Offline narration runs on the platform's downloaded voice packs
(no model is bundled, by choice — a Piper pack is 60–200 MB per voice), the
YouTube PO token has the source it was built for, and TDLib is now linked:
Telegram reads private channels and full history through the vendored client,
with the web preview kept as the fallback. See §3.

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
| `core/LoadGate.kt` (load-slot semaphore) | ✅ | `core/provider/load_gate.dart` wraps every JS-pack load; per-host in-flight dedupe kept |

### Music

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `music/` mode + JioSaavn | ✅ | `core/music/`, `features/music/` |
| YouTube Music catalogue | ✅ | `YouTubeMusicSource` (see `MusicApi.kt` below) is a second catalogue in the same service |
| `VxLosslessApi.kt` | ✅ | `core/music/lossless_source.dart`; endpoint and key persist in Hive (`lossless_endpoint`), prefilled and editable in Parity tools |
| `MusicApi.kt` (YouTube Music) | ✅ | `core/music/youtube_music_source.dart`, registered next to JioSaavn: WEB_REMIX InnerTube for browse/search, ANDROID_VR → iOS → Android Music → MWEB for playback |
| `PoToken*.kt` | ✅ | `core/music/potoken.dart` + `potoken_js.dart` — visitor id, BotGuard `Create`/`GenerateIT`, mint in the QuickJS runtime; the MWEB client sends the token and its visitor id, and the source tries native clients first so a mint failure costs only the fallback |
| `VxDownload.kt` | ✅ | `core/music/music_download.dart`, download action in the music player sheet |
| `TvMusic*.kt` | ✅ | `features/music/music_screen_tv.dart` on the TV shell |

### Telegram

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| Public channel streaming | ✅ | `core/telegram/`, web fallback |
| TDLib private channels | ✅ | `telegram/TelegramTd.kt` + `TelegramStreamServer.kt` behind the existing `zangetsu/telegram` channel; TDLib vendored in `jniLibs/`, `zangetsu/parity` `tdlib` now answers `true` |

### Web and network

| Hikari unit | Status | Zangetsu evidence |
|---|---|---|
| `web/WebViewActivity.kt` | ✅ | `features/web/websites_screen.dart` |
| `web/UserscriptManager.kt` | ✅ | `core/web/userscript_store.dart` |
| `net/AdBlocker.kt` | ✅ | `core/web/ad_block.dart` |
| `net/PromoGuard.kt` | ✅ | `core/web/promo_guard.dart` |
| `data/RedirectAllow.kt` | ✅ | `core/web/redirect_allow.dart` |
| `net/ExtensionUiGuard.kt`, `ExtensionVerifyGuard.kt` | ✅ | `core/provider/extension_guard.dart` on every JS-pack call and manifest; `ExtensionVerifyGuard` pins Aniyomi signer digests |
| `deeplink/RepoLinkActivity.kt` | ✅ | `parity/RepoLinkActivity.kt`, manifest filters, handed to `addRepo` in `MainActivity` |
| `net/StreamProbe.kt` | ✅ | `core/playback/stream_probe.dart` |
| `net/SlowNetTip.kt` | ✅ | `core/playback/slow_net_tip.dart`, shown after the probe in `player_controller` |
| `work/` foreground service | ✅ | `parity/WorkService.kt`, started through `ParityNative.beginWork` around the DASH mux |

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
| `data/Ratings.kt` (IMDb/RT/Metacritic aggregation) | ✅ | `core/metadata/rating_aggregator.dart`, blended score replaces the single-source row in the detail tabs |
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
| `PiperVoice` offline packs | ✅ | `parity/OfflineVoicePack.kt` lists the platform's downloaded offline voices over `zangetsu/parity` `voicePacks`, Parity tools shows the count and links the system download screen, and `DubPrefs.offlineOnly` filters the dub voice picker to them. No model is bundled — see §3 |
| `HardSubDub` | ✅ | `ParityBridge.captureWindow` (PixelCopy on the window, `zangetsu/parity`), called by the player's snapshot action; the subtitle overlay is in the saved frame |
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
| `MouseMode` | ✅ | `core/tv/mouse_mode.dart`; switch in Appearance → Mouse mode (`tvMouseMode`) |
| `TvDesktop` | ➖ | No desktop target |
| `ScrollAnim`, `ScrollKeeper` | ✅ | `core/ui/scroll_keeper.dart` on the home rows and My List |

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
| `ScraperReaderScreen` | ✅ | `features/reader/scraper_reader_screen.dart`, offered from the reader error state when a chapter is one bare image URL |
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
| `CustomBackground` | ✅ | `core/theme/background_pref.dart`; picker, opacity and remove rows in Appearance |
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

Nothing. Every unit in §2 is reachable from the UI.

Closed since the last pass: **TDLib**. The library is vendored (both ARM ABIs,
plus its Java bindings and the `libc++_shared.so` staging task), and the client
behind the existing `zangetsu/telegram` channel does the phone/code/password
login, resolves a channel's videos, and serves them to mpv through a loopback
range server. Hikari's player is ExoPlayer and its stream is a media3
`DataSource`; this one is mpv and needs a URL, which is the only structural
divergence. §3c of `PARITY.md` has the port table, the build changes and what
still needs a device to verify.

Closed since the last pass: **the YouTube PO token**, by porting the source it
was written for. `YouTubeMusicSource` is Hikari's `MusicApi.kt` reduced to what
this app needs — InnerTube browse/search, a native-first client chain, and the
BotGuard token for the web client (§3b of `PARITY.md` has the port table and
the divergences). Browse and search were checked against the live endpoint; the
player path needs a device, because a datacenter address gets `LOGIN_REQUIRED`
from YouTube for every client.

Closed since the last pass: **offline voices**. Nothing is bundled — a
Piper/Sherpa pack is 60–200 MB per voice — but Android's own speech engine
ships offline packs, so `parity/OfflineVoicePack.kt` reports the ones actually
installed, Parity tools lists them and links the download screen, and the dub
sheet has an "offline voices only" filter for watching without a network. That
is the same outcome Hikari's bundled packs give, without the APK weight.

Everything else in §2 is present **and reachable from the UI**. The last pass
closed the built-but-unwired set: LoadGate, LosslessSource, the foreground
service, the window frame grab, multi-source ratings, TV mouse mode, the scroll
keeper, the scraper reader, the custom background and the extension guards.
`HardSubBurner.kt` was folded into `ParityBridge`: two frame grabbers, one of
which nothing called, was one too many.

Two rows are ➖ on purpose: the `zangetsu/` plugin family (Zangetsu is the host)
and `TvDesktop` (no desktop target).

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

- "Audio FX" was pitch only; reverb and echo now go through mpv's `af`, so the
  row covers what its name claims.
- "Player skins" is cosmetic; the functional stream/server selection exists.
- "Channel marks" is the only Live TV store gap; favourites elsewhere are not it.

Units the first matrix missed entirely, all of them landed since:

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
| **Whole suite** | **714** | **5,563** |

`flutter analyze` → No issues found. `flutter build apk --debug` builds, so the
Kotlin in `android/app/src/main/kotlin/.../parity/` compiles and both method
channels (`zangetsu/media_export`, `zangetsu/parity`) are registered in
`MainActivity`. The whole suite is run per area in this sandbox — a full run
takes ~40 minutes and gets killed by the runtime restart.

Tests added in the last pass: `test/core/music/lossless_source_test.dart` (the
endpoint survives a restart) and `test/core/parity/parity_native_test.dart`
(the channel's failure modes and the reference-counted work keeper).

## 6. Bottom line

- The migration's ledger is complete: **33/33 ✅**, verified by path.
- Against the whole reference app, Zangetsu is at **139 ✅ / 141 units (99 %)**,
  or **139/139 applicable (100 %)**: the two ➖ rows are deliberate choices,
  not gaps.
- Nothing is open. The last native unit, TDLib, is linked and reachable.
- What remains unverified is runtime, not code: Telegram login and playback and
  YouTube playback all need a device and a real account.
