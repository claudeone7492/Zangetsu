// NovelFire provider — https://novelfire.net
//
// Novel-type source (text chapters, no page images). Verified live:
//   * search  → /ajax/searchLive?keyword= returns a clean JSON payload
//   * browse  → /genre-all/sort-*/status-all/all-novel HTML grids
//   * detail  → h1.novel-title, .summary .content paragraphs, ul.chapter-list
//   * chapter → div#content paragraphs, paged via the pager links
//
// The chapter list is paged on the site (Shadow Slave is 33 pages). getDetail
// only walks a bounded prefix of those pages — the reader continues through
// nextUrl anyway, and the per-source call timeout is 30s.

var SOURCE_ID = 'novelfire';
var SITE = 'https://novelfire.net';
var REFERER = SITE + '/';
var LOGO = SITE + '/frontend/img/logo.png';
var MAX_CHAPTER_PAGES = 6;

function getInfo() {
  return {
    name: 'NovelFire',
    lang: 'en',
    baseUrl: SITE,
    logo: LOGO,
    type: 'novel',
    version: '1.0.0'
  };
}

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _all(html, re) {
  var out = [];
  var m;
  re.lastIndex = 0;
  while ((m = re.exec(html)) !== null) {
    out.push(m);
    if (m.index === re.lastIndex) re.lastIndex++;
  }
  return out;
}

function _slugFromUrl(url) {
  var m = String(url).match(/\/book\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

function _numFromUrl(url) {
  var m = String(url).match(/chapter-([0-9]+(?:[.-][0-9]+)?)/i);
  return m ? parseFloat(m[1]) : null;
}

function _normalizeStatus(s) {
  s = (s || '').toLowerCase();
  if (s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('complete') !== -1 || s.indexOf('finished') !== -1) return 'completed';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

// ── browse ──────────────────────────────────────────────────────────────────
// The explore grids share one markup: <li class="novel-item"><a href="/book/...">
// <figure class="novel-cover"><img data-src="...">…; the title is the anchor's
// title attribute (the visible text can be truncated to one line).
function _parseBrowse(html) {
  var out = [];
  var seen = {};
  var re = /<li[^>]*class="novel-item"[^>]*>([\s\S]*?)<\/li>/gi;
  var items = _all(html, re);
  for (var i = 0; i < items.length; i++) {
    var block = items[i][1];
    var linkM = block.match(/href="(\/book\/[^"]+)"/);
    if (!linkM) continue;
    var link = absUrl(linkM[1], SITE);
    if (seen[link]) continue;
    seen[link] = true;
    var titleM = block.match(/title="([^"]+)"/);
    var imgM = block.match(/<img[^>]+(?:data-src|src)="([^"]+)"/i);
    out.push({
      id: _slugFromUrl(link),
      title: _clean(titleM ? titleM[1] : ''),
      cover: imgM ? absUrl(imgM[1], SITE) : null,
      url: link,
      type: 'novel'
    });
  }
  return out;
}

async function _browseRow(title, sortSlug) {
  var url = SITE + '/genre-all/' + sortSlug + '/status-all/all-novel?page=1';
  var res = await fetch(url, { headers: { Referer: REFERER } });
  if (res.status !== 200) {
    console.log('novelfire home row HTTP ' + res.status + ' ' + title);
    return null;
  }
  var items = _parseBrowse(res.body || '');
  return items.length ? { title: title, items: items } : null;
}

async function getHome(opts) {
  opts = opts || {};
  var rows = [
    { title: 'Popular', sort: 'sort-popular' },
    { title: 'Latest Updates', sort: 'sort-updated' },
    { title: 'New Novels', sort: 'sort-new' }
  ];
  var sections = [];
  for (var i = 0; i < rows.length; i++) {
    try {
      var sec = await _browseRow(rows[i].title, rows[i].sort);
      if (sec) sections.push(sec);
    } catch (e) {
      console.log('novelfire home row failed: ' + rows[i].title + ' (' + e + ')');
    }
  }
  return sections;
}

