import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('mangakakalot', new URL('../providers/mangakakalot.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports a manga provider', async () => {
  const info = JSON.parse(await callProvider('mangakakalot', 'getInfo', []));
  assert.equal(info.type, 'manga');
  assert.equal(info.name, 'Mangakakalot');
  assert.ok(info.baseUrl);
});

live('getHome returns at least one rail', async () => {
  const sections = JSON.parse(await callProvider('mangakakalot', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  assert.ok(sections[0].items.length > 0, 'rail has items');
});

live('search finds manga by title', async () => {
  const rows = JSON.parse(await callProvider('mangakakalot', 'search', ['one piece', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url);
});

live('getDetail returns chapters', async () => {
  const rows = JSON.parse(await callProvider('mangakakalot', 'search', ['one piece', 1, {}]));
  const d = JSON.parse(await callProvider('mangakakalot', 'getDetail', [rows[0].url]));
  assert.ok(d.title.length > 0);
  assert.ok(d.chapters.length > 0);
});

live('getPages returns image URLs', async () => {
  const rows = JSON.parse(await callProvider('mangakakalot', 'search', ['one piece', 1, {}]));
  const d = JSON.parse(await callProvider('mangakakalot', 'getDetail', [rows[0].url]));
  const pages = JSON.parse(await callProvider('mangakakalot', 'getPages', [d.chapters[0].url]));
  assert.ok(pages.length > 0, 'expected pages');
  assert.match(pages[0].url, /^https?:\/\//);
});
