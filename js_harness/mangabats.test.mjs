import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('mangabats', new URL('../providers/mangabats.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports a manga provider', async () => {
  const info = JSON.parse(await callProvider('mangabats', 'getInfo', []));
  assert.equal(info.type, 'manga');
  assert.equal(info.name, 'MangaBat');
  assert.ok(info.baseUrl);
});

live('getHome returns rails of manga cards', async () => {
  const sections = JSON.parse(await callProvider('mangabats', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  const items = sections[0].items;
  assert.ok(items.length > 0, 'rail has items');
  assert.ok(items[0].url.startsWith('https://www.mangabats.com/manga/'));
});

live('search finds manga by title', async () => {
  const rows = JSON.parse(await callProvider('mangabats', 'search', ['solo', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url);
});

live('getDetail returns a chapter list', async () => {
  const rows = JSON.parse(await callProvider('mangabats', 'search', ['solo', 1, {}]));
  const d = JSON.parse(await callProvider('mangabats', 'getDetail', [rows[0].url]));
  assert.ok(d.title.length > 0);
  assert.ok(d.chapters.length > 0);
  assert.match(d.chapters[0].url, /\/manga\/.+\/chapter-/);
});

live('getPages returns chapter images', async () => {
  const rows = JSON.parse(await callProvider('mangabats', 'search', ['solo', 1, {}]));
  const d = JSON.parse(await callProvider('mangabats', 'getDetail', [rows[0].url]));
  const pages = JSON.parse(await callProvider('mangabats', 'getPages', [d.chapters[0].url]));
  assert.ok(pages.length > 0, 'expected pages');
  assert.match(pages[0].url, /^https?:\/\//);
});
