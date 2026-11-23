import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('nuvio', new URL('../providers/nuvio.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports the Nuvio sports source', async () => {
  const info = JSON.parse(await callProvider('nuvio', 'getInfo', []));
  assert.equal(info.name, 'Nuvio Live Sports');
  assert.equal(info.type, 'movie');
  assert.ok(info.baseUrl);
});

live('getLive returns soccer fixtures with league info', async () => {
  const items = JSON.parse(await callProvider('nuvio', 'getLive', [{}]));
  assert.ok(items.length > 0, 'expected live fixtures');
  assert.ok(items.every((x) => x.liveSport === 'soccer'), 'football only');
  assert.ok(items.some((x) => x.liveInfo && x.liveInfo.length > 0), 'league info');
});

live('search finds a fixture by team name', async () => {
  const rows = JSON.parse(await callProvider('nuvio', 'search', ['arsenal', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].url.startsWith('nuviotv:'));
});

live('a fixture resolves to a playable HLS stream', async () => {
  const items = JSON.parse(await callProvider('nuvio', 'getLive', [{}]));
  const match = items.find((x) => x.liveBadge === 'LIVE') || items[0];
  const sources = JSON.parse(await callProvider('nuvio', 'getVideoSources', [match.url]));
  assert.ok(sources.length > 0, 'expected sources');
  assert.match(sources[0].url, /^https?:\/\//);
  assert.equal(sources[0].container, 'hls');
});
