// Tapas provider — https://tapas.io
//
// Tapas hosts BOTH novels and comics, and the two are genuinely different
// content kinds, so this one file registers as TWO bundled sources and picks
// its behaviour from the id the runtime wraps it with:
//
//   tapas         → novels   (category_type=NOVEL, search t=NOVELS, type novel)
//   tapas-comics  → comics   (category_type=COMIC, search t=COMICS, type manga)
//
// A novel chapter is HTML text; a comic chapter is a list of page images.
// Splitting the id keeps each half honest about its type — the detail screen
// routes novel→NovelReaderScreen and manga→MangaReaderScreen off `detail.type`
// — while the two share every fetch helper below.
//
// Endpoints (all public, no auth):
//   home    → story-api.tapas.io/cosmos/api/v1/landing/<rail>?category_type=…
//             rails: ranking | original | free | daily | completed
//             (…/layout 500s and …/landing/new is empty, so neither is used)
//   search  → tapas.io/search?q=…&t=NOVELS|COMICS&pageNumber=N  (HTML scrape of
//             li.search-item-wrap; data-series-type separates books/comics)
//   series  → tapas.io/series/<id|slug>            JSON (needs XHR header)
//   meta    → tapas.io/series/<id>/info            JSON: description + creators
//   chapters→ tapas.io/series/<id>/episodes?page=N JSON, 20/page, pagination
//             carries `total`, so the remaining pages are fetched in parallel
//   episode → tapas.io/episode/<id>                JSON: data.html
//             · novel  → <article class="viewer__body …"> holds the text
//             · comic  → <img … data-src="…"> holds each page URL
//
// Cover art: story-api assetProperty paths carry no extension — `.webp`
// resolves for every item checked (jpg misses some), so that is appended.
// The series JSON `thumb_url` (us-a host) already ends in an extension.

var SOURCE_ID = (typeof __SOURCE_ID !== 'undefined' && __SOURCE_ID)
  ? String(__SOURCE_ID) : 'tapas';

var SITE = 'https://tapas.io';
var STORY_API = 'https://story-api.tapas.io/cosmos/api/v1';
var REFERER = SITE + '/';

// 'tapas-comics' (or any id ending in -comics) is the comic half.
var IS_COMIC = /comics?$/i.test(SOURCE_ID);
var CATEGORY = IS_COMIC ? 'COMIC' : 'NOVEL';
var SEARCH_TYPE = IS_COMIC ? 'COMICS' : 'NOVELS';
var TYPE = IS_COMIC ? 'manga' : 'novel';

// Chapters are pulled newest→oldest across pages; bound the walk so a
// pathological series can't fan out unbounded. 60 pages = 1200 chapters.
var MAX_PAGES = 60;

function getInfo() {
  return {
    name: IS_COMIC ? 'Tapas Comics' : 'Tapas',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/favicon.ico',
    type: TYPE,
    version: '1.0.0'
  };
}

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _jsonHeaders() {
  return { 'Accept': 'application/json', 'X-Requested-With': 'XMLHttpRequest', 'Referer': REFERER };
}

function _htmlHeaders() {
  return { 'Accept': 'text/html,application/xhtml+xml', 'Referer': REFERER };
}

async function _get(url, json) {
  var res = await fetch(url, { headers: json ? _jsonHeaders() : _htmlHeaders() });
  if (res.status !== 200) throw new Error('HTTP ' + res.status + ' ' + url);
  return res.body || '';
}

async function _getJson(url) {
  var body = await _get(url, true);
  var data = JSON.parse(body);
  // Tapas wraps payloads as {code,msg,type,data}. The story-api landing
  // endpoints return the bare object instead.
  return data && data.data !== undefined ? data.data : data;
}

