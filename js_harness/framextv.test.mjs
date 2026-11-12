import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const FT = new URL('../providers/framextv.js', import.meta.url);
loadProvider('framextv', FT);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) => test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('framextv', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'frameXTV');
  assert.ok(info.baseUrl);
});

// --- Live ------------------------------------------------------------------
live('search returns TMDB-keyed results', async () => {
  const rows = JSON.parse(await callProvider('framextv', 'search', ['inception', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected results');
  assert.ok(rows[0].id && rows[0].title && rows[0].url);
  assert.ok(/^(movie|tv|anime):/.test(rows[0].url), 'url carries a kind prefix, got ' + rows[0].url);
});

live('getHome returns named rails', async () => {
  const sections = JSON.parse(await callProvider('framextv', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected sections');
  assert.ok(
    sections.every((s) => typeof s.title === 'string' && Array.isArray(s.items)),
    'each section is {title, items[]}');
});

live('movie: search -> detail -> playable sources', async () => {
  const rows = JSON.parse(await callProvider('framextv', 'search', ['inception', 1, {}]));
  const movie = rows.find((r) => r.url.startsWith('movie:')) || rows[0];
  const detail = JSON.parse(await callProvider('framextv', 'getDetail', [movie.url, {}]));
  assert.ok(detail.title && detail.title.length > 0, 'expected a title');
  assert.ok(Array.isArray(detail.episodes) && detail.episodes.length > 0, 'expected episodes');
  const sources = JSON.parse(
    await callProvider('framextv', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected sources');
  assert.ok(sources[0].url, 'source has a url');
  assert.ok(['hls', 'mp4', 'unknown'].includes(sources[0].container), 'known container');
  if (sources[0].container === 'hls') {
    const m3u8 = await (await fetch(sources[0].url, { headers: sources[0].headers })).text();
    assert.ok(/#EXTM3U/.test(m3u8), 'hls master should start with #EXTM3U, got: ' + m3u8.slice(0, 120));
  }
});

live('tv: detail lists episodes across seasons', async () => {
  const rows = JSON.parse(await callProvider('framextv', 'search', ['game of thrones', 1, {}]));
  const show = rows.find((r) => r.url.startsWith('tv:')) || rows[0];
  const detail = JSON.parse(await callProvider('framextv', 'getDetail', [show.url, {}]));
  assert.ok(Array.isArray(detail.episodes) && detail.episodes.length > 0, 'expected episodes');
  assert.ok(detail.episodes[0].url.includes(':'), 'episode url carries season:episode');
});
