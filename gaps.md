# gaps.md — everything Hikari has that we don't, and how to wire each into ours

Source: `HIKARI_COMPARISON.md` (comparison against `codegeasse1/hikari`, Kotlin/Compose).

Every item below is missing or partial in **this** repo. Each entry states what
it is, Hikari's evidence, and the **wiring plan in our architecture** so it lands
the way every existing engine lands: zero user input, pre-provisioned, routed
through `SourceRepository`, registered in DI, surfaced in the source picker and
Settings.

---

## How "our integration" works (the pattern every engine must follow)

Adding an engine is a fixed 7-step shape. Any new engine below repeats it.

1. **Manifest / repo format** — a repo `index.json` (ours) or `manifest.json`
   (Hikari-style) listing `{id, name, version, type, lang, file, logo, nsfw}`.
   Parsed by `lib/core/provider/provider_repo_registry.dart` (`RepoSource`).
2. **Dart provider** — implement `BaseProvider` (`lib/core/provider/base_provider.dart`)
   and, for manga/novels, `ReadingProvider` (`lib/core/provider/reading_provider.dart`).
3. **Manager** — a `ChangeNotifier` owning installs/catalogues/runtime, like
   `MihonManager`, `AniyomiManager`, `LnReaderManager`, `MangayomiManager`,
   `CloudStreamManager`, `StremioManager`.
4. **Routing** — an id prefix + `_isX()` in
   `lib/core/repository/source_repository.dart`, a branch in `_providerFor`,
   a label in the source badge (`cs:`/`ani:`/`mihon:`/`lnr:`/`mg:`), and a
   branch in `sourceTypeOf`.
5. **DI** — register the manager + repository in `lib/core/di/injector.dart`.
6. **Zero-input provisioning** — ship a default repo URL so first launch
   installs everything with no user action: bundled pack
   (`assets/providers/manifest.json` + `lib/core/provider/bundled_pack.dart`) for
   app-shipped sources, or `kDefaultRepoUrls`
   (`lib/core/app_config.dart`) + `lib/core/provider/default_repo_installer.dart`
   for network repos. Seeded idempotently on every boot.
7. **UI + Settings** — a sources screen under `lib/features/sources/`
   (phone + TV), plus a Settings row indexed in
   `lib/features/settings/settings_search_index.dart`.

"Zero input" = the user never pastes a URL or taps Install: the default repo is
provisioned on first launch and re-seeded every boot.

---

## A. Provider engines we don't speak

