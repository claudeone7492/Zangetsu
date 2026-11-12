import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const MB = new URL('../providers/moviebox.js', import.meta.url);
loadProvider('moviebox', MB);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('moviebox', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'MovieBox');
  assert.ok(info.baseUrl);
});

test('getVideoSources needs a full episode url', async () => {
  const none = JSON.parse(await callProvider('moviebox', 'getVideoSources', ['mb:abc']));
  assert.deepEqual(none, []);
});

// --- Live ------------------------------------------------------------------
live('getHome returns named rails of movie-shaped rows', async () => {
  const sections = JSON.parse(await callProvider('moviebox', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected sections');
  assert.ok(sections[0].title && sections[0].title.length > 0, 'section has a title');
  const it = sections[0].items[0];
  assert.ok(it.id && it.title && it.url, 'items are MediaItem-shaped');
  assert.ok(it.url.startsWith('mb:'), 'url carries the mb: prefix, got ' + it.url);
});

live('search returns hits for a keyword', async () => {
  const rows = JSON.parse(await callProvider('moviebox', 'search', ['love', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected hits');
  assert.ok(rows[0].id && rows[0].url, 'hits are MediaItem-shaped');
});

live('short drama: home -> detail -> first episode stream', async () => {
  const sections = JSON.parse(await callProvider('moviebox', 'getHome', [{}]));
  // Prefer a short-drama rail; fall back to any show with episodes.
  let show = null;
  for (const sec of sections) {
    if (/short/i.test(sec.title) && sec.items.length) { show = sec.items[0]; break; }
  }
  if (!show) show = sections[0].items[0];

  const detail = JSON.parse(await callProvider('moviebox', 'getDetail', [show.url, {}]));
  assert.ok(detail.title && detail.title.length > 0, 'expected a title');
  assert.ok(Array.isArray(detail.episodes) && detail.episodes.length > 0, 'expected episodes');

  const sources = JSON.parse(
    await callProvider('moviebox', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected a source');
  assert.ok(sources[0].url, 'source has a url');
  assert.ok(['mp4', 'hls', 'dash'].includes(sources[0].container), 'known container');
  assert.ok(sources[0].headers && sources[0].headers.Referer, 'playback headers carry a referer');
});

live('movie: search -> detail -> single movie stream', async () => {
  const rows = JSON.parse(await callProvider('moviebox', 'search', ['love', 1, {}]));
  const movie = rows.find((r) => r.url.indexOf('|1|') > 0) || rows[0];
  const detail = JSON.parse(await callProvider('moviebox', 'getDetail', [movie.url, {}]));
  assert.ok(detail.episodes.length >= 1, 'a movie exposes one playable entry');
  const sources = JSON.parse(
    await callProvider('moviebox', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(sources.length >= 1, 'expected a source');
});
