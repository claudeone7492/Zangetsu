import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const SF = new URL('../providers/streamfree.js', import.meta.url);
loadProvider('streamfree', SF);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a provider', async () => {
  const info = JSON.parse(await callProvider('streamfree', 'getInfo', []));
  assert.equal(info.name, 'StreamFree');
  assert.equal(info.type, 'movie');
});

test('search with no query is empty without a network call', async () => {
  const rows = JSON.parse(await callProvider('streamfree', 'search', ['', 1, {}]));
  assert.deepEqual(rows, []);
});

test('getVideoSources ignores a handle with no key', async () => {
  const src = JSON.parse(await callProvider('streamfree', 'getVideoSources', ['live:']));
  assert.deepEqual(src, []);
});

// --- Live ------------------------------------------------------------------
live('getHome returns per-sport rails of fixtures', async () => {
  const sections = JSON.parse(await callProvider('streamfree', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  const items = sections.reduce((n, s) => n + s.items.length, 0);
  assert.ok(items > 0, 'rails carry fixtures');
  const fx = sections[0].items[0];
  assert.ok(fx.url.startsWith('live:'), 'fixture url uses the live: scheme, got ' + fx.url);
  assert.equal(fx.sourceId, 'streamfree');
});

live('getLive folds every sport into one feed, in-play first', async () => {
  const items = JSON.parse(await callProvider('streamfree', 'getLive', [{}]));
  assert.ok(Array.isArray(items) && items.length > 0, 'expected fixtures');
  const liveIdx = items.findIndex((i) => i.liveBadge === 'LIVE');
  const otherIdx = items.findIndex((i) => i.liveBadge !== 'LIVE');
  if (liveIdx !== -1 && otherIdx !== -1) {
    assert.ok(liveIdx < otherIdx, 'in-play fixtures lead the feed');
  }
  // Every fixture carries a badge, so no poster is left without a status.
  for (const it of items) {
    assert.ok(it.liveBadge, 'fixture has a badge: ' + it.title);
    assert.ok(it.url.startsWith('live:'));
  }
});

live('a 24/7 channel resolves to a real HLS playlist', async () => {
  const items = JSON.parse(await callProvider('streamfree', 'getLive', [{}]));
  const channel = items.find((i) => i.liveBadge === 'LIVE');
  assert.ok(channel, 'expected at least one in-play fixture or 24/7 channel');
  const sources = JSON.parse(await callProvider('streamfree', 'getVideoSources', [channel.url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'one source per fixture');
  const s = sources[0];
  assert.equal(s.container, 'hls');
  assert.ok(/index\.m3u8/.test(s.url), 'playlist url, got ' + s.url);
  const res = await fetch(s.url, { headers: s.headers, redirect: 'follow' });
  assert.ok(res.ok, 'playlist should answer, got ' + res.status);
  const body = await res.text();
  assert.ok(/#EXTM3U/.test(body), 'playlist body is HLS');
});
