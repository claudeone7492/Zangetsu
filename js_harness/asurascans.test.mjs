import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

loadProvider('asurascans', new URL('../providers/asurascans.js', import.meta.url));

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

test('getInfo reports a manga provider', async () => {
  const info = JSON.parse(await callProvider('asurascans', 'getInfo', []));
  assert.equal(info.type, 'manga');
  assert.equal(info.name, 'Asura Scans');
  assert.ok(info.baseUrl);
});

live('getHome returns browse rails', async () => {
  const sections = JSON.parse(await callProvider('asurascans', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected rails');
  assert.ok(sections[0].items.length > 0, 'rail has items');
  assert.ok(sections[0].items[0].url.includes('/comics/'));
});

live('search finds series by title', async () => {
  const rows = JSON.parse(await callProvider('asurascans', 'search', ['solo', 1, {}]));
  assert.ok(rows.length > 0, 'expected matches');
  assert.ok(rows[0].title.length > 0 && rows[0].url.includes('/comics/'));
});

live('getDetail returns a chapter list', async () => {
  const rows = JSON.parse(await callProvider('asurascans', 'search', ['solo', 1, {}]));
  const d = JSON.parse(await callProvider('asurascans', 'getDetail', [rows[0].url]));
  assert.ok(d.title.length > 0);
  assert.ok(d.chapters.length > 0);
  assert.match(d.chapters[0].url, /\/chapter\//);
});

live('getPages returns chapter images', async () => {
  const rows = JSON.parse(await callProvider('asurascans', 'search', ['solo', 1, {}]));
  const d = JSON.parse(await callProvider('asurascans', 'getDetail', [rows[0].url]));
  const pages = JSON.parse(await callProvider('asurascans', 'getPages', [d.chapters[0].url]));
  assert.ok(pages.length > 0, 'expected pages');
  assert.match(pages[0].url, /^https:\/\/cdn\.asurascans\.com\//);
});