function _seriesId(url) {
  var m = String(url).match(/\/series\/([^/?#]+)/i);
  var slug = m ? m[1] : String(url);
  return /^\d+$/.test(slug) ? slug : slug;
}

function _seriesUrl(slug) {
  return SITE + '/series/' + slug;
}

function _episodeUrl(id) {
  return SITE + '/episode/' + id;
}

function _episodeId(url) {
  var m = String(url).match(/\/episode\/(\d+)/) || String(url).match(/^tapas:(\d+)$/)
    || String(url).match(/(\d{4,})/);
  return m ? m[1] : String(url);
}

function _assetUrl(asset) {
  if (!asset || !asset.path) return null;
  var p = asset.path;
  if (/\.(jpg|jpeg|png|webp|gif)$/i.test(p)) return p;
  return p + '.webp';
}

function _coverFromAssets(assetProperty) {
  if (!assetProperty) return null;
  return _assetUrl(assetProperty.thumbnailImage)
    || _assetUrl(assetProperty.bookCoverImage)
    || null;
}

function _cardFromLanding(it) {
  return {
    id: String(it.seriesId),
    title: _clean(it.title),
    cover: _coverFromAssets(it.assetProperty),
    url: _seriesUrl(it.seriesId),
    author: (it.authorList && it.authorList.length) ? _clean(it.authorList[0]) : '',
    description: _clean(it.description || ''),
    type: TYPE
  };
}

async function _landingRow(title, rail) {
  var url = STORY_API + '/landing/' + rail + '?category_type=' + CATEGORY + '&page=0&size=20';
  var data;
  try { data = await _getJson(url); } catch (e) {
    console.log('tapas landing ' + rail + ' failed: ' + e);
    return null;
  }
  var items = (data && data.items) || [];
  var cards = items.map(_cardFromLanding);
  return cards.length ? { title: title, items: cards } : null;
}

async function getHome(opts) {
  var rails = [
    { title: 'Top ' + (IS_COMIC ? 'Comics' : 'Novels'), rail: 'ranking' },
    { title: 'Original', rail: 'original' },
    { title: 'Free to Read', rail: 'free' },
    { title: 'Daily Updates', rail: 'daily' },
    { title: 'Completed', rail: 'completed' }
  ];
  var results = await Promise.all(rails.map(function(r) { return _landingRow(r.title, r.rail); }));
  var out = [];
  for (var i = 0; i < results.length; i++) if (results[i]) out.push(results[i]);
  console.log('tapas ' + SOURCE_ID + ' home rows: ' + out.length);
  return out;
}

// One `li.search-item-wrap` block → card. Tapas wraps matched words in
// <strong class="word-highlight">, and the title lives in <p class="title">.
function _searchCard(block) {
  var idM = block.match(/data-series-id="(\d+)"/);
  var typeM = block.match(/data-series-type="([^"]+)"/);
  var hrefM = block.match(/href="(\/series\/[^"]+)"/);
  if (!idM || !hrefM) return null;
  var seriesType = typeM ? typeM[1] : '';
  // The search endpoint is already type-scoped, but guard the odd cross-post:
  // books carry COMMUNITY_BOOKS, comics COMMUNITY.
  var isBook = /BOOK/i.test(seriesType);
  if (isBook === IS_COMIC) return null;
  var titleM = block.match(/<p class="title[^"]*">([\s\S]*?)<\/p>/i);
  var imgM = block.match(/<img[^>]+src="([^"]+)"/i);
  return {
    id: idM[1],
    title: titleM ? _clean(titleM[1]) : '',
    cover: imgM ? imgM[1] : null,
    url: SITE + hrefM[1],
    author: '',
    type: TYPE
  };
}

async function search(query, page, opts) {
  var p = (page && page > 0) ? page : 1;
  var url = SITE + '/search?q=' + encodeURIComponent(query || '') + '&t=' + SEARCH_TYPE + '&pageNumber=' + p;
  var html = await _get(url, false);
  var re = /<li class="search-item-wrap">([\s\S]*?)<\/li>/g;
  var out = [];
  var m;
  while ((m = re.exec(html)) !== null) {
    var card = _searchCard(m[1]);
    if (card && card.title) out.push(card);
  }
  console.log('tapas ' + SOURCE_ID + ' search "' + query + '" p' + p + ' hits: ' + out.length);
  return out;
}

