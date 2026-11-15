import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const TS = new URL('../providers/timstreams.js', import.meta.url);
loadProvider('timstreams', TS);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('search with no query is empty without a network call', async () => {
  const rows = JSON.parse(await callProvider('timstreams', 'search', ['', 1, {}]));
  assert.deepEqual(rows, []);
});

test('getVideoSources ignores a fixture handle with no feeds', async () => {
  const src = JSON.parse(await callProvider('timstreams', 'getVideoSources', ['ts:%7B%22n%22%3A%22X%22%2C%22s%22%3A%5B%5D%7D']));
  assert.deepEqual(src, []);
});

test('getVideoSources tolerates a malformed handle', async () => {
  const src = JSON.parse(await callProvider('timstreams', 'getVideoSources', ['ts:not-json']));
  assert.deepEqual(src, []);
});

test('getDetail names a fixture handle', async () => {
  const handle = 'ts:' + encodeURIComponent(JSON.stringify({ n: 'Patriots @ Lions', s: [] }));
  const d = JSON.parse(await callProvider('timstreams', 'getDetail', [handle]));
  assert.equal(d.title, 'Patriots @ Lions');
  assert.equal(d.episodes.length, 1);
});

// --- Live ------------------------------------------------------------------
live('getLive returns fixtures, in-play first, each with a badge', async () => {
  const items = JSON.parse(await callProvider('timstreams', 'getLive', [{}]));
  assert.ok(Array.isArray(items), 'expected an array');
  assert.ok(items.length > 0, 'expected fixtures');
  for (const it of items) {
    assert.ok(it.url.startsWith('ts:'), 'fixture url uses the ts: scheme, got ' + it.url);
    assert.equal(it.sourceId, 'timstreams');
    assert.ok(it.liveBadge, 'fixture has a status badge: ' + it.title);
    // The app keeps its rail to soccer, so each fixture must carry the
    // canonical slug the filter matches on.
    assert.ok(it.liveSport, 'fixture has a sport slug: ' + it.title);
  }
  const liveIdx = items.findIndex((i) => i.liveBadge === 'LIVE');
  const otherIdx = items.findIndex((i) => i.liveBadge !== 'LIVE');
  if (liveIdx !== -1 && otherIdx !== -1) {
    assert.ok(liveIdx < otherIdx, 'in-play fixtures lead the feed');
  }
});

live('getHome returns rails of live/upcoming fixtures', async () => {
  const sections = JSON.parse(await callProvider('timstreams', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  const items = sections.reduce((n, s) => n + s.items.length, 0);
  assert.ok(items > 0, 'rails carry items');
});

// The whole point of the binary lane: a fixture's embed decodes through the
// XOR-obfuscated page and the binary ticket to a real HLS playlist.
live('a fixture resolves to a real HLS playlist', async () => {
  const items = JSON.parse(await callProvider('timstreams', 'getLive', [{}]));
  assert.ok(items.length > 0, 'expected fixtures');
  let resolved = null;
  for (const it of items.slice(0, 6)) {
    const src = JSON.parse(await callProvider('timstreams', 'getVideoSources', [it.url]));
    if (src.length && /\.m3u8/i.test(src[0].url)) { resolved = src[0]; break; }
  }
  assert.ok(resolved, 'at least one fixture decodes to an .m3u8 url');
  assert.equal(resolved.container, 'hls');
  const res = await fetch(resolved.url, {
    headers: { 'User-Agent': resolved.headers['User-Agent'], Referer: resolved.headers.Referer },
  });
  assert.ok(res.ok, 'playlist fetch ok, got ' + res.status);
  const body = await res.text();
  assert.ok(body.startsWith('#EXTM3U'), 'body is an HLS playlist');
});
