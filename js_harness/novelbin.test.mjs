import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('novelbin', new URL('../providers/novelbin.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports a novel provider', async () => {
  const info = JSON.parse(await callProvider('novelbin', 'getInfo', []));
  assert.equal(info.type, 'novel');
  assert.equal(info.name, 'NovelBin');
  assert.ok(info.baseUrl);
});

test('exposes getHome, search and getChapterContent', async () => {
  const info = JSON.parse(await callProvider('novelbin', 'getInfo', []));
  assert.equal(info.type, 'novel');
  assert.doesNotThrow(() => callProvider('novelbin', 'getHome', [{}]));
});

live('getHome returns rails of novels', async () => {
  const sections = JSON.parse(await callProvider('novelbin', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  assert.ok(sections[0].items.length > 0, 'rail has items');
  assert.ok(sections[0].items[0].url.includes('/book/'), 'cards link to books');
});

live('search finds novels by title', async () => {
  const rows = JSON.parse(await callProvider('novelbin', 'search', ['shadow', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url);
});

live('getDetail returns metadata and the full chapter list', async () => {
  const rows = JSON.parse(await callProvider('novelbin', 'search', ['shadow', 1, {}]));
  const d = JSON.parse(await callProvider('novelbin', 'getDetail', [rows[0].url]));
  assert.ok(d.title.length > 0);
  assert.ok(d.description && d.description.length > 50, 'expected a synopsis');
  assert.ok(d.genres && d.genres.length > 0, 'expected genres');
  // The detail page only renders 30 chapters inline; the chapter-list endpoint
  // supplies the rest, so a longer novel must exceed that.
  assert.ok(d.chapters.length > 30, 'expected the full chapter list');
});

live('getChapterContent returns chapter text', async () => {
  const rows = JSON.parse(await callProvider('novelbin', 'search', ['shadow', 1, {}]));
  const d = JSON.parse(await callProvider('novelbin', 'getDetail', [rows[0].url]));
  const c = JSON.parse(await callProvider('novelbin', 'getChapterContent', [d.chapters[0].url]));
  assert.ok(c.text && c.text.length > 200, 'expected substantial text');
});
