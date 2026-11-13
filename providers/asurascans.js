// AsuraScans provider — https://asurascans.com (Aatricks/Emaki source port).
//
// Manga-type source. Astro-rendered HTML with a hydration island holding the
// chapter image URLs; the reader's own <img> tags are lazy, so getPages reads
// the escaped island payload. Verified live:
//   * browse  → /browse?order={popular,update,latest}
//   * search  → /browse?q=<q> (series-card grid)
//   * detail  → <h1> + og:description + /comics/<slug>/chapter/<n> links
//   * reader  → cdn.asurascans.com/asura-images/chapters/<slug>/<n>/*.webp

var SOURCE_ID = 'asurascans';
var SITE = 'https://asurascans.com';
var REFERER = SITE + '/';
var LOGO = SITE + '/favicon.ico';
// AsuraScans' edge rejects the default `Accept: */*` with 403; it wants an
// HTML accept on every document request.
var HTML_ACCEPT = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

function getInfo() {
  return {
    name: 'Asura Scans',
    lang: 'en',
    baseUrl: SITE,
    logo: LOGO,
    type: 'manga',
    version: '1.0.0'
  };
}

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _unescape(s) {
  return String(s || '')
    .replace(/&quot;/g, '"')
    .replace(/&#34;/g, '"')
    .replace(/&amp;/g, '&');
}

function _slugFromUrl(url) {
  var m = String(url).match(/\/comics\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

function _parseGrid(html) {
  var out = [];
  var seen = {};
  var re = /<div class="series-card[^"]*"[^>]*data-series-id="[^"]*"[^>]*>([\s\S]*?)(?=<div class="series-card|<\/div><\/div><\/div>|$)/g;
  var m;
  while ((m = re.exec(html)) !== null) {
    var blk = m[1];
    var hrefM = blk.match(/href="(\/comics\/[^"]+)"/);
    if (!hrefM) continue;
    var link = absUrl(hrefM[1], SITE);
    if (seen[link]) continue;
    seen[link] = true;
    var titleM = blk.match(/<h3[^>]*>([\s\S]*?)<\/h3>/i)
      || blk.match(/<img[^>]+alt="([^"]+)"/i);
    var coverM = blk.match(/<img[^>]+src="([^"]+)"/i);
    out.push({
      id: _slugFromUrl(link),
      title: _clean(titleM ? titleM[1] : ''),
      cover: coverM ? absUrl(coverM[1], SITE) : null,
      url: link,
      type: 'manga'
    });
  }
  return out;
}

async function _browseRow(title, order) {
  var res = await fetch(SITE + '/browse?order=' + order, { headers: { Referer: REFERER, Accept: HTML_ACCEPT } });
  if (res.status !== 200) {
    console.log('asurascans home row HTTP ' + res.status + ' ' + title);
    return null;
  }
  var items = _parseGrid(res.body || '');
  return items.length ? { title: title, items: items } : null;
}

async function getHome(opts) {
  opts = opts || {};
  var rows = [
    { title: 'Popular', order: 'popular' },
    { title: 'Latest Updates', order: 'update' },
    { title: 'New Series', order: 'latest' }
  ];
  var sections = [];
  for (var i = 0; i < rows.length; i++) {
    try {
      var sec = await _browseRow(rows[i].title, rows[i].order);
      if (sec) sections.push(sec);
    } catch (e) {
      console.log('asurascans home row failed: ' + rows[i].title + ' (' + e + ')');
    }
  }
  return sections;
}

async function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  var url = q
    ? SITE + '/browse?q=' + encodeURIComponent(q) + (page > 1 ? '&page=' + page : '')
    : SITE + '/browse?order=popular' + (page > 1 ? '&page=' + page : '');
  console.log('asurascans search url: ' + url);
  var res = await fetch(url, { headers: { Referer: REFERER, Accept: HTML_ACCEPT } });
  if (res.status !== 200) {
    console.log('asurascans search HTTP ' + res.status);
    return [];
  }
  var out = _parseGrid(res.body || '');
  console.log('asurascans search count: ' + out.length);
  return out;
}

