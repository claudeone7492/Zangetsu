// NovelCool provider — https://www.novelcool.com
// Server-rendered catalogue with the full chapter archive inline on each novel
// page. Search uses `?wd=` (the `name` field on the desktop form is ignored).
// Chapter bodies live in `.chapter-reading-section`.

var SOURCE_ID = 'novelcool';
var SITE = 'https://www.novelcool.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelCool', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'novel', version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }

function _blockText(html) {
  var s = String(html || '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|tr|blockquote)>/gi, '\n\n')
    .replace(/<[^>]+>/g, '');
  s = s.replace(/&#x([0-9a-fA-F]+);/g, function(_, h) { return String.fromCodePoint(parseInt(h, 16)); })
    .replace(/&#(\d+);/g, function(_, d) { return String.fromCodePoint(parseInt(d, 10)); })
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'").replace(/&hellip;/g, '…').replace(/&mdash;/g, '—');
  return s.replace(/\r/g, '').replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n').trim();
}

function _abs(href) { return absUrl(href || '', SITE); }
function _slug(url) {
  var m = String(url).match(/\/novel\/([^\/?#]+)\.html/i);
  return m ? m[1] : String(url);
}

function _cards(html) {
  var out = [], seen = {};
  var re = /<div class="book-pic" title="([^"]*)">\s*<a href="([^"]+)"[^>]*>[\s\S]*?<img[^>]+src="([^"]+)"/g;
  var m;
  while ((m = re.exec(html)) !== null) {
    var url = _abs(m[2]);
    if (seen[url]) continue;
    seen[url] = true;
    out.push({
      id: _slug(url), title: _clean(m[1]) || _slug(url),
      cover: _abs(m[3]), url: url, author: '', description: '', type: 'novel'
    });
  }
  return out;
}

function _meta(html, prop) {
  var re = new RegExp('<meta[^>]+(?:property|name)="' + prop + '"[^>]+content="([^"]*)"', 'i');
  var m = String(html || '').match(re);
  return m ? m[1] : '';
}

function getHome() {
  return fetch(SITE + '/', { headers: { 'Referer': REFERER } }).then(function(r) {
    var items = _cards(r.body || '');
    return items.length ? [{ title: 'Popular', items: items.slice(0, 30) }] : [];
  });
}

function search(query, page) {
  var q = String(query || '').trim();
  var u = SITE + '/search/?wd=' + encodeURIComponent(q);
  return fetch(u, { headers: { 'Referer': REFERER } }).then(function(r) {
    return _cards(r.body || '');
  });
}

function _chapter(url, title, date) {
  var n = String(title || '').match(/Chapter\s+([0-9]+(?:\.[0-9]+)?)/i);
  return {
    id: String(url).replace(/[^0-9a-zA-Z]+/g, '-'),
    title: _clean(title), number: n ? parseFloat(n[1]) : null,
    url: _abs(url), date: date || ''
  };
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h1[^>]*class="bookinfo-title"[^>]*>([\s\S]*?)<\/h1>/i);
    var authorM = html.match(/<span[^>]+itemprop="creator"[^>]*>([\s\S]*?)<\/span>/i);
    var coverM = html.match(/<img[^>]+class="bookinfo-pic-img"[^>]+src="([^"]+)"/i);
    var descM = html.match(/<div[^>]+class="bk-summary-txt"[^>]*>([\s\S]*?)<\/div>/i) ||
      html.match(/<span[^>]+itemprop="description"[^>]*>([\s\S]*?)<\/span>/i);
    var genres = [], gm, gre = /<div class="book-tag">([\s\S]*?)<\/div>/g;
    while ((gm = gre.exec(html)) !== null) genres.push(_clean(gm[1]));
    var chapters = [], seen = {}, cm;
    var cre = /<a href="(https:\/\/www\.novelcool\.com\/chapter\/[^"]+)"[^>]*title="([^"]*)"[\s\S]*?<span class="chapter-item-headtitle">([\s\S]*?)<\/span>/g;
    while ((cm = cre.exec(html)) !== null) {
      var cu = _abs(cm[1]);
      if (seen[cu]) continue;
      seen[cu] = true;
      chapters.push(_chapter(cu, _clean(cm[3] || cm[2])));
    }
    chapters.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
    return {
      id: _slug(url), sourceId: SOURCE_ID,
      title: _clean(titleM ? titleM[1] : _meta(html, 'og:title')),
      cover: coverM ? _abs(coverM[1]) : null, url: _abs(url),
      author: _clean(authorM ? authorM[1] : ''),
      authors: authorM ? [_clean(authorM[1])] : [],
      status: _meta(html, 'og:novel:status'),
      description: _blockText(descM ? descM[1] : _meta(html, 'og:description')),
      genres: genres, chapters: chapters, type: 'novel'
    };
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var marker = html.indexOf('chapter-start-mark');
    var start = marker >= 0 ? html.lastIndexOf('<p', marker) : -1;
    var endMarker = html.indexOf('chapter-end-mark');
    var end = endMarker >= 0 ? html.lastIndexOf('<p', endMarker) : -1;
    var block = start >= 0 && end > start ? html.slice(start, end) : html;
    block = block.replace(/<h[12][^>]*>[\s\S]*?<\/h[12]>/gi, '');
    var text = _blockText(block)
      .replace(/^Chapter start\s*/i, '')
      .replace(/\s*Support Creator\s*$/i, '')
      .trim();
    var nextM = html.match(/<a href="([^"]+)"[^>]*>\s*<div>\s*Next/i);
    return { text: text, nextUrl: nextM ? _abs(nextM[1]) : null };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
