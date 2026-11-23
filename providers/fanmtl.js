// FanMTL provider — https://www.fanmtl.com
// Search is a POST to the site's search module; the archive is paginated via
// /e/extend/fy.php (100 chapters per page) and chapter pages carry the body in
// div.chapter-content.

var SOURCE_ID = 'fanmtl';
var SITE = 'https://www.fanmtl.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'FanMTL', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'novel', version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }
function _abs(href) { return absUrl(href || '', SITE); }
function _slug(url) { return String(url || '').replace(/[?#].*$/, '').replace(/\/+$/, '').split('/').pop(); }
function _all(s, re) {
  var out = [], m;
  while ((m = re.exec(s)) !== null) out.push(m);
  return out;
}

function _blockText(html) {
  var s = String(html || '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<div[^>]+align="center"[^>]*>[\s\S]*?<\/div>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|tr|blockquote)>/gi, '\n\n')
    .replace(/<[^>]+>/g, '');
  s = s.replace(/&#x([0-9a-fA-F]+);/g, function(_, h) { return String.fromCodePoint(parseInt(h, 16)); })
    .replace(/&#(\d+);/g, function(_, d) { return String.fromCodePoint(parseInt(d, 10)); })
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'").replace(/&hellip;/g, '…').replace(/&mdash;/g, '—');
  return s.replace(/\r/g, '').replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n').replace(/^Panda Novel\s*/i, '').trim();
}

function _cards(html) {
  var out = [], seen = {};
  var re = /<li class="novel-item">([\s\S]*?)<\/li>/gi, m;
  while ((m = re.exec(html)) !== null) {
    var b = m[1];
    var aM = b.match(/<a[^>]+href="([^"]+)"[^>]*title="([^"]*)"/i);
    if (!aM) continue;
    var url = _abs(aM[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var imgM = b.match(/data-src="([^"]+)"/i) || b.match(/<img[^>]+src="([^"]+)"/i);
    var statusM = b.match(/Status:\s*<span[^>]*>([\s\S]*?)<\/span>/i);
    out.push({
      id: _slug(url), title: _clean(aM[2]), cover: imgM ? _abs(imgM[1]) : null,
      url: url, author: '', description: '', status: statusM ? _clean(statusM[1]) : '',
      type: 'novel'
    });
  }
  return out;
}

function getHome() {
  return fetch(SITE + '/', { headers: { 'Referer': REFERER } }).then(function(r) {
    var items = _cards(r.body || '').slice(0, 30);
    return items.length ? [{ title: 'Latest', items: items }] : [];
  });
}

function search(query, page) {
  var body = 'show=title&tempid=1&tbname=news&keyboard=' + encodeURIComponent(String(query || ''));
  var u = SITE + '/e/search/index.php' + (page > 1 ? '?page=' + page : '');
  return fetch(u, {
    method: 'POST', body: body,
    headers: { 'Referer': SITE + '/search.html', 'Content-Type': 'application/x-www-form-urlencoded' }
  }).then(function(r) { return _cards(r.body || ''); });
}

function _chapters(html, base) {
  var out = [], seen = {};
  var re = /<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/gi, m;
  while ((m = re.exec(html)) !== null) {
    var url = _abs(m[1]);
    if (seen[url] || !/\/novel\/[^/]+_\d+\.html/i.test(url)) continue;
    var titleM = m[2].match(/<strong[^>]*>([\s\S]*?)<\/strong>/i);
    if (!titleM) continue;
    seen[url] = true;
    var numM = url.match(/_(\d+)\.html/i);
    out.push({
      id: numM ? numM[1] : _slug(url), title: _clean(titleM[1]),
      number: numM ? parseInt(numM[1], 10) : null, url: url, date: ''
    });
  }
  return out;
}

function _allChapters(base) {
  var slugM = base.match(/\/novel\/([^/]+)\.html/i);
  if (!slugM) return Promise.resolve([]);
  var slug = slugM[1];
  var firstUrl = SITE + '/e/extend/fy.php?page=0&wjm=' + encodeURIComponent(slug);
  return fetch(firstUrl, { headers: { 'Referer': base } }).then(function(r) {
    var html = r.body || '';
    var all = _chapters(html, base);
    var max = 0, pm;
    var pRe = /fy\.php\?page=(\d+)/gi;
    while ((pm = pRe.exec(html)) !== null) max = Math.max(max, parseInt(pm[1], 10));
    var jobs = [];
    for (var p = 1; p <= max; p++) {
      jobs.push(fetch(SITE + '/e/extend/fy.php?page=' + p + '&wjm=' + encodeURIComponent(slug), {
        headers: { 'Referer': base }
      }).then(function(pr) { return _chapters(pr.body || '', base); }));
    }
    return Promise.all(jobs).then(function(groups) {
      var seen = {};
      all.forEach(function(c) { seen[c.url] = true; });
      groups.forEach(function(g) {
        g.forEach(function(c) { if (!seen[c.url]) { seen[c.url] = true; all.push(c); } });
      });
      all.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
      return all;
    });
  });
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h1[^>]*itemprop="name"[^>]*>([\s\S]*?)<\/h1>/i) ||
      html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var coverM = html.match(/<figure class="cover">[\s\S]*?<img[^>]+(?:data-src|src)="([^"]+)"/i);
    var authorM = html.match(/itemprop="author"[^>]*>([\s\S]*?)<\/span>/i);
    var descM = html.match(/<div class="summary">[\s\S]*?<div class="content">([\s\S]*?)<\/div>/i);
    var statusM = html.match(/<strong class="">([\s\S]*?)<\/strong>\s*<small>Status<\/small>/i);
    var genres = [];
    var gm = html.match(/<div class="categories">([\s\S]*?)<\/div>/i);
    if (gm) genres = _all(gm[1], /<a[^>]*>([\s\S]*?)<\/a>/gi).map(function(x) { return _clean(x[1]); }).filter(Boolean);
    var inline = _chapters(html, url);
    return _allChapters(url).then(function(list) {
      if (!list.length) list = inline;
      return {
        id: _slug(url), sourceId: SOURCE_ID, title: _clean(titleM ? titleM[1] : ''),
        cover: coverM ? _abs(coverM[1]) : null, url: url,
        author: _clean(authorM ? authorM[1] : ''), authors: [],
        status: statusM ? _clean(statusM[1]) : '',
        description: descM ? _blockText(descM[1]) : '', genres: genres,
        chapters: list, type: 'novel'
      };
    });
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl).then(function(r) {
    var html = r.body || '';
    var bodyM = html.match(/<div class="chapter-content">([\s\S]*?)<div class="chapternav/i);
    var nM = html.match(/<a[^>]+class="[^"]*nextchap[^"]*"[^>]+href="([^"]+)"/i);
    return { text: _blockText(bodyM ? bodyM[1] : ''), nextUrl: nM ? _abs(nM[1]) : null };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
