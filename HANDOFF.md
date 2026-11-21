# HANDOFF — Zangetsu / Hikari parity: finish the wiring pass, then build the native seams

Written 2026-11-21. Measured against `main` after the seven parity commits
listed in §5. Working tree clean, `flutter analyze` clean.

## 0. Start here

```bash
cd /workspace/project
source scripts/env.sh          # ALWAYS. Sets Flutter/JDK/Android paths.
git status --short             # expect clean
git --no-pager log --oneline -8
flutter analyze                # expect "No issues found!"
```

## 1. What is done

- **38-row gap board from `AUDIT.md`: every row now has code.** 33 Dart
  modules/screens, 6 Kotlin files, 37 new tests, all Dart analyzed clean.
- **Live at real call sites (4):** `NsfwGate` (home rows, driven by the
  NSFW-source switch), `HomeDedupe`, `TitleQualityParser` (poster badge),
  `EpisodeDubSub` (inside `EpisodeMetadataService`).
- **Built but not reachable (the wiring pass):** everything in §3.
- **Parity tools screen** `lib/features/settings/parity_tools_screen.dart`
  already hosts: Nuvio import, Tachiyomi import, lossless endpoint, tracker
  status, UI-scale slider, help sheet.

## 2. Environment facts (trust these)

- Flutter **3.44.9**, Dart **3.12.2**, JDK 17, at `/workspace/toolchain/{flutter,jdk,androi-sdk}`.
- `pub get` resolved; 184 packages have newer *incompatible* versions — pre-existing, do not "fix".
- `flutter gen-l10n` must run after any `.arb` edit; generated files are committed.
- Android package is `com.spyou.watch_app`; parity Kotlin lives in
  `android/app/src/main/kotlin/com/spyou/watch_app/parity/`.
- Sandbox restarts kill long commands; `/tmp` is wiped. Keep logs in
  `.agent_logs/` (gitignored). `flutter analyze` survives; large `flutter test`
  runs may not — run one file at a time.

## 3. Remaining work, in order

1. **Settings entry for Parity tools.** Add `parityTools` + `parityToolsSubtitle`
   to all 12 ARBs (en + ar de es fr id it ja pt tr zh zh_TW), `flutter gen-l10n`,
   then in `lib/features/settings/settings_about.dart` first `SettingsCard`:
   `SettingsTile(icon: Icons.tune, title: context.l10n.parityTools, onTap: () => _push(const ParityToolsScreen()))`.
   Do **not** hardcode English — the catalogues are at exact key parity.
2. **Player.** Push `ServerStreamsPage` from the stream picker; set
   `AudioFxChain.filterFor(fx)` on mpv's `af`; call
   `SlowNetTip.shouldShow(host, slow: probe.slow)` after the probe.
3. **Detail.** `StillsRail(urls: images, headers: headers)` under the synopsis;
   show `DonghuaDetails.fromTmdb(json)` when `country == 'CN'`.
4. **Reader.** Add a `sharpen` pref, apply `Sharpen.apply(decoded)` in the page
   pipeline; add a translate action using `NovelTranslate.translate(text, fn)`.
5. **Live TV.** Star icon → `IptvMarkStore.toggle(id)`; route
   `LiveManageScreen`, `LiveOnDemandScreen`, `LiveSportsScreen` from the overflow.
6. **Music.** Register `LosslessSource` next to `JioSaavnSource`; download action
   → `MusicDownload.save`; `MusicScreenTv` on the TV shell; `PlayerSkins.of(skin)`
   in the player overlay.
7. **Native build (needs a device).** `MediaExporter`, `RepoLinkActivity`,
   `WorkService`, `HardSubBurner`, `OfflineVoicePack`, `Cs3BuiltInResolvers`
   are written but **never compiled**. `MainActivity` still needs the
   `zangetsu/media_export` MethodChannel handler; `Cs3BuiltInResolvers` needs
   registering with the `.cs3` host.

## 4. Definition of done

1. `git status` clean; `main` level with `origin/main`.
2. `flutter analyze` → "No issues found!".
3. All 12 ARBs at identical key counts; `untranslated.txt` is `{}`.
4. Every screen in §3 reachable from the UI (not just imported).
5. Full `flutter test` green.
6. Kotlin compiles (`flutter build apk --debug`) and the two channels answer.
7. `AUDIT.md` counts updated to match reality.

## 5. Commit log (all on `main`)

```
aa6938a  feat(parity): parity tools screen consolidating the new integrations
6891a50  feat(parity): CS3 resolvers, live screens, TV music, player skins, marks wiring
830ea1e  feat(parity): native seams for gallery export, repo links, foreground work, hard-sub, offline voices
60937ef  feat(parity): Kitsu, Shikimori, lossless, music downloads, PoToken, novel translation, scroll keeper, stills rail, scraper reader, server page
4daef44  feat(parity): UI scale, custom background, channel marks, help sheet, mouse mode, audio FX, slow-net tip, donghua fields
a50c622  feat(parity): land the core for six audited gaps
d98cf06  feat(parity): app-wide NSFW gate, cross-engine dedupe, quality badges, dub/sub merge
8f1c1e2  docs: full second-pass audit against all 33 Hikari packages
```

## 6. Honest status

The feature code exists and the Dart compiles clean; the product is **not**
finished. Nothing new is reachable except the four wired items, and no Kotlin
has been built. Treat §3 as the definition of "done", not the commit list.
