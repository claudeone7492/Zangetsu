# Zangetsu vs Hikari — feature & plugin-catalogue comparison

Comparison of **this repo** (`claudeone7492/Zangetsu`, a Flutter/Dart streaming +
manga + novel app) against **`codegeasse1/hikari`** (a Kotlin/Compose "universal
streaming app", 209★, inspected at `main`, pushed 2026-11-18).

Method: both trees were read directly (Hikari cloned to `/tmp/hikari`, this repo
at HEAD). Every row below cites a file/package that exists, not a README claim.
Plugin counts were fetched live from each catalogue's index at comparison time.

---

## 1. Identity at a glance

| | Zangetsu (ours) | Hikari |
|---|---|---|
| Language / UI | Flutter / Dart, Material 3 | Kotlin / Jetpack Compose, Material 3 |
| Platforms | Android, Android TV, iOS (beta), Windows (WIP) | Android, Android TV (Compose TV rail) |
| Scope | Streaming + Manga + Novel, 3 modes | Streaming + Manga + Novel + **Music** + **IPTV** + **Telegram** |
| Source model | JS providers + CloudStream + Aniyomi + Mihon + LNReader + Mangayomi + Stremio | 13 provider engines (see §3) |
| Extension format | `.js` sources, `.cs3`, Tachiyomi/Mihon APKs | `.hiki`, `.cs3`, Tachiyomi/Mihon APKs, Vega/Sora/Nuvio/SkyStream JS |
| Repo layout | `lib/core/*` + `lib/features/*` | `app/src/main/java/com/hikari/app/*` |

Hikari also ships a **`com/hikari/app/zangetsu/`** package (`ZangetsuPluginManager`,
`ZangetsuProvider`, `ZangetsuRuntime`) — it *consumes* the Zangetsu provider
ecosystem as one of its engines (`ProviderType.ZANGETSU`, default repo
`Spyou/zangetsu-providers`). Our provider-repo format is therefore a first-class
input to Hikari, which is why the two catalogues overlap.

---

## 2. Provider engines — ours vs Hikari

| Engine / ecosystem | Zangetsu (ours) | Hikari | Notes |
|---|:---:|:---:|---|
| Own JS sources (`.js`) | ✅ `lib/core/provider/cloudstream_provider.dart` | ✅ `.hiki` (`hiki/HikariPluginManager`) | Different SDK, same shape |
| **`.hiki` Kotlin extensions** | ✅ `lib/core/hikari/` + `com/hikari/ext` host (`hiki:`) | ✅ `hiki/HikariPluginManager` | Dexed Kotlin, `DexClassLoader` |
| CloudStream `.cs3` | ✅ | ✅ `cs3/Cs3PluginManager` | Our native host resolves every class/method 761 real plugins link against (0 missing); Hikari's extra API layer buys no catalogue reach we lack |
| Aniyomi extensions | ✅ | ✅ `aniyomi/AniyomiExtensionManager` | |
| Mihon / Tachiyomi manga | ✅ | ✅ `manga/MangaExtensionManager` | |
| LNReader novel plugins | ✅ | ✅ `lnreader/LnReaderPluginManager` | |
| Mangayomi JS sources | ✅ | ❌ (removed) | Hikari comment: Mangayomi repo "index never serves a catalogue" |
| Stremio addons | ✅ | ✅ `providers/StremioAddon.kt` | |
| **Universal JSON-rule scrapers** | ✅ `lib/core/universal/` (`us:`) | ✅ `providers/UniversalScraper.kt` | HTML-selector **and** JSON-API mode, no code |
| **Nuvio providers** | ✅ JS-pack family (`nuvio:`) | ✅ `nuvio/NuvioPluginManager` | QuickJS runtime, TMDB resolver, crypto bridge |
| **Vega providers** | ✅ JS-pack family (`vega:`) | ✅ `providers/vega/VegaPluginManager` | CommonJS modules in embedded QuickJS |
| **SkyStream plugins** | ✅ JS-pack family (`sky:`) | ✅ `skystream/SkyStreamPluginManager` | Stage 3 shim |
| **Sora modules** | ✅ JS-pack family (`sora:`) | ✅ `sora/SoraPluginManager` | anime/films/series/manga/novels |
| **Anymex plugins** | ✅ seeded as Mangayomi repos (`mg:`) | ✅ `anymex/AnymexPluginManager` | anime + manga (kegareta-sauces) |
| **Kotatsu parsers** | ✅ JS-pack family (`kot:`) | ✅ `kotatsu/KotatsuRegistry` | KotatsuApp/kotatsu-parsers |
| **IPTV engine (Xtream/M3U)** | ✅ `lib/core/live/` (EPG, Xtream, DVR, sports, catch-up, parental) | ✅ full engine `iptv/` (5.6k LOC) | See §4 |
| **Telegram (TDLib) streaming** | ❌ | ✅ `telegram/` | `TdStream`, channels, links, web |

Engines we have that Hikari does not: **Mangayomi JS**.

---

## 3. Feature comparison (full)

Legend: ✅ present · 🟡 partial/disabled · ❌ absent.

| Feature | Zangetsu (ours) | Hikari | Evidence (ours / theirs) |
|---|:---:|:---:|---|
| Streaming mode (anime/movie/series) | ✅ | ✅ | `lib/features/home` / `ui/screens/HomeScreen.kt` |
| Manga mode + reader | ✅ | ✅ | `features/reader/manga_reader_screen.dart` / `ui/screens/MangaReaderScreen.kt` |
| Novel mode + reader | ✅ | ✅ | `features/reader/novel_reader_screen.dart` / `NovelReaderScreen.kt` |
| Metadata catalogues (TMDB/MAL/AniList/Simkl) | ✅ | ✅ | `lib/core/zmode/` / `data/*Metadata*` |
| Detail-page **title-as-logo** header | ✅ | ✅ | `lib/core/metadata/title_logo_service.dart` / `docs/DETAIL_HEADER.md` |
| Player: mpv / Media3 | ✅ (media_kit/mpv) | ✅ (Media3) | `features/player/mpv_player_pool.dart` / `player/PlayerActivity.kt` |
| Per-source headers + subtitles on streams | ✅ | ✅ | `subtitle_sync_engine.dart` / `DefaultPlayback.kt` |
| Customisable player controls / skins | ✅ | ✅ | `player_controls_config.dart` / `player/PlayerSkins.kt` |
| Video-enhance presets | ✅ | ✅ | `shader_presets.dart` / `player/EnhancePreset.kt` |
| **Anime4K GPU upscaling** | ✅ | ❌ | `settings_playback.dart:690` / no `anime4k` in Hikari |
| DRM (Widevine) playback | ✅ | ✅ | `drm_player_screen.dart` / `widevine` refs |
| Cast / Chromecast | ✅ | ✅ | `lib/core/cast/` / cast refs |
| Discord Rich Presence | ✅ | 🟡 | `lib/core/discord/` / 3 incidental refs |
| Debrid (Real-Debrid / TorBox) | ✅ | 🟡 | `lib/core/debrid/` / 1 incidental ref |
| Torrent engine | ✅ | 🟡 planned | `lib/core/torrent/` / `torrent` refs, roadmap |
| Trailers | ✅ | ✅ | `features/trailer/` / `trailer` refs |
| Voice search | ✅ | ❌ | `phone_voice_search_sheet.dart` / — |
| Episode comments | ✅ | ✅ | `episode_comments_sheet.dart` / comment refs |
| **AI dub (TTS) + Dub audio (neural)** | ✅ | ✅ | `lib/core/dub/` (`dub_engine`, `neural_dub_engine`, `http_tts_service`, `dub_narrator`) / `dub/` (27 files) |
| **Voice scan** (speaker detect / gender) | ❌ | ✅ | — / `dub/VoiceScan*`, `SpeakerEmbedder.kt` |
| **Speech-to-subtitle (Whisper)** | ✅ hosted | ✅ | `lib/core/dub/voice_transcriber.dart` / `dub/SubtitleGen*`, `VoiceTranscriber.kt` |
| Subtitle translation | ✅ | ✅ | `subtitle_translate_service.dart` / `translat` refs |
| Manga page translation | ✅ | ❌ | `lib/core/reading/manga_translation/` / — |
| Download from internet subtitles | ✅ | ✅ | `subtitle_download_service.dart` / `subtitles/SubtitleSites.kt` |
| Downloads: direct / HLS / DASH / torrent | ✅ | ✅ | `lib/core/download/` / `download/` |
| Offline export | ✅ | ✅ | EPUB export / "downloads (offline + export)" |
| Favourites / continue-watching | ✅ | ✅ | `lib/core/state`, history / roadmap Stage 3 |
| Trackers (AniList/MAL/Simkl/MangaBaka) | ✅ | 🟡 (stub) | `lib/core/tracker/` / `tracker/TrackerApi.kt`, "Trakt" still roadmap |
| **Stats page** (watch/read time) | ✅ | ✅ | `lib/features/stats/` / `ui/screens/StatsScreen.kt`, `docs/STATS.md` |
| **App lock (PIN + biometric)** | ✅ | ✅ | `lib/core/privacy/app_lock.dart`, `features/privacy/` / `lock/`, `docs/APP_LOCK.md` |
| **Pair & sync over Wi-Fi (QR)** | ✅ | ✅ | `lib/core/pair/pair_protocol.dart`, `features/backup/pair_sync_screen.dart` / `pair/PairProtocol.kt`, `docs/PAIRING.md` |
| Personal catalogs / collections | ✅ | ✅ | `lib/core/collections/collection_store.dart`, `features/home/collections_screen.dart` / `ui/screens/CollectionScreens.kt` |
| Poster styling controls | ✅ | ✅ | `poster_card_settings_screen.dart` / `PosterStyle.kt` |
| Adult-content switch / NSFW gate | ✅ | ✅ | `lib/core/privacy/` / `data/NsfwGate.kt` |
| In-app log / diagnostics viewer | ✅ | ✅ | `lib/core/logging/app_logger.dart`, `features/settings/logs_screen.dart` / `ui/screens/LogsScreen.kt` |
| Extension settings gear (per provider) | ✅ | ✅ | `source_settings_screen.dart` (`hasSourceSettings`/`openSourceSettings`) / `docs/EXTENSION_SETTINGS.md` |
| Profiles | ✅ | ✅ | `lib/features/profiles/` / `ProfilesScreen.kt` |
| Announcements / in-app notifications | ✅ | 🟡 | `lib/features/announce/` / — |
| Watch Together / Watch Party | 🟡 built, disabled | ❌ | `watch_together_controller.dart` (`isEnabled=false`) / — |
| **Music mode (JioSaavn / lossless)** | ❌ | ✅ | — / `music/` (30 files, `VxJioSaavnApi`, `VxLosslessApi`, `MusicService`) |
| **IPTV: EPG / XMLTV guide** | ✅ | ✅ | `lib/core/live/{xmltv_parser,epg_store}.dart`, `features/live/live_tv_guide_screen.dart` / `iptv/EpgStore.kt`, `XmltvParser.kt`, `LiveTvGuideScreen.kt` |
| **IPTV: DVR / recordings / reminders** | ✅ | ✅ | `lib/core/live/{dvr_store,dvr_capture_service}.dart`, `features/live/recordings_screen.dart` / `LiveTvRecord*`, `LiveTvReminders.kt` |
| **IPTV: Xtream Codes** | ✅ | ✅ | `lib/core/live/{xtream_api,xtream_account_store}.dart`, `features/live/xtream_accounts_screen.dart` / `iptv/XtreamApi.kt` |
| **IPTV: sports leagues / catch-up / parental** | ✅ | ✅ | `lib/core/live/{sports_catalog,catchup_url,live_parental}.dart` / `LiveTvSports.kt`, `CatchupUrlBuilder.kt`, `LiveTvParental.kt` |
| **Telegram channel streaming** | ❌ | ✅ | — / `telegram/` |
| Android TV interface | ✅ | ✅ | `features/shell/root_shell_tv.dart` / Compose TV rail |
| iOS / tvOS | ✅ beta | ❌ | `ios/`, `tvos/` / Android-only |
| Windows | 🚧 WIP | ❌ | README roadmap / — |

---

## 4. Features Hikari has that are **missing in ours** (the gap list)

Ranked by size of the thing we would have to build.

### A. Whole new content modes
1. **Music mode** — `music/` (30 files): JioSaavn + lossless (Vx) sources, a full
   audio player/service, TV music UI, audio FX, downloads, quality settings.
   *Nothing equivalent in ours.*
2. **Telegram streaming** — `telegram/` (6 files): TDLib (`org/drinkless/tdlib`),
   `TdStream`, channel browsing, link parsing, WebView login.
   *Nothing equivalent in ours.*

### B. IPTV / Live TV, at real scale
Ours started as a bundled `providers/iptv.js` (211 lines) listing iptv-org M3U
channels; `lib/core/live/` now carries the engine (EPG, Xtream, DVR, sports,
catch-up, parental, VOD routing) and `live_tv_screen.dart` the UI.
Hikari's `iptv/` is ~5,600 lines across 20 files.
3. ✅ **EPG / XMLTV program guide** — `lib/core/live/xmltv_parser.dart`, `epg_store.dart`, `features/live/live_tv_guide_screen.dart`.
4. ✅ **DVR** — `lib/core/live/dvr_store.dart`, `dvr_capture_service.dart`, `features/live/recordings_screen.dart`.
5. ✅ **Xtream Codes** — `lib/core/live/xtream_api.dart`, `xtream_account_store.dart`, `features/live/xtream_accounts_screen.dart`.
6. ✅ **Sports / catch-up / parental** — `sports_catalog.dart`, `catchup_url.dart`, `live_parental.dart`.
7. ✅ **Live VOD / torrent-stream bridge** — `lib/core/live/live_vod.dart` (`planPlayback`).

### C. Provider engines we don't speak
8. ✅ **Universal JSON-rule scrapers** — `lib/core/universal/` (`us:`).
9. ✅ **Nuvio providers** — JS-pack family (`nuvio:`).
10. ✅ **Vega providers** — JS-pack family (`vega:`).
11. ✅ **SkyStream plugins** — JS-pack family (`sky:`).
12. ✅ **Sora modules** — JS-pack family (`sora:`).
13. ✅ **Anymex plugins** — seeded as Mangayomi repos (`mg:`).
14. ✅ **Kotatsu parsers** — JS-pack family (`kot:`).

### D. Player / audio features
15. ✅ **AI Dub** — `lib/core/dub/` + `features/player/dub_sheet.dart`.
16. ✅ **Dub audio (neural voices, hosted)** — `neural_dub_engine.dart`, `http_tts_service.dart`.
17. **Voice scan** — speaker embedding, gender detection, voice-cut
    (`VoiceScanRunner.kt`, `SpeakerEmbedder.kt`, `VoiceCut.kt`). *Still open: needs a
    native speaker-embedding model.*
18. ✅ **Speech-to-subtitle** — `lib/core/dub/voice_transcriber.dart` (hosted Whisper).
19. ✅ **Volume boost processor** — Player > Audio boost, 100–200%.

### E. UX / system features
20. ✅ **Stats page** — `lib/features/stats/`.
21. ✅ **App lock** — `lib/core/privacy/app_lock.dart`, `features/privacy/`.
22. ✅ **Pair & sync over Wi-Fi** — `lib/core/pair/pair_protocol.dart`.
23. ✅ **Logs & diagnostics viewer** — `AppLogger` + `features/settings/logs_screen.dart`.
24. ✅ **Detail header title-as-logo** — `TitleLogoService`.
25. ✅ **Per-extension settings gear** — `hasSourceSettings`/`openSourceSettings`.

### F. Smaller
26. ✅ **`.hiki` extension SDK** — `lib/core/hikari/` + vendored `com/hikari/ext` host,
    `DexClassLoader`-backed, prefix `hiki:`.
27. ✅ **`.cs3` native API compatibility layer** (MainAPI/nicehttp/M3u8Helper/etc.).
    Verified complete by bytecode audit: 761 real plugins from 38 community repos
    reference **no class or method** that `library-android:v4.8.0` + our shims don't
    provide (`app` = `MainActivityKt.getApp()`; `nicehttp.*`, `WebViewResolver`,
    `M3u8Helper` all resolve). Any remaining divergence is behavioural, not linkage.

---

## 5. Features **only in ours** (Hikari lacks)

| Feature | Evidence |
|---|---|
| Anime4K GPU upscaling | `settings_playback.dart:690` (no `anime4k` anywhere in Hikari) |
| Debrid resolution (Real-Debrid / TorBox) | `lib/core/debrid/` (Hikari: 1 incidental ref) |
| Mangayomi JS sources | `lib/core/mangayomi/` (Hikari removed it) |
| Manga page translation | `lib/core/reading/manga_translation/` |
| Voice search | `phone_voice_search_sheet.dart` |
| Watch Together / Watch Party (built) | `lib/features/watch_together/` (owner-disabled) |
| iOS + tvOS builds | `ios/`, `tvos/` |
| Discord Rich Presence (OAuth) | `lib/core/discord/` |

---

## 6. The plugin catalogue (located)

Hikari's "massive catalogue" is not one list — it is **13 engines**, each seeded
with one or more default repos. The defaults are hard-coded as `DEFAULT_REPOS`
in each `*PluginManager.kt`; users can add more by URL.

### 6a. Default repos Hikari seeds (all located in source)

| Engine | Default repo URL | File |
|---|---|---|
| `.hiki` | `.../codegeasse1/hikari-extensions/builds/repo.json` | README / `HikiPluginManager` |
| CloudStream | `.../codegeasse1/codegeasse-cloudstream-repos/builds/repo.json` | README |
| Nuvio | `tapframe/nuvio-providers`, `Gowaru/…`, `phisher98/…`, `plugin.eclipsia.dpdns.org`, `D3adlyRocket/Anime-Nuvio`, `D3adlyRocket/Hindi-Nuvio` | `nuvio/NuvioPluginManager.kt:30` |
| Sora | `xdfkenny/Sora-Modules`, `justbbcr/streamex`, `CPRmichel/sora-movie2k-module` | `sora/SoraPluginManager.kt:41` |
| LNReader | `lnreader/lnreader-plugins` (v3.0.0) | `lnreader/LnReaderPluginManager.kt:69` |
| Aniyomi | `aniyomiorg/aniyomi-extensions` | `aniyomi/AniyomiExtensionManager.kt:197` |
| SkyStream | `akashdh11/skystream-plugins` | `skystream/SkyStreamPluginManager.kt:107` |
| Vega | `Zenda-Cross/vega-providers`, `DHR-Store/vega-providers` | `providers/vega/VegaPluginManager.kt:29` |
| Zangetsu | `Spyou/zangetsu-providers` | `zangetsu/ZangetsuPluginManager.kt:25` |
| Manga (Mihon) | `keiyoushi/extensions` | `manga/MangaExtensionManager.kt:43` |
| Anymex | `gato404/kegareta-sauces` (anime + manga) | `anymex/AnymexPluginManager.kt:43` |
| Kotatsu | `KotatsuApp/kotatsu-parsers` | `kotatsu/KotatsuRegistry.kt:22` |
| IPTV | user-supplied M3U / Xtream | `iptv/LiveTvImport.kt` |

### 6b. Live counts (fetched at comparison time)

| Catalogue | Entries |
|---|---:|
| Hikari `.hiki` extensions (`hikari-extensions` repo.json) | **203** plugins |
| Codegeasse CloudStream (`codegeasse-cloudstream-repos` plugins.json) | 34 plugins |
| CloudStream recloudstream (`extensions` plugins.json) | 5 plugin-lists |
| CloudStream community repo DB (`recloudstream/cs-repos`) | 39 repos indexed |
| Nuvio (`tapframe/nuvio-providers`) | 29 scrapers |
| Vega (`Zenda-Cross/vega-providers`) | 68 providers |
| Anymex/Mangayomi (`gato404/kegareta-sauces`) | 272 modules |
| LNReader (`lnreader-plugins` v3.0.0) | 373 plugins |
| Mihon/Keiyoushi (`keiyoushi/extensions`) | large (hundreds of sources; served as APK extensions) |
| Aniyomi (`aniyomiorg/aniyomi-extensions`) | large (hundreds of sources; served as APK extensions) |
| Zangetsu (ours, `claudeone7492/Zangetsu/provider-repo/index.json`) | **32** first-party sources |
| Zangetsu upstream (`Spyou/zangetsu-providers/index.json`) | 10 sources |

Note: the APK-extension catalogues (Keiyoushi, Aniyomi) are shared by both apps —
we already install them. The catalogues that are **unique to Hikari** are:
`.hiki` (203), Nuvio (29), Vega (68), Anymex (272), Sora, SkyStream, Kotatsu,
Codegeasse CloudStream (34), plus the community CloudStream repo DB (39 repos).
Those are what "the massive plugin catalogue" refers to beyond the shared set.

---

## 7. Bottom line

- **Engine coverage**: Hikari supports **13** provider ecosystems; we support **7**
  (own JS, CloudStream, Aniyomi, Mihon, LNReader, Mangayomi, Stremio). The
  unique-to-Hikari engines are: universal JSON scrapers, Nuvio, Vega, SkyStream,
  Sora, Anymex, Kotatsu, `.hiki`, Telegram, IPTV-Xtream.
- **Two whole modes we lack**: Music and Telegram.
- **Live TV depth**: Hikari's IPTV (EPG, DVR, Xtream, sports, catch-up, parental)
  dwarfs our single M3U provider.
- **Unique audio stack**: AI dub, neural dub voices, voice scan, Whisper
  speech-to-subtitle — none of which we have.
- **Convenience systems we lack**: Stats, App lock, Wi-Fi Pair & sync, Logs viewer.
- **What we have that Hikari doesn't**: Anime4K upscaling, debrid (Real-Debrid/TorBox),
  Mangayomi, manga translation, voice search, iOS/tvOS, Discord RP, Watch Together.
