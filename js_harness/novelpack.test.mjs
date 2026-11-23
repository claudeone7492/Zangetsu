import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const providers = [
  ['novelbuddy', 'https://novelbuddy.me/lord-of-the-mysteries'],
  ['novelfull', 'https://novelfull.com/lord-of-the-mysteries.html'],
  ['novelhi', 'https://novelhi.com/novel/action/lord-of-the-mysteries'],
  ['fanmtl', 'https://www.fanmtl.com/novel/lord-of-the-mysteries-2-circle-of-inevitability.html'],
  ['novelcool', 'https://www.novelcool.com/novel/Overlord-WN.html'],
  ['novelping', 'https://novelping.com/book/lord-of-the-mysteries'],
  ['novelrare', 'https://novelrare.com/novel/lord-of-the-mysteries/'],
  ['wondernovels', 'https://wondernovels.com/novels/lord-of-enigma/'],
  ['wuxiaworld', 'https://wuxiaworld.site/novel/lord-of-mysteries-llc/'],
];

for (const [id] of providers) {
  loadProvider(id, new URL(`../providers/${id}.js`, import.meta.url));
}

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

for (const [id, url] of providers) {
  test(`${id}: declares a novel source`, async () => {
    const info = JSON.parse(await callProvider(id, 'getInfo', []));
    assert.equal(info.type, 'novel');
    assert.ok(info.name && info.baseUrl);
  });

  test(`${id}: getPages is a no-op`, async () => {
    const pages = JSON.parse(await callProvider(id, 'getPages', ['https://example.test/chapter-1']));
    assert.deepEqual(pages, []);
  });

  live(`${id}: browse, detail and chapter text`, async () => {
    const home = JSON.parse(await callProvider(id, 'getHome', [{}]));
    assert.ok(Array.isArray(home) && home.length >= 1, 'expected shelves');
    assert.ok(home.reduce((n, s) => n + (s.items || []).length, 0) > 0, 'shelves have items');

    const rows = JSON.parse(await callProvider(id, 'search', ['lord of the mysteries', 1, {}]));
    assert.ok(rows.length > 0, 'expected search hits');
    assert.ok(rows[0].title && rows[0].url);

    const detail = JSON.parse(await callProvider(id, 'getDetail', [url]));
    assert.equal(detail.type, 'novel');
    assert.ok(detail.title.length > 0);
    assert.ok(detail.chapters.length > 50, 'expected the full chapter archive');
    assert.ok(detail.chapters[0].url);

    const text = JSON.parse(await callProvider(id, 'getText', [detail.chapters[0].url]));
    assert.ok(text.text.length > 500, 'expected chapter text');
  });
}
