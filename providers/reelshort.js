// ReelShort provider — https://www.reelshort.com
//
// ReelShort is a short-drama service: a "show" is a book with ~40–80
// one-to-three-minute vertical episodes. There is no public API, but the
// Next.js site ships its own page data as JSON under /_next/data/<buildId>/…,
// which is exactly what the browser fetches when it renders a page. That is
// what this provider reads: no scraping of HTML, no auth, no keys.
//
// The build id changes on every deploy, so it is discovered from the homepage
// once per session and reused. The three JSON documents that matter:
//   /en.json                                   → home shelves (bookShelfList)
//   /en/search.json?keywords=…                 → search results (books)
//   /en/movie/<slug>-<book_id>.json            → detail + online_base episodes
//   /en/episodes/episode-<n>-…-<chapter_id>.json → one episode's video_url (HLS)
//
// URLs carry what the next call needs: a show is `rs:<book_id>|<slug>` and an
// episode is `rs:<book_id>|<slug>|<serial>|<chapter_id>`. Verified live.

var SOURCE_ID = 'reelshort';
var SITE = 'https://www.reelshort.com';
var LANG = 'en';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function _headers() {
  return {
    'User-Agent': UA,
    'Accept': 'application/json, text/plain, */*',
    'Referer': SITE + '/',
    'Origin': SITE
  };
}

function _get(url) {
  return fetch(url, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('ReelShort: HTTP ' + r.status);
    var ct = (r.headers && (r.headers['content-type'] || r.headers['Content-Type'])) || '';
    if (ct && ct.indexOf('json') < 0) {
      // A stale build id answers with the HTML shell instead of JSON; that is
      // the one failure worth surfacing as a typed error so _json() can retry.
      throw new Error('ReelShort: not json (build id may be stale)');
    }
    try { return JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('ReelShort: bad JSON'); }
  });
}

