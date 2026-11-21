# Zangetsu ↔ Hikari parity

Measured against `claudeone7492/Zangetsu` at `794a8d5` and the Hikari tree at
`codegeasse1/hikari` (`/workspace/hikari-reference`). Every row was checked by
file and symbol search, not by feature name alone. Tests are named where they
exist.

Legend: ✅ done and reachable · ⚠️ partial, or deliberately different ·
❌ no counterpart yet.

## Summary

| Area | ✅ | ⚠️ | ❌ |
|---|---:|---:|---:|
| 33-row ledger (A1–F2) | 33 | 0 | 0 |
| 33 sub-features below | 11 | 8 | 14 |
| **Total** | **44** | **8** | **14** |

The ledger is closed. The 14 open items are all outside the ledger: two
trackers, one native resolver pack, four native-only system seams, three
music extras, two reader extras, one import, and one guard layer.

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
| Kitsu tracker | `tracker/TrackerApi.kt` | ❌ | Email/password + client secret; needs a credential store. |
| Shikimori tracker | `TrackerKind.SHIKIMORI` | ❌ | OAuth, same shape as MAL. |
| M3U / JSON playlist import | `iptv/LiveTvImport.kt` | ✅ | `core/live/m3u_playlist.dart` + import screen, 15 tests. |
| Channel marks / favourites | `data/IptvMark.kt` | ⚠️ | No separate marks store; favourites live elsewhere. |
| CS3 built-in resolvers | `cs3/Cs3NewPipe.kt` etc. | ❌ | Native CS3 host exists; the bundled resolvers do not. |
| Ad blocker | `net/AdBlocker.kt` | ✅ | StevenBlack hosts, exact match, cached set. |
| Promo guard | `net/PromoGuard.kt` | ✅ | Donation hosts, path/query words, media exemption. |
| Stream probe | `net/StreamProbe.kt` | ✅ | 16 KB head, HLS/DASH sniff, three HTML hops, 5-min TTL. |
| Slow-net tip / tuning | `net/SlowNetTip.kt` | ⚠️ | Tuning + toggle landed; the in-player tip is not built. |
| Extension UI/verify guards | `net/Extension*Guard.kt` | ❌ | No shared guard layer. |
| Redirect allowlist | `data/RedirectAllow.kt` | ✅ | Host-or-word matching, editor in Web protections. |
| Repo-link intents | `deeplink/RepoLinkActivity.kt` | ❌ | Native activity for `http(s)://*.json` and `stremio:`. |
| Foreground work service | `work/BackgroundWork.kt` | ❌ | No wake-lock/ongoing-notification service. |
| Offline Piper/Sherpa voices | `dub/PiperVoice.kt` | ❌ | D1/D2 are hosted only. |
| Hard-sub dub | `dub/HardSubDub.kt` | ❌ | No PixelCopy burn-in path. |
| Audio FX | `dub/AudioFx.kt` | ⚠️ | Pitch exists; other effects do not. |
| Lossless source | `music/VxLosslessApi.kt` | ❌ | JioSaavn only. |
| YouTube PoToken | `music/PoToken*.kt` | ❌ | No YouTube music source. |
| Music downloads | `music/VxDownload.kt` | ❌ | No music download path. |
| TV music UI | `music/TvMusic*.kt` | ⚠️ | Phone `MusicScreen` is reused on TV with focus wrappers. |
| Sharpen filter | `reader/SharpenTransformation.kt` | ❌ | Crop exists; sharpen does not. |
| Generic scraper reader | `ScraperReaderScreen.kt` | ❌ | Image-list reader for scraped pages. |
| Nuvio catalog/collections import | `NuvioCatalogImport.kt` | ❌ | No Nuvio export import. |
| Bangumi metadata | `nuvio/BangumiMeta.kt` | ✅ | Subject search, specials filtered, absolute episode titles. |
| TheTVDB artwork | `data/TvdbArt.kt` | ✅ | Keyless search, poster/banner, TMDB/IMDb cross-ids. |
| Performance mode | `data/PerfMode.kt` | ✅ | Image cache 1000/100 MB → 200/64 MB, automatic on TV. |
| Memory report | `data/MemoryReport.kt` | ✅ | RSS + peak behind a Logs action. |
| Tag translator | `i18n/TagTranslator.kt` | ✅ | 13 genres × 11 locales, unknown tags pass through. |
| Donghua details | `data/DonghuaDetails.kt` | ⚠️ | Only an ISO country field. |
| TMDB stills rail | `TmdbStills.kt` | ⚠️ | Episode stills backfilled; detail-page rail missing. |
| Userscript manager | `web/UserscriptManager.kt` | ✅ | Parser, matcher, Hive store, injected on page finish. |
| Player skins / layouts | `PlayerSkins.kt` | ⚠️ | Functional equivalents, different styling. |
| l10n wiring | `i18n/` | ⚠️ | 12 catalogues at 2269 keys; ~120 older literals remain. |

## 3. What is still open, and why

| Item | Kind | Why it is open | Next step |
|---|---|---|---|
| Kitsu | Dart | Needs account-password sign-in and a credential store. | `core/tracker/kitsu.dart` + secure storage; ~1 pass. |
| Shikimori | Dart | OAuth, same shape as the MAL client. | Clone the MAL connect flow with Shikimori scopes. |
| CS3 built-in resolvers | Native | They are JVM classes the `.cs3` host must ship. | Port `Cs3NewPipe`/`MovieBlast`/`Mlbd`/`Fallback`. |
| Extension UI/verify guards | Dart | No shared guard layer. | One `ExtensionGuard` used by every source call. |
| Repo-link intents | Native | Android/iOS activity + manifest. | `RepoLinkActivity` mirroring Hikari. |
| Foreground work service | Native | Wake lock + ongoing notification. | `WorkService` over the existing download service. |
| Offline Piper/Sherpa voices | Native | Model packs, per-voice storage. | Keep hosted; add packs only on request. |
| Hard-sub dub | Native | PixelCopy frame burn-in. | Needs a device to verify. |
| Lossless music | API | No keyless lossless catalogue. | Add a second `MusicSource`. |
| YouTube PoToken | API | Fragile, server-dependent. | Defer until a stable endpoint exists. |
| Music downloads | API | No download path. | Reuse `DownloadService` with an audio-only container. |
| Sharpen filter | Dart | Not implemented. | `image` package convolution, same pipeline as crop. |
| Generic scraper reader | Dart | Not implemented. | Image-list reader fed by the universal scraper. |
| Nuvio import | Dart | Parser + paste flow not built. | `core/collections/nuvio_import.dart`. |
| Channel marks | Dart | No separate store. | `IptvMark` box keyed by channel id. |
| Slow-net tip | Dart | Only the tuning landed. | Snackbar in the player when the probe degrades. |
| Audio FX | Dart | Only pitch. | Reverb/echo via mpv `af`. |
| TV music UI | Dart | Phone screen reused. | Leanback rows already focusable; styling only. |
| Donghua details | Dart | Only a country field. | Add studio/year/status fields. |
| TMDB stills rail | Dart | Episode stills exist; detail rail does not. | Horizontal rail from `/images`. |
| Player skins | Dart | Cosmetic divergence. | Not a functional gap. |
| l10n backlog | Dart | ~120 literals in 50 files. | Mechanical; inventory regenerates from the script in `HANDOFF.md` §4.2. |

## 4. Landed in this pass

```
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

Every commit above is local only; nothing has been pushed.
