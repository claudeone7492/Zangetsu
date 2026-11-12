// GoodShort provider — https://www.goodshort.com
//
// GoodShort is a short-drama service: a "book" is a show with ~60–80
// one-minute vertical chapters. Its web app talks to a small JSON API under
// /hwycreels that needs no auth and no keys — a POST with a JSON body returns
// the page. This provider uses those four endpoints:
//   POST /hwycreels/home/index              → pageColumns[] (named rails)
//   POST /hwycreels/book/search/recommend/v1 → book search
//   POST /hwycreels/book/detail             → book + chapterVoList (all chapters)
//   POST /hwycreels/chapter/detail          → one chapter's m3u8Path (HLS)
//
// Free chapters carry `m3u8Path` inline in the detail response; locked ones
// return null and are filtered out, so every listed episode is playable.
// URLs carry what the next call needs: a show is `gs:<bookId>|<resourceUrl>`
// and an episode is `gs:<bookId>|<resourceUrl>|<chapterId>`. Verified live.

var SOURCE_ID = 'goodshort';
var SITE = 'https://www.goodshort.com';
var LANG = 'en';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function _headers() {
  return {
    'User-Agent': UA,
    'Accept': 'application/json, text/plain, */*',
    'Content-Type': 'application/json',
    'Referer': SITE + '/',
    'Origin': SITE
  };
}

function _post(path, body) {
  return fetch(SITE + path, {
    method: 'POST',
    headers: _headers(),
    body: JSON.stringify(body)
  }).then(function (r) {
    if (!r.ok) throw new Error('GoodShort: HTTP ' + r.status);
    var j;
    try { j = JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('GoodShort: bad JSON'); }
    if (j && j.success === false) throw new Error('GoodShort: ' + (j.message || 'request failed'));
    return j || {};
  });
}

