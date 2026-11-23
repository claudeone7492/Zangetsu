// NovelFull provider — https://novelfull.com
// NovelFull-family site. Search/home use `div.li-row` cards. A novel detail
// page paginates its chapter list with ?page=N, so the full list is assembled
// from every page linked in the archive pagination.

var SOURCE_ID = 'novelfull';
var SITE = 'https://novelfull.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelFull', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'novel', version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }
function _abs(href) { return absUrl(href || '', SITE); }

function _all(html, re) {
  var out = [], m;
  re.lastIndex = 0;
  while ((m = re.exec(html)) !== null) {
    out.push(m);
    if (m.index === re.lastIndex) re.lastIndex++;
  }
  return out;
}

function _slug(url) {
  var m = String(url).match(/\/([^\/?#]+)\.html/);
  return m ? m[1] : String(url);
}

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

function _chapter(href, title, num) {
  var url = _abs(href);
  var t = _clean(title || '');
  if (!t) {
    var m = url.match(/chapter-([0-9]+)/i);
    t = m ? 'Chapter ' + m[1] : 'Chapter';
  }
  return {
    id: _slug(url) + '#' + (url.match(/chapter-([^\/?#]+?)(?:\.html)?$/i) || [, ''])[1],
    title: t, number: num != null ? num : null, url: url, date: ''
  };
}

function _cards(html) {
  var out = [], seen = {};
  function push(href, title, block) {
    var url = _abs(href);
    if (!url || seen[url]) return;
    seen[url] = true;
    var imgM = block.match(/<img[^>]+src="([^"]+)"/i);
    var authorM = block.match(/class="author"[^>]*>([\s\S]*?)<\/span>\s*<\/div>/i) ||
      block.match(/glyphicon-user[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
    out.push({
      id: _slug(url), title: _clean(title),
      cover: imgM ? _abs(imgM[1]) : null, url: url,
      author: authorM ? _clean(authorM[1].replace(/<[^>]+>/g, '')) : '',
      description: '', type: 'novel'
    });
  }
  var re = /<h3[^>]*class="truyen-title"[^>]*>([\s\S]*?)<\/h3>/gi, m;
  while ((m = re.exec(html)) !== null) {
    var aM = m[1].match(/<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (aM) push(aM[1], aM[2], html.slice(Math.max(0, m.index - 1600), m.index + 1600));
  }
  re = /<div class="li-row">([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>/gi;
  while ((m = re.exec(html)) !== null) {
    var aM2 = m[1].match(/<h3[^>]*class="tit"[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (aM2) push(aM2[1], aM2[2], m[1]);
  }
  re = /<div class="item[^"]*">\s*<a href="([^"]+)" title="([^"]*)"[\s\S]*?<img[^>]+src="([^"]+)"/gi;
  while ((m = re.exec(html)) !== null) {
    push(m[1], m[2], m[0]);
  }
  return out;
}

function getHome() {
  return fetch(SITE + '/', { headers: { 'Referer': REFERER } }).then(function(r) {
    var items = _cards(r.body || '');
    return items.length ? [{ title: 'Latest Novels', items: items.slice(0, 30) }] : [];
  });
}

function search(query, page) {
  page = page || 1;
  var u = SITE + '/search?keyword=' + encodeURIComponent(String(query || '')) +
    (page > 1 ? '&page=' + page : '');
  return fetch(u, { headers: { 'Referer': REFERER } }).then(function(r) { return _cards(r.body || ''); });
}

function _chapters(html) {
  var out = [], seen = {};
  var rows = _all(html, /<a[^>]+href="([^"]*\/chapter-[^"]+\.html)"[^>]*>([\s\S]*?)<\/a>/gi);
  for (var i = 0; i < rows.length; i++) {
    var url = _abs(rows[i][1]);
    if (seen[url]) continue;
    seen[url] = true;
    var n = url.match(/chapter-([0-9]+)/i);
    out.push(_chapter(url, _clean(rows[i][2]), n ? parseInt(n[1], 10) : out.length + 1));
  }
  return out;
}

function _pageUrls(html, url) {
  var clean = String(url).replace(/[?&]page=\d+.*$/, '');
  var max = 1;
  var re = /[?&]page=(\d+)/g, m;
  while ((m = re.exec(html)) !== null) max = Math.max(max, parseInt(m[1], 10));
  var urls = [];
  for (var p = 1; p <= max; p++) {
    urls.push(clean + (clean.indexOf('?') === -1 ? '?' : '&') + 'page=' + p);
  }
  return urls;
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h3[^>]*class="title"[^>]*>([\s\S]*?)<\/h3>/i) ||
      html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var imgM = html.match(/<div class="book">[\s\S]*?<img[^>]+src="([^"]+)"/i) ||
      html.match(/<div class="pic">[\s\S]*?<img[^>]+src="([^"]+)"/i);
    var descM = html.match(/<div class="desc-text"[^>]*>([\s\S]*?)<\/div>/i);
    var authorM = html.match(/<h3>Author:<\/h3>([\s\S]*?)<\/div>/i) ||
      html.match(/glyphicon-user[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
    var genres = [];
    var gm = html.match(/<h3>Genre:<\/h3>([\s\S]*?)<\/li>/i);
    if (gm) genres = _all(gm[1], /<a[^>]*>([\s\S]*?)<\/a>/gi).map(function(m) { return _clean(m[1]); }).filter(Boolean);
    var pages = _pageUrls(html, url);
    var first = Promise.resolve(html);
    return first.then(function() {
      var rest = pages.slice(1).map(function(p) {
        return fetch(p, { headers: { 'Referer': url } }).then(function(pr) { return pr.body || ''; });
      });
      return Promise.all(rest).then(function(bodies) {
        var list = _chapters(html);
        var seen = {};
        list.forEach(function(c) { seen[c.url] = true; });
        bodies.forEach(function(b) {
          _chapters(b).forEach(function(c) {
            if (!seen[c.url]) { seen[c.url] = true; list.push(c); }
          });
        });
        list.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
        return {
          id: _slug(url), sourceId: SOURCE_ID, title: _clean(titleM ? titleM[1] : ''),
          cover: imgM ? _abs(imgM[1]) : null, url: url,
          author: _clean(authorM ? authorM[1] : ''), authors: [], status: 'unknown',
          description: descM ? _blockText(descM[1]) : '', genres: genres,
          chapters: list, type: 'novel'
        };
      });
    });
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var bodyM = html.match(/<div[^>]+id="chapter-content"[^>]*>([\s\S]*?)<\/div>\s*(?:<div[^>]+id="chapter-nav|<hr)/i) ||
      html.match(/<div[^>]+id="chr-content"[^>]*>([\s\S]*?)<\/div>/i);
    var text = _blockText(bodyM ? bodyM[1] : '');
    var next = null;
    var nM = html.match(/<a[^>]+href="([^"]+)"[^>]*>\s*(?:<[^>]+>\s*)*Next\s*<\/a>/i);
    if (nM) next = _abs(nM[1]);
    return { text: text, nextUrl: next };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
