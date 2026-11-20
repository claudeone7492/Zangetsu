# `.cs3` compatibility audit

`audit.py` proves — rather than assumes — that our native CloudStream host can
link every plugin the community ships.

It parses the constant pool of each plugin `.class` file and resolves every
referenced `(owner, method, descriptor)` against `library-android`, which Gradle
already caches. Checking classes alone is not enough: a plugin links methods by
descriptor, so a method that is absent throws `NoSuchMethodError` at runtime even
when every class resolves.

## Run it

```bash
# audit a directory of plugin jars
python3 tools/cs3_compat/audit.py --plugins-dir /tmp/plug

# or download a sample first (no setup needed)
python3 tools/cs3_compat/audit.py --fetch --limit-repos 5 --per-repo 4
```

Exit code is `0` when everything links, `1` when something is missing, `2` when
nothing could be audited — so it can gate CI.

## Current result

761 plugins across the 38 repos in `recloudstream/cs-repos`: **0 missing classes,
0 missing methods**.

Two results that look like gaps but are not, both confirmed against the AAR:

- `app` is `MainActivityKt.getApp()` — a top-level `var app` in
  `MainActivity.kt`, not an `App.kt` (upstream has no such file).
- `com.lagradost.nicehttp.*` (which `M3u8Helper` and `CloudflareKiller` use)
  arrives transitively via `com.github.Blatzar:NiceHttp:0.4.18`, so a diff that
  only reads `library-android`'s own jar reports it as missing.

Our `CloudStreamApp` / `DataStore` / `Event` shims stay necessary: the library
omits the app-context and settings surface they supply, and plugins do call it.
