# HANDOFF — TDLib is linked; run the full test suite next


Written 2026-11-21, after `30e0dd30` on `main`. Working tree clean.


## 0. Start here


```bash
cd /workspace/project
source scripts/env.sh          # ALWAYS. Sets Flutter/JDK/Android paths.
git status --short             # expect clean
git --no-pager log --oneline -3
flutter analyze                # expect "No issues found!"
```

The first job is the one that was deliberately left: **the full test suite**.

```bash
# One file at a time — this sandbox kills long runs. The suite is large.
flutter test test/core/telegram/
flutter test test/core/music/
# ...then the rest, directory by directory.
```

`test/core/telegram/` was run before the handoff and passes (29 tests). The
rest of `flutter test` has **not** been run against `30e0dd30`.


## 1. What landed in this pass


TDLib, the last open unit in `AUDIT.md`. "Integrate it" was read as "link the
library Hikari vendors and make the existing Telegram tab use it", because that
was the one row still short of ✅ in both documents.

| Piece | File | What it does |
|---|---|---|
| Vendored runtime | `android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a}/` | `libtdjni.so`, `libcryptox.so`, `libsslx.so`, `libcxx_shared.so` — 43 MB, copied from `/workspace/hikari`, provenance in `jniLibs/README.md` |
| Java bindings | `android/app/src/main/java/org/drinkless/tdlib/` | `TdApi.java` (5 MB) + `Client.java`, copied unchanged |
| Client | `android/app/src/main/kotlin/com/spyou/watch_app/telegram/TelegramTd.kt` | Lifecycle, phone/code/password login, `SearchPublicChat` → `GetChatHistory` → videos, file state/prefix reads. Port of Hikari `Td.kt` minus the chat list, in-chat search and album tails |
| Stream server | `.../telegram/TelegramStreamServer.kt` | Loopback HTTP with range support, so mpv can play TDLib files. Hikari's equivalent is a media3 `DataSource`; this player is mpv and needs a URL |
| Channel | `.../TelegramBridge.kt` | `available`, `auth`, `setCredentials`, `submitPhone/Code/Password/Registration`, `signOut`, `resolveChannel` (now with `messageId`) |
| Dart bridge | `lib/core/telegram/telegram_bridge.dart` | The same calls, all degrading to `TelegramUnavailable` |
| Sign-in UI | `lib/features/telegram/telegram_sign_in.dart` | One card, one field per step, driven by the native state; polls while TDLib is `starting` |
| Wiring | `telegram_screen.dart`, `telegram_service.dart`, `telegram_prefs.dart` | Card shown only when the library is linked; native path used only when `ready`; `api_id`/`api_hash` persisted |
| Build | `android/app/build.gradle.kts`, `proguard-rules.pro` | `stageTdJniLibs` renames the C++ runtime; committed spelling excluded from packaging; `-keep org.drinkless.tdlib.**` |
| Docs | `PARITY.md` §3c, `AUDIT.md` | Port table, divergences, counts → 139 ✅ / 0 ⚠️ / 2 ➖ of 141 |

`zangetsu/parity`'s `tdlib` probe (`Class.forName("org.drinkless.tdlib.TdApi")`)
now answers `true`, and Parity tools says so.


## 2. Verified on this machine


- `flutter analyze` → "No issues found!".
- `flutter test test/core/telegram/` → 29 passed. The service fake gained an
  `authState` override, because the native path is now gated on `ready`.
- `./gradlew :app:compileDebugKotlin` → clean.
- `flutter build apk --debug` → built (≈250 MB debug APK).
- APK contents checked: exactly one `libc++_shared.so` per ARM ABI (the staged
  name), plus `libtdjni.so`, `libcryptox.so`, `libsslx.so`. The committed
  `libcxx_shared.so` spelling is excluded, so the duplicate Hikari ships is not
  reproduced here.
- 12 ARBs at 2295 non-metadata keys each; `flutter gen-l10n` regenerated and
  committed.


## 3. Not verified — this is the next session's work


1. **Full `flutter test`.** Nothing beyond `test/core/telegram/` was run.
2. **Telegram at runtime, on a device.** Login needs a phone with a Telegram
   account and an `api_id`/`api_hash` pair from my.telegram.org. Then:
   - the card should walk `idle → waitPhone → waitCode → [waitPassword] → ready`;
   - a public channel should list through TDLib (`TelegramBackend.native`);
   - playing one should hit `127.0.0.1:<port>/stream?...` and mpv should
     buffer as TDLib downloads;
   - thumbnails come from `/thumb?id=…`, which waits up to 20 s for the file.
3. **YouTube playback.** Still needs a device (see `PARITY.md` §3b): this
   machine's address gets `LOGIN_REQUIRED` from the `player` endpoint.
4. **Sign-out path.** `signOut()` sends `LogOut`; TDLib then reports
   `AuthorizationStateClosed`. The card handles `closed` by showing the
   credentials fields again, but that transition has not been watched on a
   device.


## 4. Environment facts (trust these)


- Flutter **3.44.9**, Dart **3.12.2**, JDK 17, at `/workspace/toolchain/...`.
- `flutter gen-l10n` must run after any `.arb` edit; generated files are
  committed (`lib/l10n/app_localizations*.dart`).
- Android package `com.spyou.watch_app`; Telegram Kotlin lives in
  `kotlin/com/spyou/watch_app/telegram/`, TDLib's Java in
  `java/org/drinkless/tdlib/`.
- `libcxx_shared.so` is committed under that spelling because a `+` cannot live
  in this workspace's paths; `stageTdJniLibs` stages the real name at build
  time. Do not "fix" the spelling in `jniLibs/`.
- Sandbox restarts kill long commands; keep logs in `.agent_logs/` (gitignored).


## 5. Known sharp edges


- `TelegramTd.available` was removed; `linked` now means "the library loaded",
  which is what the sign-in card needs. `resolveChannel` returns an empty list
  when no client exists, and the Dart service falls through to the web preview.
- The loopback server is bound to `127.0.0.1` on an ephemeral port, so URLs are
  per-process. A resume entry saved with an old URL will not play after a
  restart; the channel list re-resolves on open, which is the path that works.
- `TelegramTd.stateOf` caches `GetFile` answers; `UpdateFile` refreshes them. If
  a video stalls at 0 %, check whether TDLib refused the download — the refusal
  is recorded in `downloadErrors` and surfaces as an `IOException` in the
  server's log (`adb logcat -s TelegramStream TelegramTd`).
- The debug APK is ~250 MB now. Release splits per ABI, so the shipped size
  grows by roughly 14 MB (armv7) / 20 MB (arm64).
