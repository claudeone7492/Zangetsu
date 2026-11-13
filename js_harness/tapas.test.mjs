import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

// One file, two bundled sources: `tapas` (novels) and `tapas-comics` (comics).
const file = new URL('../providers/tapas.js', import.meta.url);
loadProvider('tapas', file);
loadProvider('tapas-comics', file);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo types each half from its own source id', async () => {
  const novel = JSON.parse(await callProvider('tapas', 'getInfo', []));
  assert.equal(novel.type, 'novel');
  assert.equal(novel.name, 'Tapas');
  assert.equal(novel.baseUrl, 'https://tapas.io');

  const comic = JSON.parse(await callProvider('tapas-comics', 'getInfo', []));
  assert.equal(comic.type, 'manga');
  assert.equal(comic.name, 'Tapas Comics');
});

test('each half short-circuits the other content kind', async () => {
  // getPages on the NOVEL id is a no-op, and getText on the COMIC id is a
  // no-op — no network, because each half guards on its declared type.
  const pages = JSON.parse(await callProvider('tapas', 'getPages', ['https://tapas.io/episode/1']));
  assert.deepEqual(pages, []);
  const text = JSON.parse(await callProvider('tapas-comics', 'getText', ['https://tapas.io/episode/1']));
  assert.equal(text.html, '');
});

live('novel: getHome returns shelves of story cards', async () => {
  const sections = JSON.parse(await callProvider('tapas', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected shelves');
  assert.ok(sections[0].items.length > 0, 'shelf has items');
  assert.match(sections[0].items[0].url, /\/series\//);
  assert.equal(sections[0].items[0].type, 'novel');
});

live('comic: getHome returns shelves of comic cards', async () => {
  const sections = JSON.parse(await callProvider('tapas-comics', 'getHome', [{}]));
  assert.ok(sections.length >= 1, 'expected shelves');
  assert.equal(sections[0].items[0].type, 'manga');
});

live('novel: search finds stories', async () => {
  const rows = JSON.parse(await callProvider('tapas', 'search', ['romance', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url.includes('/series/'));
  assert.equal(rows[0].type, 'novel');
});

live('comic: search finds comics only', async () => {
  const rows = JSON.parse(await callProvider('tapas-comics', 'search', ['magic', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  for (const r of rows) assert.equal(r.type, 'manga');
});

live('novel: getDetail returns metadata and the full chapter list', async () => {
  const d = JSON.parse(await callProvider('tapas', 'getDetail', ['https://tapas.io/series/267008']));
  assert.equal(d.type, 'novel');
  assert.ok(d.title.length > 0);
  assert.ok(d.description && d.description.length > 100, 'expected a blurb');
  assert.ok(d.authors.length > 0, 'expected creators');
  assert.ok(d.chapters.length > 500, 'expected the paginated full list (543)');
  assert.equal(d.chapters[0].number, 1, 'chapters ordered oldest-first');
  assert.equal(d.chapters[0].url, 'https://tapas.io/episode/2922705');
});

live('novel: getText returns chapter text', async () => {
  const d = JSON.parse(await callProvider('tapas', 'getDetail', ['https://tapas.io/series/267008']));
  const c = JSON.parse(await callProvider('tapas', 'getText', [d.chapters[0].url]));
  assert.ok(c.html && c.html.length > 500, 'expected substantial text');
  assert.ok(c.title.length > 0);
});

live('comic: getDetail + getPages walk to page images', async () => {
  const d = JSON.parse(await callProvider('tapas-comics', 'getDetail', ['https://tapas.io/series/205543']));
  assert.equal(d.type, 'manga');
  assert.ok(d.chapters.length > 100, 'expected the paginated full list (232)');
  const pages = JSON.parse(await callProvider('tapas-comics', 'getPages', [d.chapters[0].url]));
  assert.ok(pages.length > 0, 'expected page images');
  assert.match(pages[0].url, /^https:\/\/us-a\.tapas\.io\//);
  assert.ok(!pages[0].url.includes('&amp;'), 'token query must be unescaped');
  const res = await fetch(pages[0].url, { headers: pages[0].headers });
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type') || '', /^image\//);
});
