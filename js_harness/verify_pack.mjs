// Live end-to-end probe for every source in the bundled pack. Not part of the
// default `node --test` run (needs the network); run explicitly:
//
//   RUN_LIVE=1 node verify_pack.mjs
//
// For each source it exercises the same path the app uses — getInfo, getHome,
// search, getDetail, and getVideoSources / reader pages — and prints a verdict
// per stage. A source that fails browse, search, detail or playback is a
// candidate to drop from the curated pack.
import { loadProvider, callProvider } from './host.mjs';
import fs from 'node:fs';
import path from 'node:path';

const MANIFEST = JSON.parse(
  fs.readFileSync(new URL('../assets/providers/manifest.json', import.meta.url), 'utf8'),
);

const root = new URL('../assets/providers/', import.meta.url);

async function tryCall(id, method, args, label) {
  try {
    const raw = await callProvider(id, method, args);
    const parsed = raw == null ? null : JSON.parse(raw);
    return { ok: true, value: parsed, label };
  } catch (e) {
    return { ok: false, error: String(e && e.message ? e.message : e), label };
  }
}

function verdict(r, extra = '') {
  return r.ok ? `OK ${extra}` : `FAIL ${r.error}`;
}

for (const s of MANIFEST.sources) {
  const file = new URL(s.file, root);
  loadProvider(s.id, file);
  const info = await tryCall(s.id, 'getInfo', []);
  const home = await tryCall(s.id, 'getHome', [{}]);
  const homeCount = home.ok && Array.isArray(home.value)
    ? home.value.reduce((n, sec) => n + (sec.items ? sec.items.length : 0), 0)
    : 0;
  const search = await tryCall(s.id, 'search', ['one', 1, {}]);
  const searchCount = search.ok && Array.isArray(search.value) ? search.value.length : 0;

  let detailOk = '-';
  let playOk = '-';
  let playLabel = 'getVideoSources';
  // Pick a search hit to walk detail → sources when search gave us one.
  const first = search.ok && Array.isArray(search.value) && search.value[0];
  if (first && first.url) {
    const detail = await tryCall(s.id, 'getDetail', [first.url]);
    detailOk = verdict(detail, detail.ok && detail.value && detail.value.episodes
      ? `eps=${detail.value.episodes.length}` : '');
    const ep = detail.ok && detail.value && detail.value.episodes && detail.value.episodes[0];
    if (ep && ep.url) {
      if (s.type === 'manga') {
        playLabel = 'getPages';
        const pages = await tryCall(s.id, 'getPages', [ep.url]);
        playOk = verdict(pages, pages.ok && Array.isArray(pages.value)
          ? `pages=${pages.value.length}` : '');
      } else if (s.type === 'novel') {
        playLabel = 'getText';
        const text = await tryCall(s.id, 'getText', [ep.url]);
        playOk = verdict(text, text.ok && text.value
          ? `chars=${JSON.stringify(text.value).length}` : '');
      } else {
        const sources = await tryCall(s.id, 'getVideoSources', [ep.url]);
        playOk = verdict(sources, sources.ok && Array.isArray(sources.value)
          ? `n=${sources.value.length}` : '');
      }
    }
  }

  console.log(`\n=== ${s.id} (${s.type})`);
  console.log(`  getInfo        ${verdict(info, info.ok ? info.value.name : '')}`);
  console.log(`  getHome        ${verdict(home, `items=${homeCount}`)}`);
  console.log(`  search         ${verdict(search, `hits=${searchCount}`)}`);
  console.log(`  getDetail      ${detailOk}`);
  console.log(`  ${playLabel.padEnd(14)} ${playOk}`);
}
