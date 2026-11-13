# Bundled provider pack

Each `*.js` here is a source the app ships and can run. `assets/providers/`
holds the copies a new install loads (plus `manifest.json`, the pack index);
the two trees are kept byte-identical by hand when a provider changes.

Every source in the pack was verified end-to-end before it was added —
browse (`getHome`) → search → detail → reader/playback — with a live probe
(`RUN_LIVE=1 node js_harness/verify_pack.mjs`) and a per-source `node:test`
under `js_harness/`. A source that does not resolve fully is not added.

## Novel / manga sources

| id | site | kind | reader |
|---|---|---|---|
| `novelfire` | novelfire.net | novel | text |
| `wattpad` | wattpad.com | novel | text |
| `freewebnovel` | freewebnovel.com | novel | text |
| `novelbin` | novelbin.cc | novel | text |
| `novelight` | novelight.net | novel | text |
| `inkitt` | inkitt.com | novel | text |
| `tapas` | tapas.io | novel | text |
| `tapas-comics` | tapas.io | manga | page images |
| `weebcentral` | weebcentral.com | manga | page images |
| `mangabats` | mangabats.com | manga | page images |
| `asurascans` | asurascans.com | manga | page images |

`tapas` and `tapas-comics` are one file (`providers/tapas.js`) registered twice:
the provider reads its own runtime id (`__SOURCE_ID`) and serves novels or
comics accordingly. A novel chapter is HTML text; a comic chapter is a list of
page images.

## Intentionally excluded (WAF / JS-shield blocked)

These reading sites were probed and cannot be served without a real browser
executing a bot challenge. Each returns a challenge shell — or a flat block —
to a plain fetch, so a provider could not read them:

| site | response | why |
|---|---|---|
| quotev.com | 200, 46-byte body | custom JS/AES shield that sets a cookie; needs script execution |
| royalroad.com | 403 | WAF block on non-browser clients |
| archiveofourown.org | 418 | anti-bot ("I'm a teapot") block |
| scribblehub.com | 403 | Cloudflare block |

They are left out on purpose: shipping a source that cannot fetch would only
surface an error to the reader. If a site later becomes reachable, it can be
added the same way as the sources above.
