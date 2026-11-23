// NovelHi provider — https://novelhi.com
// Search uses /book/searchBookListWithShelfState, the full archive comes from
// /book/queryIndexList, and chapter bodies require the per-page token plus a
// ROT13 pass when the server flags font obfuscation.

var SOURCE_ID = 'novelhi';
var SITE = 'https://novelhi.com';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelHi', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'novel', version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }
function _abs(href) { return absUrl(href || '', SITE); }
function _slug(url) { return String(url || '').replace(/[?#].*$/, '').replace(/\/+$/, '').split('/').pop(); }

function _json(body) {
  try { return JSON.parse(body || '{}'); } catch (e) { return {}; }
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

function _rot13(s) {
  return String(s || '').replace(/[a-zA-Z]/g, function(c) {
    var base = c <= 'Z' ? 65 : 97;
    return String.fromCharCode((c.charCodeAt(0) - base + 13) % 26 + base);
  });
}

function _item(b) {
  var genre = (b.genres && b.genres[0] && b.genres[0].genreName) || 'action';
  var gslug = String(genre).toLowerCase().replace(/\s+/g, '-');
  return {
    id: b.id, title: b.bookName || '', cover: b.picUrl || null,
    url: SITE + '/novel/' + gslug + '/' + (b.novelSlug || b.simpleName || b.id),
    author: b.authorName || '', description: _blockText(b.bookDesc || ''),
    status: b.bookStatus === '0' ? 'ongoing' : 'completed', type: 'novel'
  };
}

function _homeCards(html) {
  var out = [], seen = {}, m;
  var re = /<li class="home_img_li">([\s\S]*?)<\/li>/gi;
  while ((m = re.exec(html)) !== null) {
    var b = m[1];
    var aM = b.match(/<a[^>]+class="home-cover-link"[^>]+href="([^"]+)"/i) ||
      b.match(/<a[^>]+href="([^"]+)"[^>]*>\s*<img[^>]+class="home_img"/i);
    if (!aM) continue;
    var url = _abs(aM[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var titleM = b.match(/<a[^>]+class="c_l home_book"[^>]*>([\s\S]*?)<\/a>/i) ||
      b.match(/<h4[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i);
    var imgM = b.match(/<img[^>]+class="home_img"[^>]+src="([^"]+)"/i) ||
      b.match(/<img[^>]+src="([^"]+)"/i);
    out.push({
      id: _slug(url), title: _clean(titleM ? titleM[1] : ''),
      cover: imgM ? _abs(imgM[1]) : null, url: url,
      author: '', description: '', type: 'novel'
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
  var u = SITE + '/book/searchBookListWithShelfState?curr=' + (page || 1) +
    '&limit=20&keyword=' + encodeURIComponent(q);
  return fetch(u, { headers: { 'Referer': SITE + '/novel', 'Accept': 'application/json' } })
    .then(function(r) {
      var j = _json(r.body);
      return ((j.data && j.data.list) || []).map(_item);
    });
}

function _chapterObj(c, base) {
  return {
    id: c.id || String(c.indexNum), title: c.indexName || ('Chapter ' + c.indexNum),
    number: parseInt(c.indexNum, 10) || null,
    url: base + '/' + c.indexNum, date: c.createTime || ''
  };
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var descM = html.match(/<p[^>]+class="detail-desc"[^>]*>([\s\S]*?)<\/p>/i);
    var ld = {};
    var ldRe = /<script[^>]+application\/ld\+json[^>]*>([\s\S]*?)<\/script>/gi, lm;
    while ((lm = ldRe.exec(html)) !== null) {
      var cand = _json(lm[1]);
      if (cand && cand['@type'] === 'Book') { ld = cand; break; }
    }
    var bookIdM = html.match(/id="bookId"[^>]+value="(\d+)"/i);
    var canonicalM = html.match(/id="canonicalNovelPath"[^>]+value="([^"]+)"/i);
    var base = canonicalM ? SITE + canonicalM[1] : url.replace(/\/$/, '');
    var chapters;
    if (bookIdM) {
      chapters = fetch(SITE + '/book/queryIndexList?bookId=' + bookIdM[1] + '&curr=1&limit=5000', {
        headers: { 'Referer': url, 'Accept': 'application/json' }
      }).then(function(cr) {
        var j = _json(cr.body);
        var list = (j.data && j.data.list || []).map(function(c) { return _chapterObj(c, base); });
        list.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
        return list;
      });
    } else {
      chapters = Promise.resolve([]);
    }
    return chapters.then(function(list) {
      var genres = [];
      if (ld.genre) genres = String(ld.genre).split(/[,/]/).map(function(x) { return x.trim(); }).filter(Boolean);
      return {
        id: bookIdM ? bookIdM[1] : '', sourceId: SOURCE_ID,
        title: _clean(titleM ? titleM[1] : (ld.name || '')),
        cover: ld.image || null, url: base,
        author: (ld.author && ld.author.name) || '',
        authors: ld.author && ld.author.name ? [ld.author.name] : [],
        status: ld.bookFormat || '', description: descM ? _blockText(descM[1]) : _blockText(ld.description || ''),
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
    var pathM = html.match(/id="chapterContentPath"[^>]+value="([^"]+)"/i);
    var tokenM = html.match(/id="chapterContentToken"[^>]+value="([^"]+)"/i);
    var nextM = html.match(/id="nextIndexNum"[^>]+value="(\d+)"/i);
    if (!pathM || !tokenM) return { text: '', nextUrl: null };
    var contentUrl = SITE + pathM[1] + '?token=' + encodeURIComponent(tokenM[1]);
    return fetch(contentUrl, {
      headers: {
        'Referer': chapterUrl, 'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json'
      }
    }).then(function(cr) {
      var j = _json(cr.body);
      var d = j.data || {};
      var text = _blockText(d.content || '');
      if (d.fontObfuscation) text = _rot13(text);
      var next = null;
      if (nextM) next = chapterUrl.replace(/\/[0-9]+\/?$/, '/' + nextM[1]);
      return { text: text, nextUrl: next };
    });
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
