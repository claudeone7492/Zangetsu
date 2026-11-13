import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('inkitt', new URL('../providers/inkitt.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports a novel provider', async () => {
  const info = JSON.parse(await callProvider('inkitt', 'getInfo', []));
  assert.equal(info.type, 'novel');
  assert.equal(info.name, 'Inkitt');
  assert.ok(info.baseUrl);
});

test('exposes getHome, search and getChapterContent', async () => {
  assert.doesNotThrow(() => callProvider('inkitt', 'getHome', [{}]));
});

live('getHome returns story shelves', async () => {
  const sections = JSON.parse(await callProvider('inkitt', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected shelves');
  assert.ok(sections[0].items.length > 0, 'shelf has items');
  assert.ok(sections[0].items[0].url.includes('/stories/'), 'cards link to stories');
});

live('search finds stories', async () => {
  const rows = JSON.parse(await callProvider('inkitt', 'search', ['love', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url.includes('/stories/'));
});

live('getDetail returns metadata and the chapter list', async () => {
  // A stable, long, completed story used as the fixture.
  const d = JSON.parse(await callProvider('inkitt', 'getDetail', ['https://www.inkitt.com/stories/1700726']));
  assert.ok(d.title.length > 0);
  assert.ok(d.description && d.description.length > 100, 'expected a blurb');
  assert.ok(d.genres && d.genres.length > 0, 'expected genres');
  assert.ok(d.chapters.length > 20, 'expected the full chapter list');
  assert.equal(d.chapters[0].number, 1, 'chapters ordered oldest-first');
});

live('getChapterContent returns chapter text', async () => {
  const d = JSON.parse(await callProvider('inkitt', 'getDetail', ['https://www.inkitt.com/stories/1700726']));
  const c = JSON.parse(await callProvider('inkitt', 'getChapterContent', [d.chapters[0].url]));
  assert.ok(c.text && c.text.length > 500, 'expected substantial text');
});
