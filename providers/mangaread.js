// MangaRead — WordPress "Madara" manga theme. Verified against
// mangaread.org (search, detail, chapter list, and reader images).

var SOURCE_ID = 'mangaread';
var SITE = 'https://www.mangaread.org';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'MangaRead',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/favicon.ico',
    type: 'manga',
    version: '1.0.0'
  };
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

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _abs(href) {
  if (!href) return '';
  return href.indexOf('http') === 0 ? href : SITE + (href.charAt(0) === '/' ? '' : '/') + href;
}

function _slug(url) {
  var m = String(url).match(/\/manga\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

function _num(title) {
  var m = String(title).match(/(?:chapter|ch\.?)\s*([0-9]+(?:\.[0-9]+)?)/i);
  return m ? parseFloat(m[1]) : null;
}

function _status(s) {
  s = (s || '').toLowerCase();
  if (s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('complete') !== -1) return 'completed';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

function _cards(html) {
  var out = [], seen = {};
  var blocks = _all(html, /<div class="row c-tabs-item__content">([\s\S]*?)<\/div>\s*<\/div>\s*<\/div>/g);
  for (var i = 0; i < blocks.length; i++) {
    var b = blocks[i][1];
    var a = b.match(/<div class="post-title">\s*<h3[^>]*>\s*<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i);
    if (!a) continue;
    var url = _abs(a[1]);
    if (seen[url]) continue;
    seen[url] = true;
    var img = b.match(/<img[^>]+src="([^"]+)"/i);
    out.push({
      id: _slug(url),
      title: _clean(a[2]),
      cover: img ? _abs(img[1]) : null,
      url: url,
      type: 'manga'
    });
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
  var q = String(query || '').trim();
  var url = q
    ? SITE + '/page/' + page + '/?s=' + encodeURIComponent(q) + '&post_type=wp-manga'
    : SITE + '/manga/page/' + page + '/?m_orderby=views';
  console.log('mangaread search url: ' + url);
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var out = _cards(r.body || '');
    console.log('mangaread search count: ' + out.length);
    return out;
  });
}

function getHome() {
  return fetch(SITE + '/manga/?m_orderby=views', { headers: { 'Referer': REFERER } })
    .then(function (r) {
      var html = r.body || '', items = _cards(html);
      if (!items.length) items = _fallbackCards(html);
      return items.length ? [{ title: 'Popular', items: items }] : [];
    });
}

function _chapters(html) {
  var out = [], seen = {};
  var re = /<li class="wp-manga-chapter[^"]*">\s*<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>([\s\S]*?)<\/li>/g;
  var list = _all(html, re);
  for (var i = 0; i < list.length; i++) {
    var url = _abs(list[i][1]);
    if (seen[url]) continue;
    seen[url] = true;
    var title = _clean(list[i][2]);
    var dateM = list[i][3].match(/<span class="chapter-release-date[^"]*">([\s\S]*?)<\/span>/i);
    var idM = url.match(/chapter-([^\/?#]+)/);
    out.push({
      id: idM ? idM[1] : url,
      title: title,
      number: _num(title),
      url: url,
      date: dateM ? _clean(dateM[1]) : ''
    });
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
    var title = t ? _clean(t[1]) : '';
    var img = html.match(/<div class="summary_image">[\s\S]*?<img[^>]+src="([^"]+)"/i);
    var desc = html.match(/<div class="description-summary">[\s\S]*?<div class="summary__content[^"]*">([\s\S]*?)<\/div>/i);
    var st = html.match(/<h5>\s*Status\s*<\/h5>[\s\S]*?<div class="summary-content">([\s\S]*?)<\/div>/i);
    var authors = [], au = html.match(/<h5>\s*Authors?\s*<\/h5>[\s\S]*?<div class="summary-content">([\s\S]*?)<\/div>/i);
    if (au) {
      var am = _all(au[1], /<a[^>]*>([\s\S]*?)<\/a>/g);
      for (var i = 0; i < am.length; i++) authors.push(_clean(am[i][1]));
    }
    var genres = [], gm = _all(html, /<div class="genres-content">([\s\S]*?)<\/div>/g);
    for (var g = 0; g < gm.length; g++) {
      var gl = _all(gm[g][1], /<a[^>]*>([\s\S]*?)<\/a>/g);
      for (var j = 0; j < gl.length; j++) {
        var name = _clean(gl[j][1]);
        if (name && genres.indexOf(name) === -1) genres.push(name);
      }
    }
    var chapters = _chapters(html);
    console.log('mangaread detail: ' + title + ' chapters=' + chapters.length);
    return {
      id: _slug(url), title: title,
      cover: img ? _abs(img[1]) : null,
      url: url, description: desc ? _clean(desc[1]) : '',
      status: _status(st ? st[1] : ''), authors: authors, genres: genres,
      chapters: chapters, type: 'manga'
    };
  });
}

function getChapters(url) {
  return fetch(url, { headers: { 'Referer': REFERER } })
    .then(function (r) { return _chapters(r.body || ''); });
}

function getPages(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '';
    var out = [], seen = {};
    var list = _all(html, /<img[^>]+class="[^"]*wp-manga-chapter-img[^"]*"[^>]*>/gi);
    for (var i = 0; i < list.length; i++) {
      var src = list[i][0].match(/data-src="([^"]+)"/i) || list[i][0].match(/src="([^"]+)"/i);
      if (!src) continue;
      var u = src[1].replace(/^\s+|\s+$/g, '');
      if (!u || seen[u]) continue;
      seen[u] = true;
      out.push({ url: _abs(u), index: out.length, headers: { 'Referer': chapterUrl } });
    }
    console.log('mangaread pages: ' + out.length);
    return out;
  });
}

function getChapterContent() {
  return { text: 'MangaRead is a manga-only source.', nextUrl: null };
}