function _statusFromLabel(label) {
  var t = _clean(label).toLowerCase();
  if (t.indexOf('complet') !== -1) return 'completed';
  if (t.indexOf('ongoing') !== -1) return 'ongoing';
  if (t.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

function _detailFromInfoHtml(html) {
  var out = { description: '', authors: [], status: 'unknown' };
  var descM = html.match(/<span class="description__body"[^>]*>([\s\S]*?)<\/span>/i);
  if (descM) out.description = _clean(descM[1]);
  var re = /<a class="creator__item[^"]*"[^>]*>([^<]+)<\/a>/g;
  var m;
  while ((m = re.exec(html)) !== null) {
    var name = _clean(m[1]);
    if (name && out.authors.indexOf(name) === -1) out.authors.push(name);
  }
  // Tapas spells status out in a schedule label ("Completed series") or, for
  // a running series, only a cadence ("Updates every Fri"). Absent both, the
  // series is finished-with or otherwise unlabelled — leave it unknown.
  var statusM = html.match(/<span class="schedule-label">([^<]*)<\/span>/i);
  if (statusM) {
    var label = _clean(statusM[1]);
    out.status = _statusFromLabel(label);
    if (out.status === 'unknown' && /updat|daily|weekly|every/i.test(label)) {
      out.status = 'ongoing';
    }
  }
  return out;
}

function _chapter(id, title, scene, date, thumbnail) {
  return {
    id: 'tapas:' + id,
    title: _clean(title) || ('Chapter ' + scene),
    number: scene,
    url: _episodeUrl(id),
    date: date || '',
    thumbnail: thumbnail || null
  };
}

// Pages are 20 chapters each (a fixed server cap), newest-first. Page 1
// carries `total`, so the rest are fetched in parallel instead of walked.
async function _chapters(seriesId) {
  var first = await _getJson(SITE + '/series/' + seriesId + '/episodes?page=1');
  var eps = (first && first.episodes) || [];
  var total = first && first.pagination && first.pagination.total;
  var pages = total ? Math.ceil(total / 20) : 1;
  if (pages > MAX_PAGES) pages = MAX_PAGES;
  if (pages > 1) {
    var rest = [];
    for (var p = 2; p <= pages; p++) {
      rest.push(_getJson(SITE + '/series/' + seriesId + '/episodes?page=' + p)
        .then(function(d) { return (d && d.episodes) || []; })
        .catch(function() { return []; }));
    }
    var got = await Promise.all(rest);
    for (var i = 0; i < got.length; i++) eps = eps.concat(got[i]);
  }
  var seen = {};
  var chapters = [];
  for (var j = 0; j < eps.length; j++) {
    var e = eps[j];
    if (!e || seen[e.id]) continue;
    seen[e.id] = true;
    chapters.push(_chapter(e.id, e.title, e.scene, e.publish_date || e.relative_publish_date, e.thumb_url));
  }
  // Newest-first from the API; the reader wants oldest-first by scene.
  chapters.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
  for (var k = 0; k < chapters.length; k++) chapters[k].number = k + 1;
  return chapters;
}

async function getDetail(url) {
  var slug = _seriesId(url);
  var series = await _getJson(_seriesUrl(slug));
  var id = series && series.id ? String(series.id) : slug;

  var meta = { description: '', authors: [], status: 'unknown' };
  try {
    var infoHtml = await _getJson(SITE + '/series/' + id + '/info');
    if (infoHtml && infoHtml.html) meta = _detailFromInfoHtml(infoHtml.html);
  } catch (e) {
    console.log('tapas info failed: ' + e);
  }

  var chapters = await _chapters(id);
  var genres = [];
  if (series && series.genre && series.genre.name) genres.push(series.genre.name);

  console.log('tapas ' + SOURCE_ID + ' detail: title=' + (series && series.title)
    + ' chapters=' + chapters.length + ' status=' + meta.status);

  return {
    id: id,
    sourceId: SOURCE_ID,
    title: _clean(series && series.title),
    cover: (series && series.thumb_url) || null,
    url: _seriesUrl(slug),
    author: meta.authors[0] || '',
    authors: meta.authors,
    status: meta.status,
    description: meta.description,
    genres: genres,
    chapters: chapters,
    type: TYPE
  };
}

async function getEpisodes(url) {
  return _chapters(_seriesId(url));
}

function getChapters(url) {
  return getEpisodes(url);
}

// Comic half: each <img class="content__img js-lazy" … data-src="…"> is a page.
// data-src is HTML-escaped, so &amp; must be turned back into & before the URL
// will fetch (the signed `?__token__=…` query is what 403s otherwise).
async function getPages(chapterUrl) {
  if (!IS_COMIC) return [];
  var id = _episodeId(chapterUrl);
  var data = await _getJson(_episodeUrl(id));
  var html = (data && data.html) || '';
  var re = /<img[^>]+class="[^"]*content__img[^"]*"[^>]*data-src="([^"]+)"/gi;
  var out = [];
  var m;
  while ((m = re.exec(html)) !== null) {
    var src = m[1].replace(/&amp;/g, '&').replace(/&#38;/g, '&');
    if (!/^https?:\/\//i.test(src)) continue;
    out.push({ url: src, index: out.length, headers: { Referer: chapterUrl } });
  }
  console.log('tapas comic pages: ' + out.length + ' for ep ' + id);
  if (out.length === 0) {
    throw new Error('Tapas episode ' + id + ' has no readable pages (locked or empty)');
  }
  return out;
}

// Novel half: the text lives in <article class="viewer__body …">.
async function getText(chapterUrl) {
  if (IS_COMIC) return { html: '', title: '' };
  var id = _episodeId(chapterUrl);
  var data = await _getJson(_episodeUrl(id));
  var html = (data && data.html) || '';
  var artM = html.match(/<article[^>]*class="[^"]*viewer__body[^"]*"[^>]*>([\s\S]*?)<\/article>/i);
  if (!artM) {
    throw new Error('Tapas episode ' + id + ' has no readable text (locked or empty)');
  }
  var body = artM[1]
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<ins[\s\S]*?<\/ins>/gi, '');
  var titleM = html.match(/data-ep-title="([^"]*)"/) || html.match(/<p class="title">([\s\S]*?)<\/p>/i);
  console.log('tapas novel text: ep ' + id + ' chars=' + body.length);
  return { html: body, title: titleM ? _clean(titleM[1]) : '' };
}

function getChapterContent(chapterUrl) {
  return getText(chapterUrl);
}
