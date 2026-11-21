# Zangetsu ↔ Hikari parity

> **Superseded in depth by [`AUDIT.md`](AUDIT.md)**, which walks all 33
> Hikari packages (140 units) and corrects several statuses below.

Measured against `claudeone7492/Zangetsu` at the head of `main` and the Hikari tree at
`codegeasse1/hikari` (`/workspace/hikari`). Every row was checked by file and
symbol search, not by feature name alone. Tests are named where they exist.

Legend: ✅ done and reachable · ⚠️ partial, or deliberately different ·
❌ no counterpart yet.

## Summary

| Area | ✅ | ⚠️ | ❌ |
|---|---:|---:|---:|
| 33-row ledger (A1–F2) | 33 | 0 | 0 |
| 33 sub-features below | 31 | 1 | 1 |
| **Total** | **64** | **1** | **1** |

The ledger is closed, and so are the sub-features it sat on top of. Two rows
stay open on purpose: no Piper/Sherpa models are bundled (hosted voices carry
the dub), and the YouTube PoToken helper has no YouTube source to serve.

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
| B2 | Telegram streaming | ✅ | `core/telegram/`, public channels; TDLib client is the private-channel upgrade |
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
| Offline Piper/Sherpa voices | `dub/PiperVoice.kt` | ❌ | No models are bundled; `parity/OfflineVoicePack.kt` reports none and Parity tools says so |
| Hard-sub dub | `dub/HardSubDub.kt` | ✅ | `ParityBridge.captureWindow` (PixelCopy on the window) keeps the burned-in subtitle in the saved frame; mpv's own screenshot does not |
| Audio FX | `dub/AudioFx.kt` | ✅ | `core/playback/audio_fx.dart` sets mpv `af` (reverb/echo), pitch kept |
| Lossless source | `music/VxLosslessApi.kt` | ✅ | `core/music/lossless_source.dart`, user endpoint + key persisted in Hive, edited in Parity tools |
| YouTube PoToken | `music/PoToken*.kt` | ⚠️ | `core/music/potoken.dart` built; no YouTube source calls it yet |
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
| l10n wiring | `i18n/` | ✅ | 12 catalogues at 2287 keys each, `untranslated.txt` empty |

## 3. What is still open, and why

| Item | Kind | Why it is open | Next step |
|---|---|---|---|
| Offline Piper/Sherpa voices | Native | Bundling voice models is a licensing and size decision, not a code one. The seam (`parity/OfflineVoicePack.kt`) answers with an empty list and Parity tools says so out loud. | Ship a model pack, then list it from `voicePacks`. |
| YouTube PoToken | Dart | `core/music/potoken.dart` can mint one, but there is no YouTube music source to hand it to. | Add the source, then wire the token into its manifest request. |

Everything else in §2 is reachable from the UI. The two rows above are the
whole open set.

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
- `flutter test` — 5,535 passing, 8 skipped, on the tree above; per-area
  counts are in `AUDIT.md` §5.
