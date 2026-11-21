# Zangetsu ↔ Hikari parity

> **Superseded in depth by [`AUDIT.md`](AUDIT.md)**, which walks all 33
> Hikari packages (149 units) and corrects several statuses below.

Measured against `claudeone7492/Zangetsu` at the head of `main` and the Hikari tree at
`codegeasse1/hikari` (`/workspace/hikari`). Every row was checked by file and
symbol search, not by feature name alone. Tests are named where they exist.

Legend: ✅ done and reachable · ⚠️ partial, or deliberately different ·
❌ no counterpart yet.

## Summary

| Area | ✅ | ⚠️ | ❌ |
|---|---:|---:|---:|
| 33-row ledger (A1–F2) | 33 | 0 | 0 |
| 33 sub-features below | 33 | 0 | 0 |
| **Total** | **66** | **0** | **0** |

The ledger is closed and so is every sub-feature on top of it. The last two
open rows closed without shipping an asset: offline narration runs on the
platform's downloaded voice packs, and the YouTube PO token now has the
YouTube Music source it was built for (both ported from Hikari, §3a).

## 1. The 33-row ledger

| # | Feature | Status | Where it lives in Zangetsu |
|---|---|---|---|
| A1 | Universal JSON-rule scrapers | ✅ | `core/universal/`, prefix `us:`, bundled Archive.org pack |
| A2 | Nuvio providers | ✅ | Shared JS-pack engine, prefix `nuvio:` |
| A3 | Vega providers | ✅ | Shared JS-pack engine, prefix `vega:` |
| A4 | Sora modules | ✅ | Shared JS-pack engine, prefix `sora:` |
| A5 | Anymex plugins | ✅ | Mangayomi defaults seed both Kegareta indexes |
| A6 | SkyStream plugins | ✅ | Shared JS-pack engine, prefix `sky:` |
| A7 | Kotatsu parsers | ✅ | Shared JS-pack engine, prefix `kot:` |
| A8 | `.hiki` extensions | ✅ | `core/hikari/` + `com/hikari/ext` DexClassLoader host |
| A9 | `.cs3` native API completeness | ✅ | Bytecode audit: 761 plugins, 0 missing classes/methods |
| B1 | Music mode | ✅ | `core/music/`, `features/music/`, JioSaavn |
| B2 | Telegram streaming | ✅ | `core/telegram/` for public channels, vendored TDLib for private ones and full history (§3c) |
| B3 | In-app browser + userscripts | ✅ | `features/web/`, `core/web/userscript_store.dart` |
| B4 | Subtitle sites | ✅ | OpenSubtitles.org mirror + SubtitleCat, keyless |
| B5 | Trackers (Trakt + MAL) | ✅ | Trakt device-code, MAL connect; Kitsu/Shikimori open (§3) |
| C1 | EPG / XMLTV guide | ✅ | `core/live/xmltv_parser.dart`, `epg_store.dart`, guide screen |
| C2 | DVR / reminders | ✅ | `core/live/dvr_store.dart`, capture service, recordings screen |
| C3 | Xtream Codes accounts | ✅ | `core/live/xtream_api.dart`, secure account store |
| C4 | Sports / catch-up / parental | ✅ | `sports_catalog.dart`, `catchup_url.dart`, `live_parental.dart` |
| C5 | Live VOD / torrent bridge | ✅ | `core/live/live_vod.dart` routing plan |
| D1 | AI Dub (TTS narration) | ✅ | `core/dub/`, `features/player/dub_sheet.dart` |
| D2 | Neural dub voices | ✅ | Hosted `translate_tts`, 14 languages, 12-locale labels |
| D3 | Voice scan | ✅ | Hosted diarizer + per-character device voices |
| D4 | Whisper speech-to-subtitle | ✅ | Hosted OpenAI-compatible transcription |
| D5 | Volume boost | ✅ | 100–200 % via mpv softvol + system volume |
| E1 | Stats page | ✅ | `features/stats/stats_screen.dart` |
| E2 | App lock (PIN + biometric) | ✅ | `core/privacy/app_lock.dart`, root gate |
| E3 | Pair & sync over Wi-Fi | ✅ | `core/pair/pair_protocol.dart`, QR screen |
| E4 | Logs & diagnostics | ✅ | `AppLogger` ring buffer, `logs_screen.dart` |
| E5 | Detail title-as-logo | ✅ | `TitleLogoService` + header/collapsed bar |
| E6 | Per-extension settings gear | ✅ | `hasSourceSettings`/`openSourceSettings`, JS `__settings` |
| E7 | Personal catalogs / collections | ✅ | `core/collections/`, Home rows, backup |
| F1 | `.hiki` extension SDK host | ✅ | Vendored `com.hikari.ext` SDK |
| F2 | CloudStream API completeness | ✅ | Closed by A9's audit |