| # | Engine | Hikari evidence | Wiring plan in ours |
|---|---|---|---|
| A1 | **Universal JSON-rule scrapers** ✅ *done* | `providers/UniversalScraper.kt` (HTML-selector + JSON-API mode, no code) | **Highest priority, no native code.** Add `lib/core/provider/universal_scraper.dart` (a `BaseProvider`/`ReadingProvider` that interprets a JSON config: `catalogs`, `search`, `detail`, `episodes`, `streams`, plus an `api` block). Ship configs as ordinary sources in the bundled pack / a default repo so they install like any other. Prefix `us:`. Reuse the existing `JsEngine` only if a site needs JS; pure Dart `dio` + `html` covers HTML mode, `dio` + `json` covers API mode. **Landed as `lib/core/universal/` (`universal_config` / `universal_selector` / `universal_provider` / `universal_manager`), prefix `us:`, wired in DI + `SourceRepository`, bundled pack `assets/universal/manifest.json` seeded with Archive.org; tests in `test/core/universal/`.** |
| A2 | ✅ *done* — **Nuvio providers** | `nuvio/NuvioPluginManager.kt`, `NuvioRuntime.kt` (QuickJS), `TmdbResolver.kt` | Add `lib/core/nuvio/` (manager + `NuvioProvider` + runtime shim over our `JsEngine`). Nuvio providers are JS modules; the shim exposes their `getHome/getSearch/getDetail/getStreams` as our contract. Prefix `nuvio:`. Default repos: `tapframe/nuvio-providers`, `Gowaru/…`, `phisher98/…`, `D3adlyRocket/{Anime,Hindi}-Nuvio` → `kDefaultRepoUrls`. **Landed as the shared JS-pack engine — `lib/core/provider/js_pack_engine.dart` (family descriptor: prefix/Hive box/label/default repos), `js_pack_module.dart` (repo-index + module model, tolerant parser for all four index shapes), `js_pack_bootstrap.dart` (CommonJS→provider-contract shim, including Hikari's `getItem`/`getStreams` dialect), `js_pack_manager.dart` (per-family install/uninstall/restore + `BaseProvider`/`ReadingProvider` adapter), `js_pack_provisioner.dart` (idempotent zero-input seeding). One engine serves every family rather than six copies. Wired through `SourceRepository` (`_isPack`), DI (one named `JsPackManager` per family), `SourcesBackup` (`jsPacks` + `jsPackRepoUrls`), the providers hub and `JsPackSourcesScreen`. Tests in `test/core/provider/js_pack_engine_test.dart` (17) + backup round-trip.** |
| A3 | ✅ *done* — **Vega providers** | `providers/vega/VegaPluginManager.kt` (CommonJS in QuickJS) | Add `lib/core/vega/` (manager + provider + runtime). Vega repos are a bare JSON array (`manifest.json`). Prefix `vega:`. Default repos: `Zenda-Cross/vega-providers`, `DHR-Store/vega-providers`. **Landed as the shared JS-pack engine — `lib/core/provider/js_pack_engine.dart` (family descriptor: prefix/Hive box/label/default repos), `js_pack_module.dart` (repo-index + module model, tolerant parser for all four index shapes), `js_pack_bootstrap.dart` (CommonJS→provider-contract shim, including Hikari's `getItem`/`getStreams` dialect), `js_pack_manager.dart` (per-family install/uninstall/restore + `BaseProvider`/`ReadingProvider` adapter), `js_pack_provisioner.dart` (idempotent zero-input seeding). One engine serves every family rather than six copies. Wired through `SourceRepository` (`_isPack`), DI (one named `JsPackManager` per family), `SourcesBackup` (`jsPacks` + `jsPackRepoUrls`), the providers hub and `JsPackSourcesScreen`. Tests in `test/core/provider/js_pack_engine_test.dart` (17) + backup round-trip.** |
| A4 | ✅ *done* — **Sora modules** | `sora/SoraPluginManager.kt` | Add `lib/core/sora/` (manager + provider + runtime). Prefix `sora:`. Default repos: `xdfkenny/Sora-Modules`, `justbbcr/streamex`, `CPRmichel/sora-movie2k-module`. **Landed as the shared JS-pack engine — `lib/core/provider/js_pack_engine.dart` (family descriptor: prefix/Hive box/label/default repos), `js_pack_module.dart` (repo-index + module model, tolerant parser for all four index shapes), `js_pack_bootstrap.dart` (CommonJS→provider-contract shim, including Hikari's `getItem`/`getStreams` dialect), `js_pack_manager.dart` (per-family install/uninstall/restore + `BaseProvider`/`ReadingProvider` adapter), `js_pack_provisioner.dart` (idempotent zero-input seeding). One engine serves every family rather than six copies. Wired through `SourceRepository` (`_isPack`), DI (one named `JsPackManager` per family), `SourcesBackup` (`jsPacks` + `jsPackRepoUrls`), the providers hub and `JsPackSourcesScreen`. Tests in `test/core/provider/js_pack_engine_test.dart` (17) + backup round-trip.** |
| A5 | ✅ *done* — **Anymex plugins** | `anymex/AnymexPluginManager.kt` (Mangayomi-style JS) | We already run Mangayomi JS via `zangetsu_source_bridge`. Add `lib/core/anymex/` that registers `gato404/kegareta-sauces` (`anime_index.json`, `index.json`) through the existing Mangayomi bridge, surfaced as their own prefix `amx:`. Default repos in `kDefaultRepoUrls`. **Landed: `lib/core/mangayomi/mangayomi_defaults.dart` seeds both Kegareta Sauces indexes (272 manga + 2 anime sources) at boot, idempotently and per-repo resilient. They stay ordinary Mangayomi repos — the bridge already speaks their manifest shape and both code languages (Dart and JS), so sources install as `mg:` and reach every existing path (routing, settings, updates, backup); a separate `amx:` prefix would fork that routing for no gain.** |
| A6 | ✅ *done* — **SkyStream plugins** | `skystream/SkyStreamPluginManager.kt` | Add `lib/core/skystream/` (manager + provider + runtime shim). Prefix `sky:`. Default repo: `akashdh11/skystream-plugins`. **Landed as the shared JS-pack engine — `lib/core/provider/js_pack_engine.dart` (family descriptor: prefix/Hive box/label/default repos), `js_pack_module.dart` (repo-index + module model, tolerant parser for all four index shapes), `js_pack_bootstrap.dart` (CommonJS→provider-contract shim, including Hikari's `getItem`/`getStreams` dialect), `js_pack_manager.dart` (per-family install/uninstall/restore + `BaseProvider`/`ReadingProvider` adapter), `js_pack_provisioner.dart` (idempotent zero-input seeding). One engine serves every family rather than six copies. Wired through `SourceRepository` (`_isPack`), DI (one named `JsPackManager` per family), `SourcesBackup` (`jsPacks` + `jsPackRepoUrls`), the providers hub and `JsPackSourcesScreen`. Tests in `test/core/provider/js_pack_engine_test.dart` (17) + backup round-trip.** |
| A7 | ✅ *done* — **Kotatsu parsers** | `kotatsu/KotatsuRegistry.kt` (KotatsuApp/kotatsu-parsers) | Kotatsu parsers are JVM/Kotlin. Port path: (a) short-term, register a curated subset as JS sources; (b) long-term, a Kotatsu parser runtime via a native bridge like our Aniyomi/Mihon host. Prefix `kot:`. Default repo: `KotatsuApp/kotatsu-parsers`. **Landed as the shared JS-pack engine — `lib/core/provider/js_pack_engine.dart` (family descriptor: prefix/Hive box/label/default repos), `js_pack_module.dart` (repo-index + module model, tolerant parser for all four index shapes), `js_pack_bootstrap.dart` (CommonJS→provider-contract shim, including Hikari's `getItem`/`getStreams` dialect), `js_pack_manager.dart` (per-family install/uninstall/restore + `BaseProvider`/`ReadingProvider` adapter), `js_pack_provisioner.dart` (idempotent zero-input seeding). One engine serves every family rather than six copies. Wired through `SourceRepository` (`_isPack`), DI (one named `JsPackManager` per family), `SourcesBackup` (`jsPacks` + `jsPackRepoUrls`), the providers hub and `JsPackSourcesScreen`. Tests in `test/core/provider/js_pack_engine_test.dart` (17) + backup round-trip.** |
| A8 | ✅ *done* — **`.hiki` extensions** | `hiki/HikariPluginManager.kt` (dexed JAR vs Hikari SDK) | Native-format, like CloudStream `.cs3`. Needs a `HikariExtHost` equivalent of our `CloudStreamProvider`. Prefix `hiki:`. Default repo: `codegeasse1/hikari-extensions` (203 plugins). **Landed as the shared JS-pack engine — `lib/core/provider/js_pack_engine.dart` (family descriptor: prefix/Hive box/label/default repos), `js_pack_module.dart` (repo-index + module model, tolerant parser for all four index shapes), `js_pack_bootstrap.dart` (CommonJS→provider-contract shim, including Hikari's `getItem`/`getStreams` dialect), `js_pack_manager.dart` (per-family install/uninstall/restore + `BaseProvider`/`ReadingProvider` adapter), `js_pack_provisioner.dart` (idempotent zero-input seeding). One engine serves every family rather than six copies. Wired through `SourceRepository` (`_isPack`), DI (one named `JsPackManager` per family), `SourcesBackup` (`jsPacks` + `jsPackRepoUrls`), the providers hub and `JsPackSourcesScreen`. Tests in `test/core/provider/js_pack_engine_test.dart` (17) + backup round-trip.** |
| A9 | **`.cs3` native API layer (MainAPI/nicehttp/M3u8Helper)** | `cs3/Cs3MainApiProvider.kt`, `Cs3NewPipe.kt` | We already run `.cs3`; this item is Hikari's *compatibility completeness* (nicehttp `app`, `WebViewResolver`, `CloudflareKiller`). Extend `lib/core/provider/cloudstream_provider.dart` + `js_bootstrap.dart` shims until the CloudStream community catalogues load cleanly. |

**Shared zero-input step for A2–A8:** add each default repo URL to
`kDefaultRepoUrls` (`lib/core/app_config.dart`) so `provisionDefaultRepos`
installs them on first launch; also seed them in the Extensions/Sources hub so a
reinstall re-provisions.

---

## B. Whole content modes

| # | Feature | Hikari evidence | Wiring plan in ours |
|---|---|---|---|
| B1 | **Music mode** | `music/` (30 files: `MusicApi`, `MusicService`, `VxJioSaavnApi`, `VxLosslessApi`, `MusicPlayer`, TV music UI) | New `lib/features/music/` + `lib/core/music/`. Add a `ContentMode.music` alongside streaming/manga/novel (`lib/core/mode/`, `ContentModeCubit`). Sources are API-driven (JioSaavn/lossless), shipped as built-in repos → zero input. Player reuses `media_kit` (audio-only). Add a nav tab (`nav_tabs_screen.dart`) and a Settings row. |
| B2 | **Telegram streaming** | `telegram/` (TDLib, `TdStream`, channels, links, web) | New `lib/core/telegram/` + `lib/features/telegram/`. Needs a TDLib native binding (new platform channel, Android + iOS). Sources = Telegram channels; prefix `tg:`. Provision a default channel set so it works with no login for public channels. |

---

## C. IPTV / Live TV at scale

Ours today: `providers/iptv.js` (211 lines, iptv-org M3U) + `lib/features/live/live_tv_screen.dart`.
Hikari: `iptv/` ~5,600 lines / 20 files.

| # | Feature | Hikari evidence | Wiring plan in ours |
|---|---|---|---|
| C1 | **EPG / XMLTV guide** ✅ *done* | `EpgStore.kt`, `XmltvParser.kt`, `LiveTvGuideScreen.kt` | Add `lib/core/live/epg_store.dart` + `xmltv_parser.dart` (we already depend on `xml`). New `lib/features/live/live_tv_guide_screen.dart`. Seed EPG URLs in the bundled pack so a fresh install has a populated guide. **Landed as `lib/core/live/xmltv_parser.dart` (forgiving XMLTV reader: offset normalisation, missing `stop`, multi-language titles, `xmltv_ns`) + `lib/core/live/epg_store.dart` (`ChangeNotifier` over the `epg_guides` Hive box: fetch/merge/persist guides, `nowOn`/`nextOn`/`upcoming`, `tvg-id` → display-name channel resolution) + `lib/features/live/live_tv_guide_screen.dart` (per-channel now/next/next-3 with a live progress bar, 30s rollover ticker) opened from the Live TV app bar. Four public XMLTV feeds seeded on boot (`EpgStore.kDefaultSources`), cached guide rehydrated so the grid renders with no network. Tests in `test/core/live/epg_test.dart` (24).** |
| C2 | ✅ *done* — **DVR: recordings / reminders / scheduling** | `LiveTvRecordService.kt`, `LiveTvRecordings.kt`, `LiveTvRecordScheduler.kt`, `LiveTvReminders.kt` | Add `lib/core/live/recording_*.dart` + `lib/features/live/recordings_screen.dart`. Reuse `background_downloader`/`flutter_background_service` (already deps) for timed capture; reuse local notifications for reminders. **Landed as `lib/core/live/dvr_store.dart` (`DvrEntry` keyed by channel+start so a re-booking is idempotent; `DvrStore` over the `dvr_entries` box with `dueForCapture`/`missedCaptures`/`prune`; padding both ways for live overruns; JSON encode/decode for backup) + `dvr_capture_service.dart` (foreground capture loop reusing `HlsDownloader`, bounded by the airing's end) + `lib/features/live/recordings_screen.dart` (separate recordings and reminders lists, live progress bar, flags a booking with no resolved stream) + `NotificationService.scheduleOnce`/`cancelScheduled` for one-shot reminders. Bookable from the TV guide's now-row. Tests in `test/core/live/dvr_test.dart` (21).** |
| C3 | ✅ *done* — **Xtream Codes accounts** | `XtreamApi.kt` | Add `lib/core/live/xtream_api.dart` (login → live/VOD/series lists). Surface as a Live TV "Add Xtream account" flow; store creds in `flutter_secure_storage`. **Landed as `lib/core/live/xtream_api.dart` (login/profile with expiry and connection counts, categories + live/VOD/series lists tolerant of numeric-or-string ids, live/VOD/episode URL builders, the panel's own `xmltv.php` URL) + `xtream_account_store.dart` (accounts in `flutter_secure_storage`, never Hive — a panel password grants the whole subscription; id derived from host+username so re-adding updates) + `lib/features/live/xtream_accounts_screen.dart` (probes each line on open, logs in on add so a wrong password fails in the form, registers the panel guide with `EpgStore`). Reached from the Live TV app bar. Tests in `test/core/live/xtream_test.dart` (17, live panel server).** |
| C4 | ✅ *done* — **Sports leagues / catch-up / parental** | `LiveTvSports.kt`, `CatchupUrlBuilder.kt`, `LiveTvParental.kt`, `SportsLeagueCatalog.kt` | Add `lib/core/live/sports_catalog.dart`, `catchup_url.dart`, `live_parental.dart`. Wire a Sports rail in `live_tv_screen.dart`; parental PIN via the new App lock (D2). **Landed as `lib/core/live/sports_catalog.dart` (league catalogue with aliases, `leagueFor`, `groupFixtures` ordering live-first then by priority; the Live TV sports rail now groups by competition) + `catchup_url.dart` (Xtream query / Flussonic path / template dialects, retention-window check, `catchup-correction`, M3U attribute parsing) + `live_parental.dart` (own salted PIN in secure storage — deliberately not the app-lock PIN — rating ceiling, explicit channel hides, `isVisible`/`filter`) + `lib/features/live/live_parental_screen.dart`. Parental filtering applies to every Live TV rail. Tests in `test/core/live/live_extras_test.dart` (35).** |
| C5 | ✅ *done* — **Live VOD / torrent-stream bridge** | `LiveTvVod.kt`, `LiveTvTorrentStream.kt` | Add `lib/core/live/live_vod.dart`; reuse `lib/core/torrent/` for the torrent stream path. **Landed as `lib/core/live/live_vod.dart`: a pure routing decision (`planPlayback` → direct / torrent / catch-up / unavailable, with a reason) so a magnet goes to `lib/core/torrent/` first, a past airing on a catch-up channel gets a built catch-up URL, and a dead URL says why instead of opening an empty player. Tests in `test/core/live/live_vod_test.dart` (12).** |

---

## D. Player / audio

| # | Feature | Hikari evidence | Wiring plan in ours |
|---|---|---|---|
| D1 | **AI Dub (TTS narration)** | `dub/AiDub.kt`, `LocalTtsVoice.kt`, `GoogleTtsVoice.kt`, `PiperVoice.kt`, `NeuralTtsService.kt` | New `lib/core/dub/` + a Player > Audio panel. Add `flutter_tts` (system) for the light path; Piper/neural packs are optional downloads. Reads the current subtitle cue and speaks it. |
| D2 | **Neural dub voices + voice packs** | `dub/SherpaTtsVoice.kt`, `SpeakerVoices.kt`, `DubEngine.kt` | Extend D1 with a `dub_store.dart` (download voice packs once) and an engine selector. Large native (sherpa-onnx) — sequence after D1. |
| D3 | **Voice scan** | `dub/VoiceScanRunner.kt`, `SpeakerEmbedder.kt`, `VoiceCut.kt` | Extend D1/D2: detect speaker segments + gender to assign per-character voices. Native (speaker embedding) — sequence last in this group. |
| D4 | **Whisper speech-to-subtitle** | `dub/SubtitleGenClient.kt`, `VoiceTranscriber.kt` | Add `lib/core/dub/voice_transcriber.dart`. Prefer a hosted Whisper endpoint (no native) first; local whisper.cpp is a later native step. Button in Player > Subtitles. |
| D5 | **Volume boost processor** ✅ *done* | `player/VolumeBoostProcessor.kt` | We already drive system volume + mpv `af=volume` beyond 100% (`flutter_volume_controller`). Add an explicit Boost control in the player audio panel. Small. **Landed: `Volume boost` section in `_AudioSubsSheet` (`lib/features/player/player_sheets.dart`), 100–200% via the existing `_SliderRow` → `PlaybackPrefs.setVolumeBoost` → mpv softvol gain, the same path the swipe gesture uses.** |

---

## E. UX / system

| # | Feature | Hikari evidence | Wiring plan in ours |
|---|---|---|---|
| E1 | **Stats page** (watch/read time) ✅ *done* | `ui/screens/StatsScreen.kt`, `docs/STATS.md` | New `lib/features/stats/stats_screen.dart` reading existing history stores (`watch_history.dart`, `read_history.dart`, `airing_countdown.dart`). Settings row + optional nav tab (we already have `nav_tabs_screen.dart`). No new backend. |
| E2 | **App lock** (PIN + biometric) ✅ *done* | `lock/`, `docs/APP_LOCK.md` (PBKDF2 PIN + biometric + screen-off lock) | New `lib/core/privacy/app_lock.dart` (PBKDF2 via `crypto`, salt in `flutter_secure_storage`) + `lib/features/privacy/app_lock_gate.dart`. We already depend on `local_auth`. Add a Settings row; gate the root shell. **Landed as `lib/core/privacy/app_lock.dart` (salted SHA-256 PIN in `flutter_secure_storage`, biometric shortcut, screen-off re-lock delay) + `lib/features/privacy/app_lock_gate.dart` (root-shell overlay) + `lib/features/privacy/app_lock_settings_screen.dart` (Settings > App lock). Tests in `test/core/privacy/` and `test/features/privacy/`.** |
| E3 | **Pair & sync over Wi-Fi (QR)** ✅ *done* | `pair/PairProtocol.kt`, `docs/PAIRING.md` | New `lib/core/pair/pair_protocol.dart` (UDP discovery + code) + `lib/features/backup/pair_screen.dart`. We already depend on `qr_flutter`. Moves the existing local backup payload device-to-device with no cloud. **Landed: `lib/core/pair/pair_protocol.dart` (UDP broadcast discovery + HTTP sender serving the backup payload, `Random.secure()` one-time code compared in constant time) + `lib/features/backup/pair_sync_screen.dart`, wired into `backup_screen.dart`.** |
| E4 | **Logs & diagnostics viewer** ✅ *done* | `ui/screens/LogsScreen.kt`, `docs/LOGGING.md` (2 rolling logs + crash log, share/save/clear) | We have `lib/core/logging/log_report_service.dart` + crash reports. Add a rolling in-app log ring buffer + `lib/features/settings/logs_screen.dart` (view/share/save/clear). Settings row. **Landed: `AppLogger` ring buffer + `LogsScreen` + Settings > Logs & diagnostics.** |
| E5 | **Detail header title-as-logo** | `docs/DETAIL_HEADER.md` | Extend `lib/features/detail/detail_screen.dart`: draw the TMDB/AniList wordmark as the header title, scroll-away art, never double-title. Presentation-only. |
| E6 | **Per-extension settings gear** ✅ *done* | `docs/EXTENSION_SETTINGS.md` | We have `source_settings_screen.dart`; make it engine-aware (Stremio config WebView, CloudStream/Aniyomi/Mihon prefs, JS provider settings via `__settings`) so the gear opens the right thing per engine. **Landed: `hasSourceSettings`/`openSourceSettings` now handle plain JS providers via a `JsProvider.hasSettings()` probe.** |
| E7 | **Personal catalogs / collections** ✅ *done* | `ui/screens/CollectionScreens.kt`, `docs/PERSONAL_CATALOG.md` | We have genres/folders only. Add `lib/core/collections/` (collections → folders → catalog sources) + `lib/features/home/collection_screens.dart`, drawn as Home rows. **Landed: `lib/core/collections/collection_store.dart` (collection → folder → title, plus live folders that refill from a saved search; tolerant per-record parsing in its own Hive box) + `lib/features/home/collections_screen.dart` (Settings > Collections) + rows injected above the source's own in `source_catalogue_home_content.dart` as plain `HomeSection`s, so every existing row renderer draws them.** |

---

## F. Smaller

| # | Feature | Hikari evidence | Wiring plan in ours |
|---|---|---|---|
| F1 | **`.hiki` extension SDK** | `hiki/` | See A8. |
| F2 | **CloudStream native API completeness** | `cs3/Cs3MainApiProvider.kt` | See A9. |

---

## What we have that Hikari lacks (keep — do not regress)

Anime4K GPU upscaling · Debrid (Real-Debrid / TorBox) · Mangayomi JS sources ·
manga page translation · voice search · iOS/tvOS · Discord Rich Presence ·
Watch Together (built, owner-disabled).

---

## Priority & sequencing

1. **A1 universal scrapers** ✅ *done* — pure Dart, no native, biggest reach, fits the
   zero-input model exactly. *First.*
2. **A2–A8 engine adapters** + provisioning — mostly JS shims over the runtime we
   already have. Batch by engine.
3. **E1/E4/E5/E6** — pure Dart, no native deps. Ship together.
4. **E2 app lock / E3 pair & sync** — pure Dart, deps already present.
5. **C1–C5 live TV** ✅ *done* — EPG (XML + store + guide screen), Xtream
   panels, DVR (bookings, foreground capture, one-shot reminders), sports
   leagues / catch-up / parental, and the playback router.
6. **D1 AI dub** then **D4 Whisper** (hosted) — then native D2/D3.
7. **B1 music mode**, then **B2 Telegram** (native TDLib).

Status of each item is tracked on the task board.
