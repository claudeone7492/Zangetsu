// MangaDNA — verified against mangadna.com (search, detail, chapters, pages).

var SOURCE_ID = 'mangadna';
var SITE = 'https://mangadna.com';
var REFERER = SITE + '/';

function getInfo() {
  return { name: 'MangaDNA', lang: 'en', baseUrl: SITE, logo: SITE + '/favicon.ico', type: 'manga', version: '1.0.0' };
}

function _all(html, re) {
  var out = [], m;
  re.lastIndex = 0;
  while ((m = re.exec(html)) !== null) {
    out.push(m);
    if (m.index === re.lastIndex) re.lastIndex++;
  }
  return out;
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }
function _abs(h) { return !h ? '' : (h.indexOf('http') === 0 ? h : SITE + (h.charAt(0) === '/' ? '' : '/') + h); }
function _slug(u) { var m = String(u).match(/\/manga\/([^\/?#]+)/); return m ? m[1] : String(u); }
function _num(t) { var m = String(t).match(/chapter\s*([0-9]+(?:\.[0-9]+)?)/i); return m ? parseFloat(m[1]) : null; }

function _cards(html) {
  var out = [], seen = {};
  var blocks = _all(html, /<div class="home-item">([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>/g);
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i][1];
    var a = b.match(/<h3 class="htitle">\s*<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!a) continue;
    var url = _abs(a[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var img = b.match(/<img[^>]+(?:data-src|src)="([^"]+)"/i);
    out.push({ id: _slug(url), title: _clean(a[2]), cover: img ? _abs(img[1]) : null, url: url, type: 'manga' });
  }
  return out;
}


function _fallbackCards(html) {
  var out = [], seen = {};
  var re = /<a[^>]+href="([^"]*\/manga\/[^"]+)"[^>]*(?:title="([^"]*)")?[^>]*>([\s\S]*?)<\/a>/g;
  var list = _all(html, re);
  for (var i = 0; i < list.length; i++) {
    var url = _abs(list[i][1]);
    if (/\/chapter[-\/]/i.test(url) || seen[url]) continue;
    var title = _clean(list[i][2] || list[i][3]);
    if (!title || /^chapter\b/i.test(title)) continue;
    seen[url] = true;
    var at = html.indexOf(list[i][0]);
    var back = at > 0 ? html.substring(Math.max(0, at - 900), at) : '';
    var img = back.match(/<img[^>]+(?:data-src|src)="([^"]+)"/i);
    out.push({ id: _slug(url), title: title, cover: img ? _abs(img[1]) : null, url: url, type: 'manga' });
  }
  return out;
}

function search(query, page) {
  page = page || 1;
  var url = SITE + '/search?q=' + encodeURIComponent(String(query || '').trim()) + (page > 1 ? '&page=' + page : '');
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var out = _cards(r.body || '');
    console.log('mangadna search count: ' + out.length);
    return out;
  });
}

function getHome() {
  return fetch(SITE + '/', { headers: { 'Referer': REFERER } })
    .then(function (r) {
      var html = r.body || '', items = _cards(html);
      if (!items.length) items = _fallbackCards(html);
      return items.length ? [{ title: 'Latest', items: items }] : [];
    });
}

function _chapters(html) {
  var out = [], seen = {};
  var list = _all(html, /<a class="chapter-name[^"]*" href="([^"]+)"[^>]*title="([^"]*)"[^>]*>([\s\S]*?)<\/a>\s*<span class="chapter-time[^"]*"[^>]*>([\s\S]*?)<\/span>/g);
  for (var i = 0; i < list.length; i++) {
    var url = _abs(list[i][1]);
    if (seen[url]) continue;
    seen[url] = true;
    var title = _clean(list[i][3]) || _clean(list[i][2]);
    var idM = url.match(/chapter-([^\/?#]+)/);
    out.push({ id: idM ? idM[1] : url, title: title, number: _num(title), url: url, date: _clean(list[i][4]) });
  }
  out.sort(function (a, b) {
    if (a.number == null) return -1;
    if (b.number == null) return 1;
    return a.number - b.number;
  });
  return out;
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '';
    var t = html.match(/<div class="post-title">\s*<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var img = html.match(/<div class="summary_image">[\s\S]*?<img[^>]+(?:data-src|src)="([^"]+)"/i);
    var desc = html.match(/<div class="dsct">([\s\S]*?)<\/div>/i);
    var st = html.match(/<h5>\s*Status\s*<\/h5>[\s\S]*?<div class="summary-content"[^>]*>([\s\S]*?)<\/div>/i);
    var genres = [], gm = _all(html, /<a href="\/genre\/[^"]+"[^>]*>([\s\S]*?)<\/a>/g);
    for (var i = 0; i < gm.length; i++) {
      var g = _clean(gm[i][1]);
      if (g && genres.indexOf(g) === -1) genres.push(g);
    }
    var authors = [], am = _all(html, /<h5>\s*Author\(s\)\s*<\/h5>[\s\S]*?<div class="summary-content"[^>]*>([\s\S]*?)<\/div>/g);
    if (am.length) {
      var al = _all(am[0][1], /<a[^>]*>([\s\S]*?)<\/a>/g);
      for (var j = 0; j < al.length; j++) authors.push(_clean(al[j][1]));
    }
    var chapters = _chapters(html);
    console.log('mangadna detail: ' + (t ? _clean(t[1]) : '') + ' chapters=' + chapters.length);
    return {
      id: _slug(url), title: t ? _clean(t[1]) : '',
      cover: img ? _abs(img[1]) : null, url: url,
      description: desc ? _clean(desc[1]) : '',
      status: st ? _clean(st[1]).toLowerCase() : 'unknown',
      authors: authors, genres: genres, chapters: chapters, type: 'manga'
    };
  });
}

function getChapters(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) { return _chapters(r.body || ''); });
}

function _sleep(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }

function _fetchRetry(url, headers, tries) {
  tries = tries || 3;
  return fetch(url, { headers: headers }).catch(function (e) {
    if (tries <= 1) throw e;
    return _sleep(700).then(function () { return _fetchRetry(url, headers, tries - 1); });
  });
}

function getPages(chapterUrl) {
  return _fetchRetry(chapterUrl, { 'Referer': REFERER }, 3).then(function (r) {
    var html = r.body || '';
    var out = [], seen = {};
    var list = _all(html, /<img[^>]+src="([^"]+\.(?:jpg|jpeg|png|webp))"/gi);
    for (var i = 0; i < list.length; i++) {
      var u = list[i][1];
      if (u.indexOf('/thumbnails/') !== -1 || u.indexOf('/images/') !== -1) continue;
      if (seen[u]) continue;
      seen[u] = true;
      out.push({ url: _abs(u), index: out.length, headers: { 'Referer': chapterUrl } });
    }
    console.log('mangadna pages: ' + out.length);
    return out;
  });
}

function getChapterContent() { return { text: 'MangaDNA is a manga-only source.', nextUrl: null }; }
