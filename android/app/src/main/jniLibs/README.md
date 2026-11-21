# TDLib native libraries

Vendored from the Hikari reference app (`/workspace/hikari`), which in turn
ships Telegram X's prebuilt `libtdjni` bundle. Nothing here is built from
source in this repo.

| File | What it is |
| --- | --- |
| `libtdjni.so` | TDLib's JNI entry point; finds `org.drinkless.tdlib.Client` by name |
| `libcryptox.so`, `libsslx.so` | TDLib's bundled crypto and TLS |
| `libcxx_shared.so` | the C++ runtime TDLib links against |

`libcxx_shared.so` is committed under that spelling because a `+` cannot live
in this workspace's paths, and Android's linker resolves `DT_NEEDED` by file
name — so `android/app/build.gradle.kts` stages it as `libc++_shared.so` before
packaging (`stageTdJniLibs`).

The Java bindings these register against live in
`android/app/src/main/java/org/drinkless/tdlib/` and are kept whole by
`android/app/proguard-rules.pro`, because TDLib looks its own classes up by
name at runtime.

Only the two ARM ABIs are shipped; the app's packaging rules drop x86/x86_64
for every other native library too.
