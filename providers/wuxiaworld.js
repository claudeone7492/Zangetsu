// WuxiaWorld provider — https://wuxiaworld.site
// Madara/WordPress novel site. The chapter archive is served by a POST to
// <novel-url>/ajax/chapters/ (the GET form returns the whole novel page).
// Chapter bodies live in .text-left.

var SOURCE_ID = 'wuxiaworld';
var SITE = 'https://wuxiaworld.site';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'WuxiaWorld', lang: 'en', baseUrl: SITE,
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
  var m = String(url).match(/\/novel\/([^\/?#]+)/i);
  return m ? m[1] : String(url);
}
function _meta(html, prop) {
  var re = new RegExp('<meta[^>]+(?:property|name)="' + prop + '"[^>]+content="([^"]*)"', 'i');
  var m = String(html || '').match(re);
  return m ? m[1] : '';
}

function _cards(html) {
  var out = [], seen = {}, m;
  var re = /<div[^>]+class="item-thumb[^"]*"[^>]*>\s*<a href="([^"]+)" title="([^"]*)"[\s\S]*?<img[^>]+(?:data-src|src)="([^"]+)"/g;
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
  var parts = String(html || '').split('<div class="row c-tabs-item__content">');
  var out = [], seen = {};
  for (var i = 1; i < parts.length; i++) {
    var block = parts[i];
    var linkM = block.match(/<h3 class="h4"><a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!linkM) continue;
    var url = _abs(linkM[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var imgM = block.match(/<img[^>]+(?:data-src|src)="([^"]+)"/i);
    var authorM = block.match(/<div class="author-content">([\s\S]*?)<\/div>/i);
    out.push({
      id: _slug(url), title: _clean(linkM[2]),
      cover: imgM ? _abs(imgM[1]) : null, url: url,
      author: authorM ? _clean(authorM[1]) : '', description: '', type: 'novel'
    });
  }
  return out;
}

function getHome() {
  return fetch(SITE + '/', { headers: { 'Referer': REFERER } }).then(function(r) {
    var items = _cards(r.body || '');
    return items.length ? [{ title: 'Latest Updates', items: items.slice(0, 30) }] : [];
  });
}

function search(query, page) {
  var q = String(query || '').trim();
  function run(term) {
    var u = SITE + '/?s=' + encodeURIComponent(term) + '&post_type=wp-manga' +
      (page > 1 ? '&paged=' + page : '');
    return fetch(u, { headers: { 'Referer': REFERER } }).then(function(r) {
      return _searchCards(r.body || '');
    });
  }
  return run(q).then(function(rows) {
    if (rows.length || q.indexOf(' ') === -1) return rows;
    return run(q.split(/\s+/)[0]);
  });
}

function _chapter(url, title) {
  var n = String(title || url).match(/chapter\s*[- ]?([0-9]+(?:\.[0-9]+)?)/i);
  return {
    id: String(url).replace(/[^0-9a-zA-Z]+/g, '-'),
    title: _clean(title), number: n ? parseFloat(n[1]) : null,
    url: _abs(url), date: ''
  };
}

function _parseChapters(html) {
  var out = [], seen = {}, m;
  var re = /<li class="wp-manga-chapter[^>]*>\s*<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  while ((m = re.exec(html)) !== null) {
    var url = _abs(m[1]);
    if (seen[url]) continue;
    seen[url] = true;
    out.push(_chapter(url, m[2]));
  }
  return out.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
}

function _generatedChapters(html, url) {
  var max = 0, m, re = /href="([^"]*\/chapter-([0-9]+)(?:-[^"]*)?\/)"/g;
  while ((m = re.exec(html)) !== null) max = Math.max(max, parseInt(m[2], 10));
  if (!max) return [];
  var base = String(url).replace(/\/$/, '') + '/chapter-';
  var out = [];
  for (var i = 1; i <= max; i++) {
    out.push({ id: 'chapter-' + i, title: 'Chapter ' + i, number: i, url: base + i + '/', date: '' });
  }
  return out;
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<div class="post-title">[\s\S]*?<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var coverM = html.match(/<div class="summary_image">[\s\S]*?<img[^>]+(?:data-src|src)="([^"]+)"/i);
    var authorM = html.match(/<div class="author-content">([\s\S]*?)<\/div>/i);
    var statusM = html.match(/<h5>\s*Status\s*<\/h5>[\s\S]*?<div class="summary-content">([\s\S]*?)<\/div>/i);
    var descM = html.match(/<div class="summary__content[^"]*">([\s\S]*?)<\/div>/i);
    var genres = [], gm, gblock = html.match(/<div class="genres-content">([\s\S]*?)<\/div>/i);
    if (gblock) {
      var ga = /<a[^>]*>([\s\S]*?)<\/a>/g;
      while ((gm = ga.exec(gblock[1])) !== null) genres.push(_clean(gm[1]));
    }
    var archiveUrl = String(url).replace(/\/$/, '') + '/ajax/chapters/';
    return fetch(archiveUrl, {
      method: 'POST',
      headers: {
        'Referer': url, 'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'text/html, */*; q=0.01'
      }
    }).then(function(cr) {
      var chapters = _parseChapters(cr.body || '');
      if (!chapters.length) chapters = _generatedChapters(html, url);
      return {
        id: _slug(url), sourceId: SOURCE_ID,
        title: _clean(titleM ? titleM[1] : _meta(html, 'og:title')),
        cover: coverM ? _abs(coverM[1]) : null, url: _abs(url),
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
    var blockM = html.match(/<div class="text-left">([\s\S]*?)<\/div>/i);
    var nextM = html.match(/<div class="nav-next[^"]*">\s*<a href="([^"]+)"/i) ||
      html.match(/<a href="([^"]+)"[^>]+class="[^"]*next_page[^"]*"/i);
    return { text: _blockText(blockM ? blockM[1] : ''), nextUrl: nextM ? _abs(nextM[1]) : null };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