async function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  if (q) {
    var url = SITE + '/ajax/searchLive?keyword=' + encodeURIComponent(q);
    console.log('novelfire search url: ' + url);
    var res = await fetch(url, { headers: { Referer: REFERER, Accept: 'application/json' } });
    if (res.status !== 200) {
      console.log('novelfire search HTTP ' + res.status);
      return [];
    }
    var data;
    try { data = JSON.parse(res.body); } catch (e) { data = null; }
    var list = (data && data.data) || [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var s = list[i];
      if (!s || !s.slug) continue;
      out.push({
        id: s.slug,
        title: _clean(s.title),
        cover: s.image ? absUrl(s.image, SITE) : null,
        url: SITE + '/book/' + s.slug,
        type: 'novel'
      });
    }
    console.log('novelfire search count: ' + out.length);
    return out;
  }
  // No query: fall back to the popular grid so an empty search still shows rows.
  var bres = await fetch(
    SITE + '/genre-all/sort-popular/status-all/all-novel?page=' + page,
    { headers: { Referer: REFERER } }
  );
  return bres.status === 200 ? _parseBrowse(bres.body || '') : [];
}

// ── detail ──────────────────────────────────────────────────────────────────
async function _chaptersFor(bookUrl) {
  var base = bookUrl.replace(/\/+$/, '');
  var firstUrl = base + '/chapters';
  var out = [];
  var seen = {};
  var maxPage = 1;

  for (var page = 1; page <= maxPage && page <= MAX_CHAPTER_PAGES; page++) {
    var url = page === 1 ? firstUrl : firstUrl + '?page=' + page;
    var res;
    try { res = await fetch(url, { headers: { Referer: REFERER } }); }
    catch (e) { break; }
    if (res.status !== 200) break;
    var html = res.body || '';
    if (page === 1) {
      var pages = _all(html, /chapters\?page=([0-9]+)/g);
      for (var p = 0; p < pages.length; p++) {
        var n = parseInt(pages[p][1], 10);
        if (n > maxPage) maxPage = n;
      }
    }
    var links = _all(
      html,
      /<a[^>]+href="(\/book\/[^"]+\/chapter-[^"]+)"[^>]*(?:title="([^"]*)")?[^>]*>([\s\S]*?)<\/a>/gi
    );
    for (var i = 0; i < links.length; i++) {
      var link = absUrl(links[i][1], SITE);
      if (seen[link]) continue;
      seen[link] = true;
      var title = _clean(links[i][2] || '');
      if (!title) {
        var tm = links[i][3].match(/class="chapter-title"[^>]*>([\s\S]*?)</i);
        title = _clean(tm ? tm[1] : links[i][3]);
      }
      if (!title) title = 'Chapter ' + (out.length + 1);
      var num = _numFromUrl(link);
      out.push({
        id: _slugFromUrl(link) + '__' + (num != null ? num : out.length + 1),
        title: title,
        number: num,
        url: link,
        date: ''
      });
    }
  }
  out.sort(function (a, b) {
    if (a.number == null && b.number == null) return 0;
    if (a.number == null) return -1;
    if (b.number == null) return 1;
    return a.number - b.number;
  });
  return out;
}

async function getDetail(url) {
  console.log('novelfire detail url: ' + url);
  var res = await fetch(url, { headers: { Referer: REFERER } });
  if (res.status !== 200) throw new Error('detail HTTP ' + res.status);
  var html = res.body || '';

  var titleM = html.match(/<h1[^>]*class="novel-title[^"]*"[^>]*>([\s\S]*?)<\/h1>/i)
    || html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  var title = titleM ? _clean(titleM[1]) : '';

  var coverM = html.match(/property="og:image"[^>]+content="([^"]+)"/i)
    || html.match(/content="([^"]+)"[^>]+property="og:image"/i);
  var cover = coverM ? coverM[1] : null;

  var authorM = html.match(/<div class="author"[\s\S]*?<span itemprop="author"[^>]*>([\s\S]*?)<\/span>/i)
    || html.match(/<a[^>]+href="\/author\/[^"]*"[^>]*>([\s\S]*?)<\/a>/i);
  var author = authorM ? _clean(authorM[1]) : '';

  var summary = '';
  var sumM = html.match(/<div class="summary">[\s\S]*?<div class="content[^"]*">([\s\S]*?)<\/div>/i);
  if (sumM) {
    var paras = _all(sumM[1], /<p[^>]*>([\s\S]*?)<\/p>/gi);
    var chunks = [];
    for (var i = 0; i < paras.length; i++) {
      var t = _clean(paras[i][1]);
      if (t) chunks.push(t);
    }
    summary = chunks.length ? chunks.join('\n\n') : _clean(sumM[1]);
  }

  var statusM = html.match(/Status:\s*<strong[^>]*>([\s\S]*?)<\/strong>/i);
  if (!statusM) statusM = html.match(/<strong[^>]*class="[^"]*status[^"]*"[^>]*>([\s\S]*?)<\/strong>/i);
  var status = _normalizeStatus(statusM ? _clean(statusM[1]) : '');

  // Genres live in the "Genres" info block; the site also drops genre links in
  // nav/breadcrumb markup, so scope to that block and read the anchor titles.
  var genres = [];
  var catM = html.match(/<div class="categories">([\s\S]*?)<\/div>/i);
  var genreSrc = catM ? catM[1] : html;
  var genreM = _all(genreSrc, /<a[^>]+title="([^"]+)"[^>]*class="property-item"/gi);
  for (var g = 0; g < genreM.length && genres.length < 12; g++) {
    var gv = _clean(genreM[g][1]);
    if (gv && genres.indexOf(gv) === -1) genres.push(gv);
  }

  var chapters = await _chaptersFor(url);
  console.log('novelfire detail: title=' + title + ' chapters=' + chapters.length);

  return {
    id: _slugFromUrl(url),
    sourceId: SOURCE_ID,
    title: title,
    cover: cover,
    url: url,
    author: author,
    status: status,
    description: summary,
    genres: genres,
    chapters: chapters,
    type: 'novel'
  };
}

