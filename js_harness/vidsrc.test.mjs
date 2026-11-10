import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const VS = new URL('../providers/vidsrc.js', import.meta.url);
loadProvider('vidsrc', VS);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) => test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('vidsrc', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'VidSrc');
  assert.ok(info.baseUrl);
});

// --- Live ------------------------------------------------------------------
live('search returns IMDb-keyed rows', async () => {
  const rows = JSON.parse(await callProvider('vidsrc', 'search', ['inception', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected results');
  assert.ok(/^(movie|series):/.test(rows[0].url), 'url carries a kind prefix, got ' + rows[0].url);
});

live('movie: detail -> playable proxied HLS', async () => {
  const rows = JSON.parse(await callProvider('vidsrc', 'search', ['inception', 1, {}]));
  const movie = rows.find((r) => r.url.startsWith('movie:')) || rows[0];
  const detail = JSON.parse(await callProvider('vidsrc', 'getDetail', [movie.url, {}]));
  assert.ok(detail.tmdbId, 'detail carries a TMDB id');
  const sources = JSON.parse(
    await callProvider('vidsrc', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected sources');
  assert.ok(sources[0].url.startsWith('https://netweb-cvu7.onrender.com/proxy'),
    'source is routed through the gateway proxy, got ' + sources[0].url);
  const m3u8 = await (await fetch(sources[0].url, { headers: sources[0].headers })).text();
  assert.ok(/#EXTM3U/.test(m3u8), 'proxied HLS should start with #EXTM3U, got: ' + m3u8.slice(0, 120));
});