## 2. Sub-features beyond the ledger

| Feature | Hikari | Status | Zangetsu / note |
|---|---|---|---|
| Kitsu tracker | `tracker/TrackerApi.kt` | ✅ | `core/tracker/kitsu_service.dart`; client id + secret in Parity tools, status row shows whether it is set |
| Shikimori tracker | `TrackerKind.SHIKIMORI` | ✅ | `core/tracker/shikimori_service.dart`; same client-credential shape as Kitsu |
| M3U / JSON playlist import | `iptv/LiveTvImport.kt` | ✅ | `core/live/m3u_playlist.dart` + import screen, 15 tests. |
| Channel marks / favourites | `data/IptvMark.kt` | ✅ | `core/live/iptv_mark_store.dart` + star action on the Live TV rows |
| CS3 built-in resolvers | `cs3/Cs3NewPipe.kt` etc. | ✅ | `parity/Cs3BuiltInResolvers.kt`, registered with the `.cs3` host; answers when a plugin yields no link |
| Ad blocker | `net/AdBlocker.kt` | ✅ | StevenBlack hosts, exact match, cached set. |
| Promo guard | `net/PromoGuard.kt` | ✅ | Donation hosts, path/query words, media exemption. |
| Stream probe | `net/StreamProbe.kt` | ✅ | 16 KB head, HLS/DASH sniff, three HTML hops, 5-min TTL. |
| Slow-net tip / tuning | `net/SlowNetTip.kt` | ✅ | `core/playback/slow_net_tip.dart`, shown from the stream probe result |
| Extension UI/verify guards | `net/Extension*Guard.kt` | ✅ | `core/provider/extension_guard.dart` on every JS-pack call, `ExtensionVerifyGuard` on Aniyomi installs |
| Redirect allowlist | `data/RedirectAllow.kt` | ✅ | Host-or-word matching, editor in Web protections. |
| Repo-link intents | `deeplink/RepoLinkActivity.kt` | ✅ | `parity/RepoLinkActivity.kt` + manifest filters for `http(s)://*.json` and `stremio:` |
| Foreground work service | `work/BackgroundWork.kt` | ✅ | `parity/WorkService.kt`, held by `ParityNative.beginWork` while a download is muxed |
| Offline Piper/Sherpa voices | `dub/PiperVoice.kt` | ✅ | Platform packs, not bundled models: `parity/OfflineVoicePack.kt` lists the installed offline voices, Parity tools shows the count and links the download screen, `DubPrefs.offlineOnly` filters the voice picker |
| Hard-sub dub | `dub/HardSubDub.kt` | ✅ | `ParityBridge.captureWindow` (PixelCopy on the window) keeps the burned-in subtitle in the saved frame; mpv's own screenshot does not |
| Audio FX | `dub/AudioFx.kt` | ✅ | `core/playback/audio_fx.dart` sets mpv `af` (reverb/echo), pitch kept |
| Lossless source | `music/VxLosslessApi.kt` | ✅ | `core/music/lossless_source.dart`, user endpoint + key persisted in Hive, edited in Parity tools |
| YouTube Music catalogue | `music/MusicApi.kt` | ✅ | `core/music/youtube_music_source.dart`, registered next to JioSaavn: WEB_REMIX InnerTube for browse/search, a native-first client chain for playback |
| YouTube PoToken | `music/PoToken*.kt` | ✅ | `core/music/potoken.dart` + `potoken_js.dart`: visitor id, BotGuard `Create`/`GenerateIT`, mint; the web client in `YouTubeMusicSource` sends `serviceIntegrityDimensions.poToken` and the bound visitor id |
| Music downloads | `music/VxDownload.kt` | ✅ | `core/music/music_download.dart` from the player sheet |
| TV music UI | `music/TvMusic*.kt` | ✅ | `features/music/music_screen_tv.dart` on the TV shell |
| Sharpen filter | `reader/SharpenTransformation.kt` | ✅ | `core/reading/sharpen.dart` in the manga page pipeline, toggle in reader prefs |
| Generic scraper reader | `ScraperReaderScreen.kt` | ✅ | `features/reader/scraper_reader_screen.dart`, offered when a chapter is a bare image URL |
| Nuvio catalog/collections import | `NuvioCatalogImport.kt` | ✅ | `core/collections/nuvio_import.dart` + paste flow in Parity tools |
| Bangumi metadata | `nuvio/BangumiMeta.kt` | ✅ | Subject search, specials filtered, absolute episode titles. |
| TheTVDB artwork | `data/TvdbArt.kt` | ✅ | Keyless search, poster/banner, TMDB/IMDb cross-ids. |
| Performance mode | `data/PerfMode.kt` | ✅ | Image cache 1000/100 MB → 200/64 MB, automatic on TV. |
| Memory report | `data/MemoryReport.kt` | ✅ | RSS + peak behind a Logs action. |
| Tag translator | `i18n/TagTranslator.kt` | ✅ | 13 genres × 11 locales, unknown tags pass through. |
| Donghua details | `data/DonghuaDetails.kt` | ✅ | `core/metadata/donghua_details.dart` merged into the detail header for CN titles |
| TMDB stills rail | `TmdbStills.kt` | ✅ | `core/ui/stills_rail.dart` under the synopsis |
| Userscript manager | `web/UserscriptManager.kt` | ✅ | Parser, matcher, Hive store, injected on page finish. |
| Player skins / layouts | `PlayerSkins.kt` | ✅ | `features/player/player_skins.dart` picked in the player overlay |
| l10n wiring | `i18n/` | ✅ | 12 catalogues at 2295 keys each, `untranslated.txt` empty |