function getInfo() {
  return {
    name: 'ReelShort', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// ── build id + page data ────────────────────────────────────────────────────
var _buildId = null;

function _discoverBuildId() {
  return fetch(SITE + '/', { headers: _headers() }).then(function (r) {
    var m = String(r.body || '').match(/"buildId":"([^"]+)"/);
    if (!m) throw new Error('ReelShort: build id not found');
    _buildId = m[1];
    return _buildId;
  });
}

// `pathAndQuery` already carries the locale prefix (`en.json`, `en/search.json`),
// matching the URL shape the site itself requests.
function _data(pathAndQuery) {
  function once(bid) {
    return _get(SITE + '/_next/data/' + bid + '/' + pathAndQuery)
      .then(function (j) { return (j && j.pageProps) || {}; });
  }
  if (_buildId) return once(_buildId);
  return _discoverBuildId().then(once);
}

// A JSON call that re-discovers the build id once when it comes back stale.
function _dataRetry(pathAndQuery) {
  return _data(pathAndQuery).catch(function () {
    _buildId = null;
    return _discoverBuildId().then(function () { return _data(pathAndQuery); });
  });
}

// ── mapping ─────────────────────────────────────────────────────────────────
function _filterTitle(title) {
  var t = String(title || '').toLowerCase();
  t = t.replace(/[^a-z0-9]+/g, ' ');
  t = t.replace(/\s+/g, ' ').replace(/^\s+|\s+$/g, '');
  return t.replace(/ /g, '-');
}

function _showUrl(bookId, slug) { return 'rs:' + bookId + '|' + slug; }

function _mapBook(b) {
  if (!b || !b.book_id) return null;
  var slug = _filterTitle(b.book_title);
  return {
    id: String(b.book_id),
    title: b.book_title || String(b.book_id),
    cover: b.book_pic || b.default_pic || null,
    banner: null,
    url: _showUrl(b.book_id, slug),
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
function _homeInfo() {
  return _dataRetry(LANG + '.json').then(function (pp) {
    var fb = (pp && pp.fallback) || {};
    var wi = fb['/api/ms/hall/webInfo'] || {};
    return (wi.bookShelfList || []).filter(function (s) {
      return s && s.bookshelf_name && s.books && s.books.length;
    });
  });
}

function getHome(opts) {
  return _homeInfo().then(function (shelves) {
    var out = [];
    for (var i = 0; i < shelves.length; i++) {
      var s = shelves[i];
      var items = _mapBooks(s.books);
      if (items.length) out.push({ title: s.bookshelf_name, items: items });
    }
    return out;
  }).catch(function () { return []; });
}

function popular(opts) {
  return _homeInfo().then(function (shelves) {
    var pick = shelves[0] || {};
    return _mapBooks(pick.books);
  }).catch(function () { return []; });
}

// ── shorts feed ─────────────────────────────────────────────────────────────
// Every ReelShort book is a short drama, so the home shelves are the feed.
// ReelTalk is a podcast shelf (its books carry a `Podcast` theme), not a
// drama, so it is skipped. Shelves overlap heavily, so de-duplicate by id.
function _isPodcast(b) {
  var themes = (b && b.theme) || [];
  for (var i = 0; i < themes.length; i++) {
    if (String(themes[i]).toLowerCase() === 'podcast') return true;
  }
  return false;
}

function getShorts(opts) {
  return _homeInfo().then(function (shelves) {
    var out = [], seen = {};
    for (var i = 0; i < shelves.length; i++) {
      var books = shelves[i].books || [];
      for (var j = 0; j < books.length; j++) {
        var b = books[j];
        if (!b || _isPodcast(b)) continue;
        var m = _mapBook(b);
        if (m && !seen[m.id]) { seen[m.id] = 1; out.push(m); }
      }
    }
    return out;
  }).catch(function () { return []; });
}

// ── search ──────────────────────────────────────────────────────────────────
function search(query, page, opts) {
  var q = String(query || '');
  if (!q) return Promise.resolve([]);
  var p = page || 1;
  // `page=1` is rejected by the site (an empty page); only page 2+ may be sent.
  var path = LANG + '/search.json?keywords=' + encodeURIComponent(q) +
             (p > 1 ? '&page=' + p : '');
  return _dataRetry(path).then(function (pp) {
    return _mapBooks(pp.books || []);
  }).catch(function () { return []; });
}

// ── detail / episodes ───────────────────────────────────────────────────────
function _parseShow(url) {
  var s = String(url || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  return { bookId: parts[0], slug: parts[1] };
}

function getDetail(url, opts) {
  var p = _parseShow(url);
  var movie = p.slug + '-' + p.bookId;
  return _dataRetry(LANG + '/movie/' + movie + '.json?slug=' + movie)
    .then(function (pp) {
      var d = (pp && pp.data) || {};
      var slug = p.slug || _filterTitle(d.book_title);
      var base = d.online_base || [];
      var eps = [];
      for (var i = 0; i < base.length; i++) {
        var e = base[i];
        var n = e.serial_number != null ? e.serial_number : (i + 1);
        eps.push({
          id: String(e.chapter_id),
          title: 'Episode ' + n,
          number: n,
          url: _showUrl(p.bookId, slug) + '|' + n + '|' + e.chapter_id,
          thumbnail: e.video_pic || null
        });
      }
      var genres = [];
      var tags = d.tag_list || [];
      for (var k = 0; k < tags.length; k++) {
        if (tags[k] && tags[k].text) genres.push(tags[k].text);
      }
      return {
        id: String(p.bookId), title: d.book_title || String(p.bookId),
        url: _showUrl(p.bookId, slug),
        cover: d.book_pic || null, banner: null,
        description: htmlText(d.special_desc || ''),
        status: 'unknown', genres: genres, studios: [], type: 'movie',
        sourceId: SOURCE_ID, episodes: eps
      };
    });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d.episodes; });
}

// ── streams ─────────────────────────────────────────────────────────────────
// episodeUrl is `rs:<book_id>|<slug>|<serial>|<chapter_id>`.
function getVideoSources(episodeUrl) {
  var s = String(episodeUrl || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  var bookId = parts[0], slug = parts[1], serial = parts[2], chapterId = parts[3];
  if (!bookId || !slug || !serial || !chapterId) return Promise.resolve([]);
  var ep = 'episode-' + serial + '-' + slug + '-' + bookId + '-' + chapterId;
  var path = LANG + '/episodes/' + ep + '.json?play_time=1&slug=' + ep;
  return _dataRetry(path).then(function (pp) {
    var d = (pp && pp.data) || {};
    var video = d.video_url;
    if (!video) return [];
    return [{
      url: video,
      quality: null,
      label: d.book_title ? (d.book_title + ' · Ep ' + serial) : ('Episode ' + serial),
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
