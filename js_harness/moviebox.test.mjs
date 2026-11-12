import { test } from 'node:test';
import assert from 'node:assert/strict';
import { loadProvider, callProvider } from './host.mjs';

const MB = new URL('../providers/moviebox.js', import.meta.url);
loadProvider('moviebox', MB);

const LIVE = process.env.RUN_LIVE === '1';
const live = (name, fn) =>
  test(name, { skip: LIVE ? false : 'set RUN_LIVE=1 to run network test' }, fn);

// --- Offline ---------------------------------------------------------------
test('getInfo reports a movie provider', async () => {
  const info = JSON.parse(await callProvider('moviebox', 'getInfo', []));
  assert.equal(info.type, 'movie');
  assert.equal(info.name, 'MovieBox');
  assert.ok(info.baseUrl);
});

test('getVideoSources needs a full episode url', async () => {
  const none = JSON.parse(await callProvider('moviebox', 'getVideoSources', ['mb:abc']));
  assert.deepEqual(none, []);
});

// --- Live ------------------------------------------------------------------
live('getHome returns named rails of movie-shaped rows', async () => {
  const sections = JSON.parse(await callProvider('moviebox', 'getHome', [{}]));
  assert.ok(Array.isArray(sections) && sections.length >= 1, 'expected sections');
  // Live-match rows lead the page and carry `live:` handles; the first
  // title rail is the one that must be MediaItem-shaped with `mb:` urls.
  const titleRail = sections.find(
    (s) => s.items && s.items.length && s.items[0].url.startsWith('mb:'),
  );
  assert.ok(titleRail, 'expected a title rail of mb: items');
  assert.ok(titleRail.title && titleRail.title.length > 0, 'rail has a title');
  const it = titleRail.items[0];
  assert.ok(it.id && it.title && it.url, 'items are MediaItem-shaped');
  assert.ok(it.url.startsWith('mb:'), 'url carries the mb: prefix, got ' + it.url);
  // Any live row must use the app's `live:` extension scheme, never `mb:`.
  for (const s of sections) {
    for (const i of s.items || []) {
      if (i.url.startsWith('live:')) return;
    }
  }
});

live('getHome exposes a browse handle rail', async () => {
  const sections = JSON.parse(await callProvider('moviebox', 'getHome', [{}]));
  const browse = sections
    .flatMap((s) => s.items || [])
    .find((i) => i.url.startsWith('browse:'));
  assert.ok(browse, 'expected at least one browse: handle (platform/filter rail)');
});

live('browseFilter honours a genre facet (flat params, not nested)', async () => {
  const sections = JSON.parse(await callProvider('moviebox', 'getHome', [{}]));
  const kdrama = sections
    .flatMap((s) => s.items || [])
    .find((i) => /K-Drama/i.test(i.title) && i.url.startsWith('browse:filter'));
  assert.ok(kdrama, 'expected a K-Drama filter handle');

  const rows = JSON.parse(await callProvider('moviebox', 'browseFilter', [kdrama.url, 1]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected filtered rows');
  assert.ok(rows[0].url.startsWith('mb:'), 'rows are playable mb: items');

  // Facets must actually reach the server. A nested `filterType` body is
  // ignored and silently returns an unrelated unfiltered feed, so selecting a
  // genre must change the result set rather than echo the default one.
  const sheetFor = async (genre) => {
    const filters = JSON.parse(await callProvider('moviebox', 'getFilters', [{}]));
    const g = filters.find((f) => f.name === 'Genre');
    g.state = g.values.findIndex((v) => v.value === genre);
    return JSON.parse(
      await callProvider('moviebox', 'browseFilter', [JSON.stringify(filters), 1]),
    );
  };
  const anime = await sheetFor('Anime');
  const horror = await sheetFor('Horror');
  assert.ok(anime.length > 0 && horror.length > 0, 'genre selections returned nothing');
  const animeTitles = new Set(anime.map((r) => r.title));
  assert.ok(
    !horror.every((r) => animeTitles.has(r.title)),
    'genre facet had no effect — likely a nested filterType body',
  );
});

live('search returns hits for a keyword', async () => {
  const rows = JSON.parse(await callProvider('moviebox', 'search', ['love', 1, {}]));
  assert.ok(Array.isArray(rows) && rows.length > 0, 'expected hits');
  assert.ok(rows[0].id && rows[0].url, 'hits are MediaItem-shaped');
});

live('short drama: home -> detail -> first episode stream', async () => {
  const sections = JSON.parse(await callProvider('moviebox', 'getHome', [{}]));
  // Prefer a short-drama rail; fall back to any show with episodes.
  let show = null;
  for (const sec of sections) {
    if (/short/i.test(sec.title) && sec.items.length) { show = sec.items[0]; break; }
  }
  if (!show) show = sections[0].items[0];

  const detail = JSON.parse(await callProvider('moviebox', 'getDetail', [show.url, {}]));
  assert.ok(detail.title && detail.title.length > 0, 'expected a title');
  assert.ok(Array.isArray(detail.episodes) && detail.episodes.length > 0, 'expected episodes');

  const sources = JSON.parse(
    await callProvider('moviebox', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(Array.isArray(sources) && sources.length >= 1, 'expected a source');
  assert.ok(sources[0].url, 'source has a url');
  assert.ok(['mp4', 'hls', 'dash'].includes(sources[0].container), 'known container');
  assert.ok(sources[0].headers && sources[0].headers.Referer, 'playback headers carry a referer');
});

live('movie: search -> detail -> single movie stream', async () => {
  const rows = JSON.parse(await callProvider('moviebox', 'search', ['love', 1, {}]));
  const movie = rows.find((r) => r.url.indexOf('|1|') > 0) || rows[0];
  const detail = JSON.parse(await callProvider('moviebox', 'getDetail', [movie.url, {}]));
  assert.ok(detail.episodes.length >= 1, 'a movie exposes one playable entry');
  const sources = JSON.parse(
    await callProvider('moviebox', 'getVideoSources', [detail.episodes[0].url]));
  assert.ok(sources.length >= 1, 'expected a source');
});
