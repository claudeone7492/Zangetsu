// MangaNato — new 2026 layout. Chapter list comes from the site's
// own JSON endpoint; pages are served from the 2xstorage CDN via mangagoku.

var SOURCE_ID = 'manganato';
var SITE = 'https://www.manganato.gg';
var REFERER = SITE + '/';

function getInfo() {
  return { name: 'MangaNato', lang: 'en', baseUrl: SITE, logo: SITE + '/favicon.ico', type: 'manga', version: '1.0.0' };
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

function _cards(html) {
  var out = [], seen = {}, covers = {};
  var imgs = _all(html, /<a href="([^"]*\/manga\/[^"]+)"[^>]*>\s*<img[^>]+src="([^"]+)"/g);
  for (var i = 0; i < imgs.length; i++) covers[_abs(imgs[i][1])] = _abs(imgs[i][2]);
  var titles = _all(html, /<h3 class="story_name">\s*<a href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/g);
  for (var j = 0; j < titles.length; j++) {
    var u = _abs(titles[j][1]);
    if (seen[u]) continue;
    seen[u] = true;
    out.push({ id: _slug(u), title: _clean(titles[j][2]), cover: covers[u] || null, url: u, type: 'manga' });
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
  var slug = q.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  var url = q ? SITE + '/search/story/' + slug + (page > 1 ? '?page=' + page : '') : SITE + '/manga-list';
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var out = _cards(r.body || '');
    console.log('manganato search count: ' + out.length);
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

function _chapterUrl(html, slug) {
  var t = html.match(/data-chapter-url-template="([^"]+)"/i);
  if (!t) return SITE + '/manga/' + slug + '/';
  return t[1].replace('__MANGA__', slug).replace('/__CHAPTER__', '');
}

function _apiUrl(html, slug) {
  var a = html.match(/data-api-url="([^"]+)"/i);
  if (!a) return SITE + '/api/manga/' + slug + '/chapters?limit=2000&offset=0';
  return a[1].replace('__SLUG__', slug) + '?limit=2000&offset=0';
}

function _chaptersFromJson(body, base) {
  var out = [];
  var data;
  try { data = JSON.parse(body); } catch (e) { return out; }
  var list = (data && data.data && data.data.chapters) || [];
  for (var i = 0; i < list.length; i++) {
    var c = list[i];
    var slug = c.chapter_slug || ('chapter-' + c.chapter_num);
    out.push({
      id: slug,
      title: c.chapter_name || ('Chapter ' + c.chapter_num),
      number: c.chapter_num != null ? c.chapter_num : null,
      url: base.replace(/\/$/, '') + '/' + slug,
      date: c.updated_at || ''
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
    var slugM = html.match(/data-comic-slug="([^"]+)"/i);
    var slug = slugM ? slugM[1] : _slug(url);
    var t = html.match(/<div class="manga-info-text">\s*<h1[^>]*>([\s\S]*?)<\/h1>/i) ||
            html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var img = html.match(/<div class="manga-info-pic">\s*<img[^>]+src="([^"]+)"/i) ||
              html.match(/<img[^>]+src="([^"]+)"[^>]+alt="[^"]*"/i);
    var st = html.match(/Status\s*<\/[^>]+>\s*<[^>]+>([^<]+)</i);
    var desc = html.match(/<div id="contentBox"[^>]*>([\s\S]*?)<\/div>/i);
    var authors = [], am = html.match(/Author\(s\)\s*:\s*([^<]+)/i);
    if (am) authors = am[1].split(/[,;]/).map(function (x) { return _clean(x); }).filter(Boolean);
    var genres = [], gm = _all(html, /<a href="[^"]+\/genre\/[^"]+"[^>]*>([\s\S]*?)<\/a>/g);
    for (var i = 0; i < gm.length; i++) {
      var g = _clean(gm[i][1]);
      if (g && genres.indexOf(g) === -1) genres.push(g);
    }
    var api = _apiUrl(html, slug);
    var base = _chapterUrl(html, slug);
    return fetch(api, { headers: { 'Referer': url } }).then(function (jr) {
      var chapters = _chaptersFromJson(jr.body || '', base);
      console.log('manganato detail: ' + (t ? _clean(t[1]) : '') + ' chapters=' + chapters.length);
      return {
        id: slug, title: t ? _clean(t[1]) : '', cover: img ? _abs(img[1]) : null, url: url,
        description: desc ? _clean(desc[1]) : '',
        status: st ? _clean(st[1]).toLowerCase() : 'unknown',
        authors: authors, genres: genres, chapters: chapters, type: 'manga'
      };
    });
  });
}

function getChapters(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '';
    var slugM = html.match(/data-comic-slug="([^"]+)"/i);
    var slug = slugM ? slugM[1] : _slug(url);
    return fetch(_apiUrl(html, slug), { headers: { 'Referer': url } }).then(function (jr) {
      return _chaptersFromJson(jr.body || '', _chapterUrl(html, slug));
    });
  });
}

function getPages(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function (r) {
    var html = r.body || '', out = [], seen = {};
    var list = _all(html, /<img[^>]+src=['"](https?:\/\/[^'"]+\.(?:jpg|jpeg|png|webp))['"]/gi);
    for (var i = 0; i < list.length; i++) {
      var u = list[i][1];
      if (u.indexOf('/thumb/') !== -1 || u.indexOf('logo') !== -1 || seen[u]) continue;
      seen[u] = true;
      out.push({ url: u, index: out.length, headers: { 'Referer': chapterUrl } });
    }
    console.log('manganato pages: ' + out.length);
    return out;
  });
}

function getChapterContent() { return { text: 'MangaNato is a manga-only source.', nextUrl: null }; }
