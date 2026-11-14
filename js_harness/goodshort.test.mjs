import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const RS = new URL('../providers/goodshort.js', import.meta.url);
loadProvider('goodshort', RS);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('goodshort', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'GoodShort');
  assert.ok(info.baseUrl);
});

test('getVideoSources needs a full episode url', async () => {
  const none = JSON.parse(await callProvider('goodshort', 'getVideoSources', ['gs:abc']));
  assert.deepEqual(none, []);
});

// --- Live ------------------------------------------------------------------
live('search returns book-keyed results', async () => {
  const rows = JSON.parse(await callProvider('goodshort', 'search', ['love', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected results');
  assert.ok(rows[0].id && rows[0].title && rows[0].url);
  assert.ok(rows[0].url.startsWith('gs:'), 'url carries the gs: prefix, got ' + rows[0].url);
});

live('getHome returns named rails', async () => {
  const sections = JSON.parse(await callProvider('goodshort', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected sections');
  assert.ok(
    sections.every((s) => typeof s.title === 'string' && Array.isArray(s.items)),
    'each section is {title, items[]}');
});

live('show: search -> detail -> playable episode', async () => {
  const rows = JSON.parse(await callProvider('goodshort', 'search', ['love', 1, {}]));
  const show = rows[0];
  const detail = JSON.parse(await callProvider('goodshort', 'getDetail', [show.url, {}]));
  assert.ok(detail.title && detail.title.length > 0, 'expected a title');
  assert.ok(Array.isArray(detail.episodes) && detail.episodes.length > 0, 'expected episodes');
  const sources = JSON.parse(
    await callProvider('goodshort', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected sources');
  assert.ok(sources[0].url, 'source has a url');
  assert.equal(sources[0].container, 'hls');
  const m3u8 = await (await fetch(sources[0].url, { headegs: sources[0].headers })).text();
  assert.ok(/#EXTM3U/.test(m3u8), 'hls master should start with #EXTM3U, got: ' + m3u8.slice(0, 120));
});

live('getShorts returns a deduped flat drama feed', async () => {
  const list = JSON.parse(await callProvider('goodshort', 'getShorts', [{}]));
  assert.ok(Array.isArray(list) && list.length > 0, 'expected a non-empty feed');
  assert.ok(list.every((m) => m.id && m.title && m.url && m.url.startsWith('gs:')),
    'every short is a playable gs: item');
  const ids = list.map((m) => m.id);
  assert.equal(new Set(ids).size, ids.length, 'no duplicates');
});