function getInfo() {
  return {
    name: 'GoodShort', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// ── mapping ─────────────────────────────────────────────────────────────────
function _showUrl(bookId, resourceUrl) {
  return 'gs:' + bookId + '|' + (resourceUrl || '');
}

function _mapBook(b) {
  if (!b || !b.bookId) return null;
  var res = b.bookResourceUrl || b.seoBookName || '';
  return {
    id: String(b.bookId),
    title: b.bookName || b.seoBookName || String(b.bookId),
    cover: b.cover || b.cover2 || b.bannerUrl || null,
    banner: b.bannerUrl || null,
    url: _showUrl(b.bookId, res),
    type: 'movie',
    sourceId: SOURCE_ID
  };
}

function _mapBooks(list) {
  var out = [];
  if (!list || !list.length) return out;
  for (var i = 0; i < list.length; i++) {
    var m = _mapBook(list[i]);
    if (m) out.push(m);
  }
  return out;
}

// ── home / browse ───────────────────────────────────────────────────────────
function getHome(opts) {
  return _post('/hwycreels/home/index', { language: LANG, page: 1 })
    .then(function (j) {
      var cols = (j.data && j.data.pageColumns) || [];
      var out = [];
      for (var i = 0; i < cols.length; i++) {
        var c = cols[i];
        // The banner rail is art, not a poster row — skip it for the poster
        // grid; its titles still appear in the rails below.
        if (String(c.style || '').toUpperCase() === 'BANNER') continue;
        var items = _mapBooks(c.items);
        if (items.length) out.push({ title: c.name || 'Featured', items: items });
      }
      return out;
    }).catch(function () { return []; });
}

function popular(opts) {
  return _post('/hwycreels/home/index', { language: LANG, page: 1 })
    .then(function (j) {
      var cols = (j.data && j.data.pageColumns) || [];
      for (var i = 0; i < cols.length; i++) {
        if (String(cols[i].style || '').toUpperCase() === 'BANNER') continue;
        var items = _mapBooks(cols[i].items);
        if (items.length) return items;
      }
      return [];
    }).catch(function () { return []; });
}

// ── search ──────────────────────────────────────────────────────────────────
// The public "recommend" endpoint ignores the keyword entirely (it returns the
// same curated set for any query) and rejects a missing `genderEnum`, so the
// real keyword search is the SEO endpoint the search page itself calls. It
// answers with paged `records`. The recommend endpoint is kept as a fallback
// for the rare case SEO returns nothing.
function search(query, page, opts) {
  var q = String(query || '');
  if (!q) return Promise.resolve([]);
  var p = page || 1;
  return _post('/hwycreels/book/search/seo', {
    seoKeywordFormat: q, keyword: q, pageNo: p, pageSize: 20,
    rid: '', type: 'DEFAULT', seoSearch: true, recommendBook: 1
  }).then(function (j) {
    var d = j.data || {};
    var list = (d.page && d.page.records) || d.records || [];
    if (list.length) return _mapBooks(list);
    return _recommend(q, p);
  }).catch(function () { return _recommend(q, p); });
}

function _recommend(q, p) {
  return _post('/hwycreels/book/search/recommend/v1', {
    keyword: q, language: LANG, page: p, pageSize: 20, genderEnum: 'ALL'
  }).then(function (j) {
    var d = j.data || {};
    var rec = (d.recommendInfo && d.recommendInfo.recommendBooks) || [];
    var list = rec.length ? rec : (d.mostTrending || d.newReleases || []);
    return _mapBooks(list);
  }).catch(function () { return []; });
}

// ── detail / episodes ───────────────────────────────────────────────────────
function _parseShow(url) {
  var s = String(url || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  return { bookId: parts[0], resource: parts[1] };
}

function getDetail(url, opts) {
  var p = _parseShow(url);
  if (!p.bookId) return Promise.resolve(null);
  return _post('/hwycreels/book/detail', { bookId: p.bookId, language: LANG })
    .then(function (j) {
      var d = j.data || {};
      var b = d.book || {};
      var res = p.resource || b.bookResourceUrl || '';
      var chapters = d.chapterVoList || [];
      var eps = [];
      for (var i = 0; i < chapters.length; i++) {
        var c = chapters[i];
        if (!c || c.id == null) continue;
        // Only chapters with a stream are playable; locked ones carry no
        // m3u8Path and would dead-end in the player.
        if (!c.m3u8Path) continue;
        var n = (c.index != null ? c.index : i) + 1;
        eps.push({
          id: String(c.id),
          title: c.chapterName || ('Episode ' + n),
          number: n,
          url: _showUrl(p.bookId, res) + '|' + c.id,
          thumbnail: c.image || null
        });
      }
      var genres = [];
      var tags = b.tagsList || [];
      for (var k = 0; k < tags.length; k++) {
        if (tags[k] && tags[k].name) genres.push(tags[k].name);
      }
      return {
        id: String(p.bookId),
        title: b.bookName || b.seoBookName || String(p.bookId),
        url: _showUrl(p.bookId, res),
        cover: b.cover || b.cover2 || null, banner: b.bannerUrl || null,
        description: htmlText(b.introduction || ''),
        status: 'unknown', genres: genres, studios: [], type: 'movie',
        sourceId: SOURCE_ID, episodes: eps
      };
    });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return (d && d.episodes) || []; });
}

// ── streams ─────────────────────────────────────────────────────────────────
// episodeUrl is `gs:<bookId>|<resourceUrl>|<chapterId>`. The chapter's m3u8 is
// fetched directly (it is signed and time-limited, so it is never cached).
function getVideoSources(episodeUrl) {
  var s = String(episodeUrl || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  var bookId = parts[0], chapterId = parts[2];
  if (!bookId || !chapterId) return Promise.resolve([]);
  return _post('/hwycreels/chapter/detail', {
    bookId: bookId, chapterId: chapterId, language: LANG, num: 16
  }).then(function (j) {
    var d = j.data || {};
    var c = d.chapterVo || d.chapter || d;
    var video = (c && c.m3u8Path) || null;
    if (!video) return [];
    return [{
      url: video,
      quality: null,
      label: c.chapterName ? ('Episode ' + c.chapterName) : null,
      container: _container(video),
      headers: { 'User-Agent': UA, 'Referer': SITE + '/' },
      kind: 'unknown',
      subtitles: []
    }];
  }).catch(function () { return []; });
}

function _container(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0) return 'hls';
  if (u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}
