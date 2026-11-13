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

live('getHome leads with the hero, then every rail', async () => {
  const sections = JSON.parse(await callProvider('framextv', 'getHome', [{}]));
  assert.ok(sections.length >= 5, 'expected several rails');
  assert.equal(sections[0].title, 'Featured');
  assert.ok(sections[0].items.length === 1, 'hero is a single item');
});

live('getFilters is built from the API genre list', async () => {
  const filters = JSON.parse(await callProvider('framextv', 'getFilters', []));
  const names = filters.map((f) => f.name);
  assert.deepEqual(names, ['Type', 'Genre', 'Year', 'Sort']);
  const genre = filters.find((f) => f.name === 'Genre');
  assert.ok(genre.values.length > 5, 'genre list came from /api/genres');
});

live('browseFilter maps a sheet selection to /api/discover', async () => {
  const selection = JSON.stringify([
    { name: 'Type', values: [{ name: 'TV Shows', value: 'tv' }], state: 0 },
    { name: 'Genre', values: [{ name: 'Animation', value: '16' }], state: 0 },
    { name: 'Sort', values: [{ name: 'Popularity', value: 'popularity' }], state: 0 }
  ]);
  const rows = JSON.parse(await callProvider('framextv', 'browseFilter', [selection, 1]));
  assert.ok(rows.length > 0, 'expected discover results');
  assert.ok(rows.every((r) => /^(movie|tv|anime):/.test(r.url)), 'urls carry a kind');
});

live('popular pages the trending feed', async () => {
  const p1 = JSON.parse(await callProvider('framextv', 'popular', [{ dateRange: 7, page: 1 }]));
  const p2 = JSON.parse(await callProvider('framextv', 'popular', [{ dateRange: 7, page: 2 }]));
  assert.ok(p1.length > 0 && p2.length > 0, 'both pages answer');
  assert.notEqual(p1[0].id, p2[0].id, 'page 2 differs from page 1');
});
