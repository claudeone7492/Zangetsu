import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const NS = new URL('../providers/netshort.js', import.meta.url);
loadProvider('netshort', NS);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('netshort', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'NetShort');
  assert.ok(info.baseUrl);
});

test('getVideoSources needs a full episode url', async () => {
  const none = JSON.parse(await callProvider('netshort', 'getVideoSources', ['ns:abc']));
  assert.deepEqual(none, []);
});

// --- Live ------------------------------------------------------------------
live('getHome returns the embedded catalogue as a rail', async () => {
  const sections = JSON.parse(await callProvider('netshort', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected sections');
  assert.ok(sections[0].items.length > 0, 'expected items');
  const it = sections[0].items[0];
  assert.ok(it.id && it.title && it.url, 'items are MediaItem-shaped');
  assert.ok(it.url.startsWith('ns:'), 'url carries the ns: prefix, got ' + it.url);
});

live('search filters the public catalogue by title', async () => {
  const rows = JSON.parse(await callProvider('netshort', 'search', ['love', 1, {}]));
  assert.ok(Array.isArray(rows), 'expected an array');
  assert.ok(rows.every((r) => /love/i.test(r.title)), 'every hit matches the query');
});

live('show: home -> detail -> first episode stream', async () => {
  const sections = JSON.parse(await callProvider('netshort', 'getHome', [{}]));
  const show = sections[0].items[0];
  const detail = JSON.parse(await callProvider('netshort', 'getDetail', [show.url, {}]));
  assert.ok(detail.title && detail.title.length > 0, 'expected a title');
  assert.ok(Array.isArray(detail.episodes) && detail.episodes.length > 0, 'expected episodes');
  const sources = JSON.parse(
    await callProvider('netshort', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected a source');
  assert.ok(sources[0].url, 'source has a url');
});
