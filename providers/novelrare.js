// NovelRare provider — https://novelrare.com
// WordPress "Novel Edge" theme. The reader exposes a JSON chapter archive:
//   /wp-json/novel-edge/v1/reader-chapters/<novelId>?anchor=N&direction=asc&limit=100
// which returns up to 100 chapters per call plus `has_more`.

var SOURCE_ID = 'novelrare';
var SITE = 'https://novelrare.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelRare', lang: 'en', baseUrl: SITE,
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
  var re = /<article class="ne-card"[\s\S]*?<a class="ne-card-cover" href="([^"]+)">[\s\S]*?<img[^>]+src="([^"]+)"[\s\S]*?<a class="ne-card-title" href="[^"]*">([\s\S]*?)<\/a>/g;
  while ((m = re.exec(html)) !== null) {
    var url = _abs(m[1]);
    if (seen[url]) continue;
    seen[url] = true;
    out.push({
      id: _slug(url), title: _clean(m[3]), cover: _abs(m[2]),
      url: url, author: '', description: '', type: 'novel'
    });
  }
  return out;
}

function _searchCards(html) {
  var out = [], seen = {}, m;
  var re = /<article>([\s\S]*?)<\/article>/g;
  while ((m = re.exec(html)) !== null) {
    var block = m[1];
    var linkM = block.match(/<h2><a href="([^"]+)">([\s\S]*?)<\/a><\/h2>/i);
    if (!linkM) continue;
    var url = _abs(linkM[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var descM = block.match(/<p>([\s\S]*?)<\/p>/i);
    out.push({
      id: _slug(url), title: _clean(linkM[2]), cover: null,
      url: url, author: '',
      description: descM ? _blockText(descM[1]) : '', type: 'novel'
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
  var u = SITE + '/?s=' + encodeURIComponent(q);
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

function _archive(id) {
  var out = [], anchor = 50, guard = 0;
  function step() {
    if (guard++ > 80) return Promise.resolve(out);
    var u = SITE + '/wp-json/novel-edge/v1/reader-chapters/' + encodeURIComponent(id) +
      '?anchor=' + anchor + '&direction=asc&limit=100';
    return fetch(u, { headers: { 'Referer': REFERER, 'Accept': 'application/json' } })
      .then(function(r) {
        var j = {};
        try { j = JSON.parse(r.body || '{}'); } catch (e) { return out; }
        var items = j.items || [];
        if (!items.length) return out;
        for (var i = 0; i < items.length; i++) {
          var it = items[i];
          out.push(_chapter(it.url, it.label || ('Chapter ' + it.number), it.number));
        }
        if (!j.has_more) return out;
        anchor += 100;
        return step();
      });
  }
  return step().then(function(list) {
    var seen = {};
    return list.filter(function(c) {
      if (seen[c.url]) return false;
      seen[c.url] = true;
      return true;
    }).sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
  });
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h1 class="ne-novel-title"[^>]*>([\s\S]*?)<\/h1>/i);
    var coverM = html.match(/<div class="ne-novel-cover"><img[^>]+src="([^"]+)"/i);
    var authorM = html.match(/<b>Author:<\/b>\s*<a[^>]*>([\s\S]*?)<\/a>/i);
    var statusM = html.match(/<b>Status:<\/b>\s*([^<]+)/i);
    var descM = html.match(/<section class="ne-section ne-panel ne-prose">([\s\S]*?)<\/section>/i);
    var genres = [], gm, gre = /<div class="ne-tax">([\s\S]*?)<\/div>/i;
    var gblock = html.match(gre);
    if (gblock) {
      var ga = /<a[^>]*>([\s\S]*?)<\/a>/g;
      while ((gm = ga.exec(gblock[1])) !== null) genres.push(_clean(gm[1]));
    }
    var idM = html.match(/data-ne-stats[^>]*data-id="(\d+)"/i) ||
      html.match(/wp-json\/wp\/v2\/ne_novel\/(\d+)/i);
    var id = idM ? idM[1] : '';
    var chapters = id ? _archive(id) : Promise.resolve([]);
    return chapters.then(function(list) {
      return {
        id: id || _slug(url), sourceId: SOURCE_ID,
        title: _clean(titleM ? titleM[1] : _meta(html, 'og:title')),
        cover: coverM ? _abs(coverM[1]) : null, url: _abs(url),
        author: _clean(authorM ? authorM[1] : ''),
        authors: authorM ? [_clean(authorM[1])] : [],
        status: _clean(statusM ? statusM[1] : ''),
        description: _blockText(descM ? descM[1] : _meta(html, 'og:description')),
        genres: genres, chapters: list, type: 'novel'
      };
    });
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var blockM = html.match(/<div[^>]*class="ne-reader-chapter-text"[^>]*>([\s\S]*?)<\/div>/i);
    var block = blockM ? blockM[1] : '';
    block = block.replace(/<h1[^>]*>[\s\S]*?<\/h1>/i, '');
    var nextM = html.match(/<a href="([^"]+)"[^>]+aria-label="Next chapter"/i) ||
      html.match(/<a[^>]+aria-label="Next chapter"[^>]+href="([^"]+)"/i);
    return { text: _blockText(block), nextUrl: nextM ? _abs(nextM[1]) : null };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
