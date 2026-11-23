// ReadNovelFull provider — https://readnovelfull.com
// NovelFull-family site. Search and home render the classic
// `div.list-novel > div.row` card; a novel's full chapter archive comes from
// /ajax/chapter-archive?novelId=<id>, and chapters are plain text.

var SOURCE_ID = 'readnovelfull';
var SITE = 'https://readnovelfull.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'ReadNovelFull', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'novel', version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }

function _all(html, re) {
  var out = [], m;
  re.lastIndex = 0;
  while ((m = re.exec(html)) !== null) {
    out.push(m);
    if (m.index === re.lastIndex) re.lastIndex++;
  }
  return out;
}

function _abs(href) { return absUrl(href || '', SITE); }

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
  var rows = _all(html, /<div class="row">([\s\S]*?)(?=<div class="row">|<\/div>\s*<\/div>\s*<\/div>|$)/g);
  for (var i = 0; i < rows.length; i++) {
    var b = rows[i][1];
    var aM = b.match(/<h3[^>]*class="novel-title"[^>]*>\s*<a[^>]+href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!aM) continue;
    var url = _abs(aM[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var imgM = b.match(/<img[^>]+src="([^"]+)"/i);
    var authorM = b.match(/class="author"[^>]*>([\s\S]*?)<\/span>/i);
    out.push({
      id: _slug(url), title: _clean(aM[2]),
      cover: imgM ? _abs(imgM[1]) : null, url: url,
      author: authorM ? _clean(authorM[1]) : '', description: '', type: 'novel'
    });
  }
  return out;
}

function getHome() {
  return search('', 1).then(function(items) {
    return items.length ? [{ title: 'Latest Novels', items: items }] : [];
  });
}

function search(query, page) {
  page = page || 1;
  var q = String(query || '').trim();
  var url = SITE + '/novel-list/search?keyword=' + encodeURIComponent(q) +
    (page > 1 ? '&page=' + page : '');
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    return _cards(r.body || '');
  });
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

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i) || html.match(/<h3[^>]*class="novel-title"[^>]*>([\s\S]*?)<\/h3>/i);
    var imgM = html.match(/<div class="book"[^>]*>[\s\S]*?<img[^>]+src="([^"]+)"/i) ||
      html.match(/<div class="col-xs-3">[\s\S]*?<img[^>]+src="([^"]+)"/i) ||
      html.match(/<img[^>]+class="cover"[^>]+src="([^"]+)"/i);
    var descM = html.match(/<div class="desc-text"[^>]*>([\s\S]*?)<\/div>/i) ||
      html.match(/<div id="novel-summary"[^>]*>([\s\S]*?)<\/div>/i);
    var authorM = html.match(/<span class="author"[^>]*>([\s\S]*?)<\/span>/i);
    var genres = [];
    var gm = html.match(/<h3>Genre:<\/h3>([\s\S]*?)<\/li>/i);
    if (gm) genres = _all(gm[1], /<a[^>]*>([\s\S]*?)<\/a>/gi).map(function(m) { return _clean(m[1]); }).filter(Boolean);
    var idM = html.match(/data-novel-id="(\d+)"/);
    var chapters;
    if (idM) {
      chapters = fetch(SITE + '/ajax/chapter-archive?novelId=' + idM[1], {
        headers: { 'Referer': url, 'X-Requested-With': 'XMLHttpRequest' }
      }).then(function(cr) { return _chapters(cr.body || ''); });
    } else {
      chapters = Promise.resolve(_chapters(html));
    }
    return chapters.then(function(list) {
      return {
        id: _slug(url), sourceId: SOURCE_ID, title: _clean(titleM ? titleM[1] : ''),
        cover: imgM ? _abs(imgM[1]) : null, url: url,
        author: _clean(authorM ? authorM[1] : ''), authors: [], status: 'unknown',
        description: descM ? _blockText(descM[1]) : '', genres: genres,
        chapters: list, type: 'novel'
      };
    });
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var bodyM = html.match(/<div[^>]+id="chr-content"[^>]*>([\s\S]*?)<\/div>/i) ||
      html.match(/<div[^>]+class="[^"]*chapter-content[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    var text = _blockText(bodyM ? bodyM[1] : '');
    var next = null;
    var nM = html.match(/<a[^>]+id="next_chap"[^>]+href="([^"]+)"/i) ||
      html.match(/<a[^>]+href="([^"]+)"[^>]+id="next_chap"/i) ||
      html.match(/<a[^>]+href="([^"]+)"[^>]*>\s*(?:<[^>]+>\s*)*Next\s*<\/a>/i);
    if (nM) next = _abs(nM[1]);
    return { text: text, nextUrl: next };
  });
}
