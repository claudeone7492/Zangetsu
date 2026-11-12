import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const TV = new URL('../providers/iptv.js', import.meta.url);
loadProvider('iptv', TV);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) => test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a provider', async () => {
  const info = JSON.parse(await callProvider('iptv', 'getInfo', []));
  assert.equal(info.name, 'IPTV');
  assert.equal(info.type, 'movie');
});

// --- Live ------------------------------------------------------------------
live('getHome returns category rails of channels', async () => {
  const sections = JSON.parse(await callProvider('iptv', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  assert.ok(sections[0].items.length > 0, 'rail has channels');
  const ch = sections[0].items[0];
  assert.ok(ch.url.startsWith('ch:'), 'channel url is self-describing, got ' + ch.url);
});

live('search filters the full index by name', async () => {
  const rows = JSON.parse(await callProvider('iptv', 'search', ['kids', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0);
});

live('channel resolves to a live HLS stream', async () => {
  const sections = JSON.parse(await callProvider('iptv', 'getHome', [{}]));
  // Find a channel whose playlist actually answers right now.
  let ok = 0, tried = 0;
  for (const rail of sections) {
    for (const ch of rail.items.slice(0, 12)) {
      tried++;
      const sources = JSON.parse(await callProvider('iptv', 'getVideoSources', [ch.url]));
      assert.ok(Array.isArray(sources) && sources.length === 1, 'one source per channel');
      try {
        const res = await fetch(sources[0].url, { headers: sources[0].headers, redirect: 'follow' });
        if (res.ok) {
          const body = await res.text();
          if (/#EXTM3U|#EXTINF/.test(body)) { ok++; break; }
        }
      } catch (e) { /* dead channel; try the next */ }
    }
    if (ok) break;
  }
  assert.ok(ok >= 1, 'at least one live channel playlist should resolve (tried ' + tried + ')');
});
