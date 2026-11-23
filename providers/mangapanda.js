// MangaHub — verified against mangapanda.onl (React reader, mghcdn images).

var SOURCE_ID = 'mangapanda';
var SITE = 'https://mangapanda.onl';
var REFERER = SITE + '/';

function getInfo() {
  return { name: 'MangaPanda', lang: 'en', baseUrl: SITE, logo: SITE + '/favicon.ico', type: 'manga', version: '1.0.0' };
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

function _clean(s) { return htmlText(s || '').replace(/<!--[\s\S]*?-->/g, '').replace(/\s+/g, ' ').trim(); }
function _abs(h) { return !h ? '' : (h.indexOf('http') === 0 ? h : SITE + (h.charAt(0) === '/' ? '' : '/') + h); }
function _slug(u) { var m = String(u).match(/\/manga\/([^\/?#]+)/); return m ? m[1] : String(u); }
function _num(t) { var m = String(t).match(/(?:chapter|ch\.?|#)\s*#?\s*([0-9]+(?:\.[0-9]+)?)/i); return m ? parseFloat(m[1]) : null; }

function _cards(html) {
  var out = [], seen = {};
  var list = _all(html, /<a href="(https?:\/\/[^"]+\/manga\/[^"]+)"><img[^>]*?src="([^"]+)"[^>]*?alt="([^"]*)"/g);
  for (var i = 0; i < list.length; i++) {
    var u = _abs(list[i][1]);
    if (seen[u]) continue;
    seen[u] = true;
    out.push({ id: _slug(u), title: _clean(list[i][3]), cover: _abs(list[i][2]), url: u, type: 'manga' });
  }
  return out;
}

function search(query, page) {
  page = page || 1;
  var q = String(query || '').trim();
  var url = SITE + '/search?q=' + encodeURIComponent(q) + '&order=POPULAR&genre=all' + (page > 1 ? '&page=' + page : '');
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var out = _cards(r.body || '');
    console.log('mangapanda search count: ' + out.length);
    return out;
  });
}

function getHome() {
  return fetch(SITE + '/popular', { headers: { 'Referer': REFERER } }).then(function (r) {
    return [{ title: 'Popular', items: _cards(r.body || '') }];
  });
}

function _chapters(html, slug) {
  var out = [], seen = {};
  var list = _all(html, /<a href="(https?:\/\/[^"]+\/chapter\/[^"\/]+\/chapter-[^"]+)"[^>]*>([\s\S]*?)<\/a>/g);
  for (var i = 0; i < list.length; i++) {
    var u = list[i][1];
    if (slug) {
      var owner = u.match(/\/chapter\/([^\/]+)\//);
      if (!owner || owner[1] !== slug) continue;
    }
    if (seen[u]) continue;
    seen[u] = true;
    var title = _clean(list[i][2]);
    var idM = u.match(/chapter-([^\/?#]+)$/);
    var number = _num(title);
    if (number == null && idM) {
      var fromUrl = idM[1].match(/^([0-9]+(?:\.[0-9]+)?)$/);
      if (fromUrl) number = parseFloat(fromUrl[1]);
    }
    out.push({ id: idM ? idM[1] : u, title: title || ('Chapter ' + (idM ? idM[1] : '')), number: number, url: u });
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
    var t = html.match(/<h1[^>]*class="_3xnDj"[^>]*>([\s\S]*?)<\/h1>/i);
    var title = t ? _clean(t[1].replace(/<small[\s\S]*?<\/small>/g, '').replace(/<a[^>]*>[\s\S]*?<\/a>/g, '')) : '';
    var img = html.match(/<img[^>]+class="[^"]*manga-thumb[^"]*"[^>]+src="([^"]+)"/i) ||
              html.match(/<img[^>]+src="([^"]+)"[^>]+class="[^"]*manga-thumb[^"]*"/i);
    var st = html.match(/>Status<\/span><span>([^<]+)<\/span>/i);
    var desc = html.match(/<div id="chapters-tab-pane-999"[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i);
    var authors = [], am = html.match(/>Author<\/span><span>([^<]+)<\/span>/i);
    if (am) authors.push(_clean(am[1]));
    var genres = [], gm = _all(html, /<a href="[^"]+\/genre\/[^"]+"[^>]*>([\s\S]*?)<\/a>/g);
    for (var i = 0; i < gm.length; i++) {
      var g = _clean(gm[i][1]);
      if (g && genres.indexOf(g) === -1) genres.push(g);
    }
    var chapters = _chapters(html, _slug(url));
    console.log('mangapanda detail: ' + title + ' chapters=' + chapters.length);
    return {
      id: _slug(url), title: title, cover: img ? _abs(img[1]) : null, url: url,
      description: desc ? _clean(desc[1]) : '',
      status: st ? _clean(st[1]).toLowerCase() : 'unknown',
      authors: authors, genres: genres, chapters: chapters, type: 'manga'
    };
  });
}

function getChapters(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) { return _chapters(r.body || '', _slug(url)); });
}

function getPages(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '', out = [], seen = {};
    var list = _all(html, /<img[^>]+src="(https?:\/\/[^"]*mghcdn[^"]+\.(?:jpg|jpeg|png|webp))"/gi);
    for (var i = 0; i < list.length; i++) {
      var u = list[i][1];
      if (seen[u] || /\/thumb\//.test(u)) continue;
      seen[u] = true;
      out.push({ url: u, index: out.length, headers: { 'Referer': chapterUrl } });
    }
    console.log('mangapanda pages: ' + out.length);
    return out;
  });
}

function getChapterContent() { return { text: 'MangaPanda is a manga-only source.', nextUrl: null }; }