function _chapters(html, slug) {
  var un = _unescape(html);
  var out = [];
  var seen = {};
  var re = new RegExp('/comics/' + slug.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '/chapter/([0-9]+(?:\\.[0-9]+)?)', 'g');
  var m;
  while ((m = re.exec(un)) !== null) {
    var num = parseFloat(m[1]);
    if (seen[m[1]]) continue;
    seen[m[1]] = true;
    out.push({
      id: slug + '__' + m[1],
      title: 'Chapter ' + m[1],
      number: isNaN(num) ? null : num,
      url: SITE + '/comics/' + slug + '/chapter/' + m[1],
      date: ''
    });
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
  console.log('asurascans detail url: ' + url);
  var slug = _slugFromUrl(url);
  var res = await fetch(url, { headers: { Referer: REFERER, Accept: HTML_ACCEPT } });
  if (res.status !== 200) throw new Error('detail HTTP ' + res.status);
  var html = res.body || '';

  var titleM = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  var title = titleM ? _clean(titleM[1]) : '';

  var coverM = html.match(/property="og:image"[^>]+content="([^"]+)"/i);
  var cover = coverM ? coverM[1] : null;

  var descM = html.match(/property="og:description"[^>]+content="([^"]*)"/i);
  var description = descM ? _clean(descM[1]) : '';

  var authorM = html.match(/href="\/browse\?author=[^"]*"[^>]*>([^<]+)</i)
    || html.match(/href="\/browse\?artist=[^"]*"[^>]*>([^<]+)</i);
  var author = authorM ? _clean(authorM[1]) : '';

  var genres = [];
  var gm = html.match(/href="\/browse\?genres?=[^"]*"[^>]*>([^<]+)</gi) || [];
  for (var g = 0; g < gm.length && genres.length < 10; g++) {
    var gv = _clean((gm[g].match(/>([^<]+)</) || [null, ''])[1]);
    if (gv && genres.indexOf(gv) === -1) genres.push(gv);
  }

  var chapters = _chapters(html, slug);
  console.log('asurascans detail: title=' + title + ' chapters=' + chapters.length);

  return {
    id: slug,
    sourceId: SOURCE_ID,
    title: title,
    cover: cover,
    url: url,
    author: author,
    status: 'ongoing',
    description: description,
    genres: genres,
    chapters: chapters,
    type: 'manga'
  };
}

async function getChapters(url) {
  var slug = _slugFromUrl(url);
  var res = await fetch(SITE + '/comics/' + slug, { headers: { Referer: REFERER, Accept: HTML_ACCEPT } });
  if (res.status !== 200) return [];
  return _chapters(res.body || '', slug);
}

async function getPages(chapterUrl) {
  console.log('asurascans pages url: ' + chapterUrl);
  var res = await fetch(chapterUrl, { headers: { Referer: REFERER, Accept: HTML_ACCEPT } });
  if (res.status !== 200) throw new Error('chapter HTTP ' + res.status);
  var un = _unescape(res.body || '');
  var out = [];
  var seen = {};
  // Two CDN layouts: /asura-images/chapters/<slug>/<n>/NNN.webp and
  // /asura-images/chapters-stitched/<slug>/<n>/NNN-hash.webp. Exclude the
  // /covers/ images (the series thumbnail) which appear earlier in the page.
  var re = /(https:\/\/cdn\.asurascans\.com\/asura-images\/(?!covers\/)[^"'\\ ]+\.(?:webp|jpg|jpeg|png)(?:\?[^"'\\ ]*)?)/g;
  var m;
  while ((m = re.exec(un)) !== null) {
    var src = m[1];
    if (seen[src]) continue;
    seen[src] = true;
    out.push({ url: src, index: out.length, headers: { Referer: chapterUrl } });
  }
  console.log('asurascans pages count: ' + out.length);
  if (out.length === 0) throw new Error('Chapter has no images');
  return out;
}

function getChapterContent(chapterUrl) {
  return { text: 'Asura Scans is a manga-only source.', nextUrl: null };
}