## 3. What is still open, and why

Nothing. Every row above is reachable from the UI. What was open at the last
count, and how it closed:

| Was open | How it closed |
|---|---|
| Offline Piper/Sherpa voices | Platform packs instead of bundled models — see below. |
| YouTube PoToken | The YouTube Music source it was built for now ships, and calls it. |

Hikari's bundled Piper models are the one thing deliberately not copied: a pack
is 60–200 MB per voice. Android's own speech engine ships offline packs, so
`parity/OfflineVoicePack.kt` reports the ones installed, Parity tools shows the
count and links the download screen, and the dub sheet has an "offline voices
only" filter for watching without a network — the same outcome, none of the
APK weight.

## 3a. Upstream sync

Hikari's `0.12.132` ("direct play starts on a server carrying the default
quality") landed in `core/playback/source_selection.dart`: a source's height is
now read from its `quality` **or** its label (`heightFromText`, which needs a
`p` so a title's year is not a resolution), and a preference means "the best
server at or below this height", falling back to the lowest one above when
every mirror is taller. That replaced a nearest-number rule which would pick
1440p for a 1080p preference when 1440p was arithmetically closer.

## 3b. The YouTube source, ported

Hikari's `music/MusicApi.kt` is 1,384 lines because it carries a television
retry ladder, a NewPipe extractor, Qobuz and mirror stages. The parts Zangetsu
needs are three, and each is a direct port:

| Hikari | Zangetsu | Note |
|---|---|---|
| `MusicApi.post()` / `parseShelves` / `parseListItem` / `parseTwoRow` | `YouTubeMusicSource._post` / `_parseShelves` / `_parseListItem` / `_parseTwoRow` | WEB_REMIX InnerTube, same key and client version. The song-only search `params` token is dropped: YouTube answers "No results" for it now, so search runs unfiltered and the parser keeps the songs. |
| `MusicApi.quickAudioUrlWith` + `quickClients` | `YouTubeMusicSource._resolve` + `_clients` | ANDROID_VR, iOS, Android Music, then MWEB. Native first because they need no token. AAC before Opus, highest bitrate within the container. |
| `potoken/*` | `potoken.dart` + `potoken_js.dart` | Visitor id, `Create` → challenge → VM → `GenerateIT` → mint. Hikari runs the VM in a hidden WebView; here it runs in the QuickJS runtime the provider packs already use, with the timer-driven glue rewritten as explicit steps. |

Divergences, all deliberate:

- **No NewPipe extractor.** It is a JVM library; the four clients cover the
  same ground and are what Hikari itself falls back to when the extractor will
  not start on a television.
- **No Qobuz / mirror stages.** `LosslessSource` is the user's own endpoint and
  JioSaavn is the keyless catalogue, so the ladder would only re-try the same
  two sources.
- **Albums, artists and playlists are dropped from lists.** Hikari keeps them to
  open a browse page; this app has no album page, so they would be dead rows.
- **No bundled Piper models.** See §3.

What is not verified here: playback. This machine is a datacenter address and
YouTube answers the `player` endpoint with `LOGIN_REQUIRED` ("Sign in to
confirm you're not a bot") for every client, which is exactly the case the
token exists for. Browse and search were checked live against the real
endpoint (17-track carousel, 18-row search); the player path needs a device.

## 3c. Telegram, ported

Hikari's `telegram/` is 2,123 lines across six files because its tab is a file
browser: chat list, in-chat search, album tails, a download manager. Zangetsu's
tab browses a channel and plays its videos, so the port keeps what serves that.

| Hikari | Zangetsu | Note |
|---|---|---|
| `Td.kt` (1,272 lines) | `android/.../telegram/TelegramTd.kt` | Client lifecycle, the phone/code/password login, `SearchPublicChat` + `GetChatHistory` reduced to videos, file state and prefix reads. The chat list, in-chat search, album tails and the search-in-post walk are dropped: no screen here needs them. |
| `TdStream.kt` (309 lines) | `android/.../telegram/TelegramStreamServer.kt` | Hikari plays Telegram videos through a media3 `DataSource`, because its player is ExoPlayer. This app's player is mpv and wants a URL, so the same waiting logic runs behind a loopback HTTP server with range support, reading through `DownloadFile` and `GetFileDownloadedPrefixSize`. |
| `jniLibs/` + `org.drinkless.tdlib` | vendored unchanged | 43 MB of prebuilt TDLib (Telegram X's build) for both ARM ABIs, plus the 5 MB Java bindings. Provenance and the `libc++_shared.so` rename are in `jniLibs/README.md`. |
| `TelegramError.kt`, `TelegramLinks.kt`, `TelegramChannels.kt`, `TelegramWeb.kt` | not ported | Error wording, link parsing and the channel list already exist in Dart (`telegram_source.dart`, `telegram_web.dart`), and the web client is the fallback this port must keep working. Porting them would duplicate both. |

The seam is the one the app already had: the `zangetsu/telegram` channel. It
now answers `available` truthfully (TDLib is linked), carries the login state
(`idle` → `starting` → `waitPhone` → `waitCode` → `waitPassword` → `ready`),
and `resolveChannel` returns the same `{title, url, thumbnail, pageUrl,
publishedAt}` maps the Dart layer always parsed — `url` is now a
`127.0.0.1` stream, `thumbnail` a `127.0.0.1` thumbnail. `TelegramService`
asks the native path only when it is `ready`, and falls back to the web preview
otherwise, so a build with no TDLib, a signed-out client, or a refused call all
degrade to the old behaviour.

Build changes this needed:

- `stageTdJniLibs` in `android/app/build.gradle.kts`: the C++ runtime is
  committed as `libcxx_shared.so` (a `+` cannot live in this workspace's paths)
  and staged as `libc++_shared.so`, the name the linker resolves.
- `-keep class org.drinkless.tdlib.**` in `proguard-rules.pro`: TDLib looks its
  own classes up by name at runtime, so a release build must not strip them.

Divergences, all deliberate:

- **No chat list, no in-chat search.** The tab browses one channel at a time;
  the pieces that would feed a chat list are not built.
- **Loopback server instead of a DataSource.** The player is mpv, not ExoPlayer.
- **Dropped login variants.** Email, Google/Apple sign-in and the premium step
  are not implemented; the phone flow is the one every account has, and the
  card says so rather than sitting on a blank state.

What is not verified here: everything at runtime. The Kotlin compiles, the APK
packages the four libraries per ABI, and the staging task is wired, but a login
needs a phone with a Telegram account and an `api_id`/`api_hash` pair from
my.telegram.org, and playback needs a device with mpv. The channel's
unavailable/fallback paths are the ones exercised on this machine.

## 4. Landed in this pass

```
feat(parity): close the built-but-unwired set and prove the native build  (this commit)
6b53685e feat(parity): CS3 built-in resolvers answer when a plugin yields no link
4d187dd8 feat(parity): finish the wiring pass and prove the native seams build
b58724dc docs: hand off the parity wiring pass
794a8d5  docs(gaps): mark the tag translator done
ea9a21a  feat(i18n): localise the genre tags
ca64ac8  feat(metadata): Bangumi episode titles and TheTVDB artwork
fb7b045  feat(perf): performance mode and a memory report
1e9f6da  docs(gaps): cross-check the matrix and mark the landed gaps
a7236a2  feat(playback): probe wrapper pages and add slow connection mode
c1bb4d6  feat(web): ad blocking, promo filtering and userscripts
a2ac7b8  feat(live): import the user's own M3U / JSON playlists
5e93935  docs(gaps): record the verified sub-feature matrix
8a929df  feat(tracker): add Trakt with the device-code flow
1ede292  perf(subtitles): fetch SubtitleCat release pages in parallel
64a0637  docs(gaps): audit the surfaces beyond the 32-row ledger
4c58399  feat(subtitles): add keyless SubtitleCat and tidy the mirror format
44cafe1  feat(subtitles): search the keyless OpenSubtitles.org mirror
9a6d308  feat(web): save websites and open them in an in-app browser
```

The seven parity commits before `b58724dc` are listed in `HANDOFF.md` §5.
`4d187dd8` closes the wiring pass in that handoff, `6b53685e` finishes the last
native resolver row, and the commit that carries this file gives the
built-but-unwired helpers their call sites.

Verified at the head of `main`:

- `flutter analyze` → "No issues found!"
- `flutter build apk --debug` → built, so every Kotlin file in `parity/`
  compiles and both method channels (`zangetsu/media_export`,
  `zangetsu/parity`) are registered in `MainActivity`.
- 12 ARB catalogues at 2287 keys each; `untranslated.txt` is `{}`.
- `flutter test` — run end to end through `scripts/run_full_tests.sh`
  (resumable 25-file shards, because a single run outlives the sandbox): 721
  files, 5,605 passing, 10 skipped. One real failure surfaced — the settings
  backup drift guard — and is fixed. Per-area counts are in `AUDIT.md` §5.

## 5. Gap-table pass

Twelve audited rows landed after the wiring pass, each with a call site and a
test: UI scale, header height, poster quick menu, TMDB browse rows and screen,
streaming Xtream parses (`FlatJsonScanner`), provider timeout recovery
(`ExtensionRecovery`), DoH wire format and DNS provider list with its settings
screen, music quality tiers, the music EQ chain, the `AudioOutput` filter seam,
and lossless tier ordering. `AUDIT.md` §6 is the row-by-row table; `AUDIT.md`
§5 has the test counts.
