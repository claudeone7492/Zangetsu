import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const CDN = new URL('../providers/cdnlivetv.js', import.meta.url);
loadProvider('cdnlivetv', CDN);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('search with no query is empty without a network call', async () => {
  const rows = JSON.parse(await callProvider('cdnlivetv', 'search', ['', 1, {}]));
  assert.deepEqual(rows, []);
});

test('getVideoSources ignores a channel handle with no url', async () => {
  const src = JSON.parse(await callProvider('cdnlivetv', 'getVideoSources', ['ch:ESPN|']));
  assert.deepEqual(src, []);
});

test('getVideoSources ignores an event handle with no servers', async () => {
  const src = JSON.parse(await callProvider('cdnlivetv', 'getVideoSources', ['ev:Match|%5B%5D']));
  assert.deepEqual(src, []);
});

test('getDetail names a channel handle', async () => {
  const d = JSON.parse(await callProvider('cdnlivetv', 'getDetail', ['ch:Sky%20Sports|https://x/y']));
  assert.equal(d.title, 'Sky Sports');
  assert.equal(d.episodes.length, 1);
});

// --- Live ------------------------------------------------------------------
live('getLive folds every sport into one feed, in-play first', async () => {
  const items = JSON.parse(await callProvider('cdnlivetv', 'getLive', [{}]));
  assert.ok(Array.isArray(items), 'expected an array');
  assert.ok(items.length > 0, 'expected fixtures');
  for (const it of items) {
    assert.ok(it.url.startsWith('ev:'), 'fixture url uses the ev: scheme, got ' + it.url);
    assert.equal(it.sourceId, 'cdnlivetv');
    assert.ok(it.liveBadge, 'fixture has a status badge: ' + it.title);
  }
  const liveIdx = items.findIndex((i) => i.liveBadge === 'LIVE');
  const otherIdx = items.findIndex((i) => i.liveBadge !== 'LIVE');
  if (liveIdx !== -1 && otherIdx !== -1) {
    assert.ok(liveIdx < otherIdx, 'in-play fixtures lead the feed');
  }
});

live('getHome returns rails including live sports', async () => {
  const sections = JSON.parse(await callProvider('cdnlivetv', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  const titles = sections.map((s) => s.title);
  assert.ok(titles.includes('Live Sports'), 'has a Live Sports rail: ' + titles.join(', '));
  const items = sections.reduce((n, s) => n + s.items.length, 0);
  assert.ok(items > 0, 'rails carry items');
});

live('a channel resolves to a real HLS playlist', async () => {
  const chans = JSON.parse(await callProvider('cdnlivetv', 'popular', [{}]));
  assert.ok(chans.length > 0, 'expected channels');
  let resolved = null;
  for (const c of chans.slice(0, 12)) {
    const src = JSON.parse(await callProvider('cdnlivetv', 'getVideoSources', [c.url]));
    if (src.length && /\.m3u8/i.test(src[0].url)) { resolved = src[0]; break; }
  }
  assert.ok(resolved, 'at least one channel decodes to an .m3u8 url');
  assert.equal(resolved.container, 'hls');
  // The decoded playlist must actually be a playlist, not an error body.
  const res = await fetch(resolved.url, {
    headers: { 'User-Agent': resolved.headers['User-Agent'], Referer: resolved.headers.Referer },
  });
  assert.ok(res.ok, 'playlist fetch ok, got ' + res.status);
  const body = await res.text();
  assert.ok(body.startsWith('#EXTM3U'), 'body is an HLS playlist');
});
