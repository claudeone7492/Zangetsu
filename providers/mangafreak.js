// MangaFreak — verified against ww3.mangafreak.me.

var SOURCE_ID = 'mangafreak';
var SITE = 'https://ww3.mangafreak.me';
var REFERER = SITE + '/';

function getInfo() {
  return { name: 'MangaFreak', lang: 'en', baseUrl: SITE, logo: SITE + '/favicon.ico', type: 'manga', version: '1.0.0' };
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
function _slug(u) { var m = String(u).match(/\/Manga\/([^\/?#]+)/i); return m ? m[1] : String(u); }
function _num(t) { var m = String(t).match(/chapter\s*([0-9]+(?:\.[0-9]+)?)/i); return m ? parseFloat(m[1]) : null; }

function search(query, page) {
  page = page || 1;
  var url = SITE + '/Find/' + encodeURIComponent(String(query || '').trim()) + (page > 1 ? '?page=' + page : '');
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '', out = [], seen = {};
    var list = _all(html, /<div class="manga_search_item">([\s\S]*?)<\/div>\s*<\/div>/g);
    for (var i = 0; i < list.length; i++) {
      var b = list[i][1];
      var a = b.match(/<h3>\s*<a href="([^"]+)">([\s\S]*?)<\/a>/i);
      if (!a) continue;
      var u = _abs(a[1]);
      if (seen[u]) continue;
      seen[u] = true;
      var img = b.match(/<img[^>]+src="([^"]+)"/i);
      out.push({ id: _slug(u), title: _clean(a[2]), cover: img ? _abs(img[1]) : null, url: u, type: 'manga' });
    }
    console.log('mangafreak search count: ' + out.length);
    return out;
  });
}

function getHome() {
  return fetch(SITE + '/MangaList/Hot', { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '', out = [], seen = {};
    var list = _all(html, /<div class="manga_search_item">([\s\S]*?)<\/div>\s*<\/div>/g);
    for (var i = 0; i < list.length; i++) {
      var b = list[i][1];
      var a = b.match(/<h3>\s*<a href="([^"]+)">([\s\S]*?)<\/a>/i);
      if (!a) continue;
      var u = _abs(a[1]);
      if (seen[u]) continue;
      seen[u] = true;
      var img = b.match(/<img[^>]+src="([^"]+)"/i);
      out.push({ id: _slug(u), title: _clean(a[2]), cover: img ? _abs(img[1]) : null, url: u, type: 'manga' });
    }
    return [{ title: 'Hot', items: out }];
  });
}

function _chapters(html) {
  var out = [], seen = {};
  var list = _all(html, /<a class="chapter-link" href="([^"]+)"[^>]*>([\s\S]*?)<\/a>\s*<\/td>\s*<td>([^<]*)<\/td>/g);
  for (var i = 0; i < list.length; i++) {
    var u = _abs(list[i][1]);
    if (seen[u]) continue;
    seen[u] = true;
    var title = _clean(list[i][2]);
    var idM = u.match(/_([0-9.]+)$/);
    out.push({ id: idM ? idM[1] : u, title: title, number: _num(title), url: u, date: _clean(list[i][3]) });
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
    var t = html.match(/<div class="manga_series_data">\s*<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var img = html.match(/<div class="manga_series_image">\s*<img[^>]+src="([^"]+)"/i);
    var desc = html.match(/<div class="manga_series_description">[\s\S]*?<p>([\s\S]*?)<\/p>/i);
    var st = html.match(/This is\s+(ON-GOING|COMPLETED|HIATUS)\s+series/i);
    var genres = [], gm = _all(html, /<div class="series_sub_genre_list">([\s\S]*?)<\/div>/g);
    if (gm.length) {
      var gl = _all(gm[0][1], /<a[^>]*>([\s\S]*?)<\/a>/g);
      for (var i = 0; i < gl.length; i++) genres.push(_clean(gl[i][1]));
    }
    var authors = [], am = html.match(/Written By:\s*([^<]+)/i);
    if (am) authors.push(_clean(am[1]));
    var chapters = _chapters(html);
    console.log('mangafreak detail: ' + (t ? _clean(t[1]) : '') + ' chapters=' + chapters.length);
    return {
      id: _slug(url), title: t ? _clean(t[1]) : '',
      cover: img ? _abs(img[1]) : null, url: url,
      description: desc ? _clean(desc[1]) : '',
      status: st ? (st[1].toLowerCase() === 'on-going' ? 'ongoing' : st[1].toLowerCase()) : 'unknown',
      authors: authors, genres: genres, chapters: chapters, type: 'manga'
    };
  });
}

function getChapters(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) { return _chapters(r.body || ''); });
}

function getPages(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '', out = [], seen = {};
    var list = _all(html, /<img[^>]+src="(https?:\/\/images\.mangafreak\.me\/mangas\/[^"]+\.(?:jpg|jpeg|png|webp))"/gi);
    for (var i = 0; i < list.length; i++) {
      var u = list[i][1];
      if (seen[u]) continue;
      seen[u] = true;
      out.push({ url: u, index: out.length, headers: { 'Referer': chapterUrl } });
    }
    console.log('mangafreak pages: ' + out.length);
    return out;
  });
}

function getChapterContent() { return { text: 'MangaFreak is a manga-only source.', nextUrl: null }; }
