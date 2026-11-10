import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const VL = new URL('../providers/vidlink.js', import.meta.url);
loadProvider('vidlink', VL);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) => test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('vidlink', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'VidLink');
  assert.ok(info.baseUrl);
});

// --- Live ------------------------------------------------------------------
live('search returns IMDb-keyed rows', async () => {
  const rows = JSON.parse(await callProvider('vidlink', 'search', ['inception', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected results');
  assert.ok(/^(movie|series):/.test(rows[0].url), 'url carries a kind prefix, got ' + rows[0].url);
});

live('movie: detail -> signed MP4 renditions', async () => {
  const rows = JSON.parse(await callProvider('vidlink', 'search', ['inception', 1, {}]));
  const movie = rows.find((r) => r.url.startsWith('movie:')) || rows[0];
  const detail = JSON.parse(await callProvider('vidlink', 'getDetail', [movie.url, {}]));
  assert.ok(detail.tmdbId, 'detail carries a TMDB id');
  const sources = JSON.parse(
    await callProvider('vidlink', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected sources');
  assert.ok(/^https?:\/\//.test(sources[0].url), 'source has an absolute url');
  assert.ok(['mp4', 'hls', 'unknown'].includes(sources[0].container), 'known container');
});
