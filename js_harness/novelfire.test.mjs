import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('novelfire', new URL('../providers/novelfire.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports a novel provider', async () => {
  const info = JSON.parse(await callProvider('novelfire', 'getInfo', []));
  assert.equal(info.type, 'novel');
  assert.equal(info.name, 'NovelFire');
  assert.ok(info.baseUrl);
});

live('getHome returns rails of novels', async () => {
  const sections = JSON.parse(await callProvider('novelfire', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  assert.ok(sections[0].items.length > 0, 'rail has items');
});

live('search finds novels by title', async () => {
  const rows = JSON.parse(await callProvider('novelfire', 'search', ['shadow', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url);
});

live('getDetail returns a chapter list', async () => {
  const rows = JSON.parse(await callProvider('novelfire', 'search', ['shadow', 1, {}]));
  const d = JSON.parse(await callProvider('novelfire', 'getDetail', [rows[0].url]));
  assert.ok(d.title.length > 0);
  assert.ok(d.chapters.length > 0);
});

live('getChapterContent returns chapter text', async () => {
  const rows = JSON.parse(await callProvider('novelfire', 'search', ['shadow', 1, {}]));
  const d = JSON.parse(await callProvider('novelfire', 'getDetail', [rows[0].url]));
  const c = JSON.parse(await callProvider('novelfire', 'getChapterContent', [d.chapters[0].url]));
  assert.ok(c.text && c.text.length > 100, 'expected substantial text');
});
