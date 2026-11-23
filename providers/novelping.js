// NovelPing provider — https://novelping.com
// Server-rendered site with a search API-compatible HTML page and a separate
// full chapter archive endpoint: /ajax/chapter-archive?novelId=<slug>.
// Chapter bodies live in #chr-content.

var SOURCE_ID = 'novelping';
var SITE = 'https://novelping.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelPing', lang: 'en', baseUrl: SITE,
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
  var m = String(url).match(/\/book\/([^\/?#]+)/i);
  return m ? m[1] : String(url);
}
function _meta(html, prop) {
  var re = new RegExp('<meta[^>]+(?:property|name)="' + prop + '"[^>]+content="([^"]*)"', 'i');
  var m = String(html || '').match(re);
  return m ? m[1] : '';
}

function _homeCards(html) {
  var out = [], seen = {}, m;
  var re = /<div class="item[^"]*"><a href="([^"]+)"\s+title="([^"]*)"[\s\S]*?<img[^>]+src="([^"]+)"/g;
  while ((m = re.exec(html)) !== null) {
    var url = _abs(m[1]);
    if (seen[url]) continue;
    seen[url] = true;
    out.push({
      id: _slug(url), title: _clean(m[2]), cover: _abs(m[3]),
      url: url, author: '', description: '', type: 'novel'
    });
  }
  return out;
}

function _searchCards(html) {
  var out = [], seen = {}, m;
  var re = /<h3 class="novel-title"><a href="([^"]+)"\s+title="([^"]*)">/g;
  while ((m = re.exec(html)) !== null) {
    var url = _abs(m[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var from = Math.max(0, m.index - 2500);
    var before = html.slice(from, m.index);
    var rowAt = before.lastIndexOf('<div class="row">');
    var row = rowAt >= 0 ? before.slice(rowAt) : before;
    var imgM = row.match(/<img[^>]+src="([^"]+)"/i);
    var authorM = row.match(/<span class="author">([\s\S]*?)<\/span>/i);
    out.push({
      id: _slug(url), title: _clean(m[2]),
      cover: imgM ? _abs(imgM[1]) : null, url: url,
      author: authorM ? _clean(authorM[1]) : '', description: '', type: 'novel'
    });
  }
  return out;
}

function getHome() {
  return fetch(SITE + '/', { headers: { 'Referer': REFERER } }).then(function(r) {
    var items = _homeCards(r.body || '');
    return items.length ? [{ title: 'Popular', items: items.slice(0, 30) }] : [];
  });
}

function search(query, page) {
  var q = String(query || '').trim();
  var u = SITE + '/search?keyword=' + encodeURIComponent(q) + (page > 1 ? '&page=' + page : '');
  return fetch(u, { headers: { 'Referer': REFERER } }).then(function(r) {
    return _searchCards(r.body || '');
  });
}

function _chapter(url, title, number) {
  return {
    id: String(url).replace(/[^0-9a-zA-Z]+/g, '-'),
    title: _clean(title), number: number != null ? number : null,
    url: _abs(url), date: ''
  };
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var slug = _slug(url);
    var titleM = html.match(/<meta[^>]+property="og:novel:novel_name"[^>]+content="([^"]*)"/i);
    var authorM = html.match(/<meta[^>]+property="og:novel:author"[^>]+content="([^"]*)"/i);
    var statusM = html.match(/<meta[^>]+property="og:novel:status"[^>]+content="([^"]*)"/i);
    var genreM = html.match(/<meta[^>]+property="og:novel:genre"[^>]+content="([^"]*)"/i);
    var imageM = html.match(/<meta[^>]+property="og:image"[^>]+content="([^"]*)"/i);
    var descM = html.match(/<div[^>]+id="novel-description-content"[^>]*>([\s\S]*?)<\/div>/i);
    var genres = genreM ? genreM[1].split(',').map(function(x) { return _clean(x); }).filter(Boolean) : [];
    return fetch(SITE + '/ajax/chapter-archive?novelId=' + encodeURIComponent(slug), {
      headers: { 'Referer': url, 'Accept': 'text/html,application/xhtml+xml' }
    }).then(function(cr) {
      var chapters = [], seen = {}, cm;
      var cre = /<li[^>]+data-chapter-item[^>]*>[\s\S]*?<a href="([^"]+)"[^>]*title="([^"]*)"/g;
      while ((cm = cre.exec(cr.body || '')) !== null) {
        var cu = _abs(cm[1]);
        if (seen[cu]) continue;
        seen[cu] = true;
        var n = String(cm[2]).match(/Chapter\s+([0-9]+(?:\.[0-9]+)?)/i);
        chapters.push(_chapter(cu, cm[2], n ? parseFloat(n[1]) : null));
      }
      chapters.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
      return {
        id: slug, sourceId: SOURCE_ID,
        title: _clean(titleM ? titleM[1] : _meta(html, 'og:title')),
        cover: imageM ? _abs(imageM[1]) : null, url: _abs(url),
        author: _clean(authorM ? authorM[1] : ''),
        authors: authorM ? [_clean(authorM[1])] : [],
        status: _clean(statusM ? statusM[1] : ''),
        description: _blockText(descM ? descM[1] : _meta(html, 'og:description')),
        genres: genres, chapters: chapters, type: 'novel'
      };
    });
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var blockM = html.match(/<div id="chr-content"[^>]*>([\s\S]*?)<\/div>/i);
    var nextM = html.match(/<a[^>]+aria-label="Next chapter"[^>]+href="([^"]+)"/i) ||
      html.match(/<a[^>]+href="([^"]+)"[^>]+aria-label="Next chapter"/i);
    return { text: _blockText(blockM ? blockM[1] : ''), nextUrl: nextM ? _abs(nextM[1]) : null };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