async function getChapters(url) {
  return _chaptersFor(url);
}

// ── chapter content ─────────────────────────────────────────────────────────
function getPages(chapterUrl) {
  return [];
}

// The site rate-limits bursts (429) and, under load, sometimes serves a short
// interstitial instead of the chapter body. Both clear on a retry after a
// pause. A single user-initiated read never triggers this; the test suite
// walking search → detail → chapter back-to-back does.
var _CHAPTER_TRIES = 3;
var _CHAPTER_BACKOFF_MS = 5000;

function _sleep(ms) {
  return new Promise(function (resolve) { setTimeout(resolve, ms); });
}

async function getChapterContent(chapterUrl) {
  console.log('novelfire chapter url: ' + chapterUrl);
  for (var attempt = 1; attempt <= _CHAPTER_TRIES; attempt++) {
    var res = await fetch(chapterUrl, { headers: { Referer: REFERER } });
    if (res.status === 200) {
      var parsed = _parseChapter(res.body || '', chapterUrl);
      if (parsed.text) return parsed;
    }
    if (attempt < _CHAPTER_TRIES) await _sleep(_CHAPTER_BACKOFF_MS);
    else if (res.status !== 200) throw new Error('chapter HTTP ' + res.status);
  }
  throw new Error('chapter empty after ' + _CHAPTER_TRIES + ' tries');
}

function _parseChapter(html, chapterUrl) {
  var bodyM = html.match(/<div id="content"[^>]*>([\s\S]*?)<\/div>\s*<\/div>/i)
    || html.match(/<div id="content"[^>]*>([\s\S]*?)(?:<div class="nf-ads|<footer|<\/article>)/i);
  var content = bodyM ? bodyM[1] : '';

  content = content.replace(/<script[\s\S]*?<\/script>/gi, '');
  content = content.replace(/<div[^>]*class="[^"]*ad[^"]*"[\s\S]*?<\/div>/gi, '');
  content = content.replace(/<iframe[\s\S]*?<\/iframe>/gi, '');

  var paragraphs = [];
  var pm = /<p[^>]*>([\s\S]*?)<\/p>/gi;
  var p;
  while ((p = pm.exec(content)) !== null) {
    var t = _clean(p[1]);
    if (t) paragraphs.push(t);
  }
  var text = paragraphs.length
    ? paragraphs.join('\n\n')
    : _clean(content.replace(/<br\s*\/?>/gi, '\n'));

  var titleM = html.match(/<span class="chapter-title"[^>]*>([\s\S]*?)<\/span>/i)
    || html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  var title = _clean(titleM ? titleM[1] : '');

  var nextUrl = null;
  var nextM = _all(html, /<a[^>]+href="([^"]*\/chapter-[^"]+)"[^>]*>\s*(?:Next|Next Chapter)/gi);
  if (nextM.length) nextUrl = absUrl(nextM[0][1], SITE);
  if (!nextUrl) {
    var bump = chapterUrl.match(/(.+\/chapter-)([0-9]+)([^\/?#]*)$/i);
    if (bump) nextUrl = bump[1] + (parseInt(bump[2], 10) + 1);
  }

  return { title: title, text: text, nextUrl: nextUrl || '' };
}
