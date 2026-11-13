// MovieBox provider — https://themoviebox.xyz (player: https://mzfi.me)
//
// MovieBox is an aggregator for movies, series and short dramas (vertical
// one-to-three-minute episodes). The site is a Nuxt SPA that talks to a public
// JSON API on h5-api.aoneroom.com; the player itself lives in an iframe at
// mzfi.me/spa/videoPlayPage/…, which is what themoviebox.xyz embeds. This
// provider speaks to that API directly — no scraping, no keys.
//
//   GET  /wefeed-h5api-bff/home?host=<host>            → catalogue rails
//   POST /wefeed-h5api-bff/subject/search              → search (needs a token)
//   GET  /wefeed-h5api-bff/detail?detailPath=<slug>    → metadata + seasons
//   GET  /wefeed-h5api-bff/subject/play?subjectId=&se=&ep=&detailPath=…
//                                                       → direct MP4/HLS/DASH
//
// Two things gate the play endpoint, both confirmed live:
//   * the request needs the PLAYER-PATH referer
//     (`…/spa/videoPlayPage/movies/<slug>…`); a bare origin referer or none
//     returns an empty `streams` array with `hasResource:false`;
//   * the API mints an anonymous guest token on every response (the `x-user`
//     header, mirrored as the `token` cookie). That token is sent as a Bearer
//     header on later calls — search requires it outright.
//
// Short dramas and series use season 1, episode 1..N; a movie is a single
// entry addressed as season 0, episode 0. The play endpoint soft-throttles
// bursts (it answers 200 with an empty list rather than 429), so resolution
// retries a few times with backoff.
//
// URLs carry what the next call needs: a show is `mb:<subjectId>|<slug>|<type>`
// and an episode is `mb:<subjectId>|<slug>|<type>|<se>|<ep>`. Verified live.

var SOURCE_ID = 'moviebox';
var SITE = 'https://themoviebox.xyz';
var API = 'https://h5-api.aoneroom.com';
var PLAYER = 'https://mzfi.me';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

// Subject types we surface as movie-mode entries. Everything else (person,
// live channel, …) is skipped.
var MOVIE_TYPES = { 1: 1, 2: 1, 7: 1 };

function getInfo() {
  return {
    name: 'MovieBox', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// ── HTTP ────────────────────────────────────────────────────────────────────
// The API's edge check reads the Referer; the bare origin is not enough, so a
// player-path referer is always sent (a real slug when we have one, a neutral
// path otherwise — every path under /spa/videoPlayPage/ is accepted).
function _referer(slug) {
  if (slug) {
    return PLAYER + '/spa/videoPlayPage/movies/' + slug + '?type=%2Fmovie%2Fdetail';
  }
  return PLAYER + '/spa/videoPlayPage/movies/detail';
}

// The sports endpoints live on the same API host but belong to a different
// front end (sportsnow.top); they expect its own referer/origin.
var SPORTS = 'https://sportsnow.top';

function _headers(slug, extra, referer, origin) {
  var h = {
    'User-Agent': UA,
    'Accept': 'application/json, text/plain, */*',
    'Referer': referer || _referer(slug),
    'Origin': origin || PLAYER,
    'X-Client-Info': '{"timezone":"UTC"}'
  };
  if (extra) { for (var k in extra) { if (extra.hasOwnProperty(k)) h[k] = extra[k]; } }
  return h;
}

// Anonymous guest token minted by the API on any response (`x-user` header,
// mirrored as the `token` cookie). Cached for the runtime session; re-minted
// on demand when a call comes back token-less.
var _token = null;

function _captureToken(r) {
  var h = (r && r.headers) || {};
  var xuser = h['x-user'] || h['X-User'];
  if (xuser) {
    try {
      var j = JSON.parse(xuser);
      if (j && j.token) { _token = j.token; return _token; }
    } catch (e) { /* fall through to the cookie */ }
  }
  var sc = h['set-cookie'] || h['Set-Cookie'];
  if (sc) {
    var m = String(sc).match(/token=([^;,\s]+)/);
    if (m) { _token = m[1]; return _token; }
  }
  return null;
}

var HOME_PATH = '/wefeed-h5api-bff/home?host=' + encodeURIComponent(SITE.replace('https://', ''));

function _ensureToken() {
  if (_token) return Promise.resolve(_token);
  return fetch(API + HOME_PATH, { headers: _headers(null) })
    .then(function (r) { return _captureToken(r) || _token; })
    .catch(function () { return _token; });
}

// One request, with a single re-mint-and-retry when the API rejects the token
// (it answers 400 "invalid token" rather than 401). A retry is safe because
// every endpoint here is idempotent. [ref]/[org] override the referer/origin
// for the sports endpoints, which want sportsnow.top's.
function _request(method, path, slug, body, retried, ref, org, noAuth) {
  return _ensureToken().then(function () {
    var h = _headers(slug, body != null ? { 'Content-Type': 'application/json' } : null, ref, org);
    if (_token && !noAuth) h['Authorization'] = 'Bearer ' + _token;
    return fetch(API + path, {
      method: method, headers: h,
      body: body != null ? JSON.stringify(body) : undefined
    });
  }).then(function (r) {
    _captureToken(r);
    if (!r.ok) throw new Error('MovieBox: HTTP ' + r.status);
    var j;
    try { j = JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('MovieBox: bad JSON'); }
    if (j && j.code && j.code !== 0) {
      var msg = String(j.message || ('code ' + j.code));
      if (!retried && !noAuth && /token/i.test(msg)) {
        _token = null;
        return _request(method, path, slug, body, true, ref, org, noAuth);
      }
      throw new Error('MovieBox: ' + msg);
    }
    return (j && j.data) || {};
  });
}

function _get(path, slug) { return _request('GET', path, slug, null, false); }
function _post(path, slug, body) { return _request('POST', path, slug, body, false); }
// The sports endpoints sit behind the same host but reject the catalogue's
// guest token ("Fail to parse JWT token"), so they go out anonymous with
// sportsnow.top's own referer/origin.
function _sportGet(path) {
  return _request('GET', path, null, null, false, SPORTS + '/', SPORTS, true);
}

// ── mapping ─────────────────────────────────────────────────────────────────
function _showUrl(subjectId, slug, type) {
  return 'mb:' + subjectId + '|' + (slug || '') + '|' + (type == null ? '' : type);
}
function _episodeUrl(subjectId, slug, type, se, ep) {
  return _showUrl(subjectId, slug, type) + '|' + se + '|' + ep;
}

function _cover(cover) {
  if (!cover) return null;
  if (typeof cover === 'string') return cover;
  return cover.url || null;
}

// Genres arrive as a comma-joined string ("Horror,Thriller"); drop blanks.
function _genres(s) {
  var raw = (s && s.genre) || '';
  var parts = String(raw).split(',');
  var out = [];
  for (var i = 0; i < parts.length; i++) {
    var g = _trim(parts[i]);
    if (g.length) out.push(g);
  }
  return out;
}

// The API reports an IMDb score as a string ("7.7"). MediaItem.score is 0-100,
// so it scales by 10; anything unparseable stays null rather than becoming 0.
function _score(s) {
  var v = parseFloat((s && s.imdbRatingValue) || '');
  if (!isFinite(v) || v <= 0) return null;
  return Math.round(v * 10);
}

function _year(s) {
  var d = (s && s.releaseDate) || '';
  return d ? String(d).slice(0, 4) : null;
}

function _mapSubject(s) {
  if (!s || s.subjectId == null) return null;
  var type = s.subjectType;
  if (type != null && !MOVIE_TYPES[type]) return null;
  var slug = s.detailPath || '';
  var item = {
    id: String(s.subjectId),
    title: s.title || String(s.subjectId),
    cover: _cover(s.cover),
    banner: null,
    url: _showUrl(s.subjectId, slug, type),
    type: 'movie',
    sourceId: SOURCE_ID
  };
  var genres = _genres(s);
  if (genres.length) item.genres = genres;
  var score = _score(s);
  if (score != null) item.score = score;
  return item;
}

function _mapSubjects(list) {
  var out = [];
  if (!list || !list.length) return out;
  for (var i = 0; i < list.length; i++) {
    var m = _mapSubject(list[i]);
    if (m) out.push(m);
  }
  return out;
}

// ── home / browse ───────────────────────────────────────────────────────────
// The home payload carries `operatingList`: named rails of subjects plus a
// BANNER rail (art, not a poster row), a FILTER rail (its `filters` are
// hand-picked browse shortcuts, each with an image) and a SPORT_LIVE rail
// (football/cricket/etc. — see getLive). All three become ordinary rows; a
// browse row's items carry a `browse:<kind>|<categoryId>` url so tapping a
// card opens the matching listing instead of a detail page.
function _home() { return _get(HOME_PATH, null); }

// A browse shortcut URL the app routes back through browseFilter (see the
// Dart side): kind `platform` lists a streaming service, `filter` applies a
// tabId + filterType query.
function _browseUrl(kind, categoryId) {
  return 'browse:' + kind + '|' + (categoryId == null ? '' : categoryId);
}

function _mapBrowse(entry, kind) {
  if (!entry) return null;
  var title = entry.title || entry.name || '';
  if (!title) return null;
  var categoryId = (kind === 'platform') ? (entry.name || entry.title) : (entry.query || '');
  if (!categoryId) return null;
  var item = {
    id: 'browse:' + kind + ':' + categoryId,
    title: title,
    cover: _cover(entry.image),
    banner: null,
    url: _browseUrl(kind, categoryId),
    type: 'movie',
    sourceId: SOURCE_ID
  };
  return item;
}

function _platformRails(d) {
  var plats = d.platformList || [];
  var out = [];
  for (var i = 0; i < plats.length; i++) {
    var m = _mapBrowse(plats[i], 'platform');
    if (m) out.push(m);
  }
  return out;
}

function _mapBrowseAll(entries, kind) {
  var out = [];
  for (var i = 0; i < entries.length; i++) {
    var m = _mapBrowse(entries[i], kind);
    if (m) out.push(m);
  }
  return out;
}

function _filterRail(d) {
  var ops = d.operatingList || [];
  for (var i = 0; i < ops.length; i++) {
    var o = ops[i];
    if (o && o.type === 'FILTER' && o.filters && o.filters.length) {
      var items = _mapBrowseAll(o.filters, 'filter');
      if (items.length) return { title: o.title || 'Browse', items: items };
    }
  }
  return null;
}

// Home rows: the catalogue's own subject rails, then a "Browse" rail built
// from the FILTER shortcuts, then one rail per streaming platform. A rail that
// comes back empty is dropped rather than shown as a blank row.
function getHome(opts) {
  return _home().then(function (d) {
    var ops = d.operatingList || [];
    var out = [];
    // Live matches lead the page — they are the one row that is only useful
    // while it is current.
    var live = _homeLive(d);
    if (live) out.push(live);
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i];
      if (!o || !o.title || o.type === 'FILTER' || o.type === 'SPORT_LIVE') continue;
      var items = _mapSubjects(o.subjects);
      if (items.length) out.push({ title: o.title, items: items });
    }
    var filterRail = _filterRail(d);
    if (filterRail && filterRail.items.length) out.push(filterRail);
    var platforms = _platformRails(d);
    if (platforms.length) out.push({ title: 'By Platform', items: platforms });
    return out;
  }).catch(function () { return []; });
}

function popular(opts) {
  return _home().then(function (d) {
    var ops = d.operatingList || [];
    for (var i = 0; i < ops.length; i++) {
      var items = _mapSubjects(ops[i] && ops[i].subjects);
      if (items.length) return items;
    }
    return [];
  }).catch(function () { return []; });
}

// ── search ──────────────────────────────────────────────────────────────────
function search(query, page, opts) {
  var q = String(query || '').trim();
  if (!q) return Promise.resolve([]);
  var p = page || 1;
  return _post('/wefeed-h5api-bff/subject/search', null, {
    keyword: q, page: p, perPage: 20
  }).then(function (d) {
    return _mapSubjects(d.items);
  }).catch(function () { return []; });
}

// ── detail / episodes ───────────────────────────────────────────────────────
function _parseShow(url) {
  var s = String(url || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  var type = parts[2] === '' ? null : parts[2];
  return {
    subjectId: parts[0], slug: parts[1],
    type: type == null ? null : parseInt(type, 10),
    se: parts[3], ep: parts[4]
  };
}

// Build the episode list from the resource block. Series/short-dramas carry one
// or more seasons with a maxEp count; a movie is a single season 0 / episode 0.
function _episodes(p, res, title) {
  var seasons = (res && res.seasons) || [];
  var eps = [];
  for (var i = 0; i < seasons.length; i++) {
    var s = seasons[i] || {};
    var se = (s.se == null) ? 0 : s.se;
    var maxEp = s.maxEp || 0;
    var allEp = String(s.allEp || '');
    var list = allEp ? allEp.split(',') : [];
    var nums = [];
    for (var k = 0; k < list.length; k++) {
      var n = parseInt(list[k], 10);
      if (n > 0) nums.push(n);
    }
    if (!nums.length) {
      // A movie (or a season with no explicit list) has no episode numbers;
      // address it as se=0&ep=0, which is what the play endpoint expects.
      if (maxEp <= 1 && se === 0) {
        nums = [0];
      } else {
        for (var e = 1; e <= maxEp; e++) nums.push(e);
      }
    }
    for (var j = 0; j < nums.length; j++) {
      var ep = nums[j];
      var label = (maxEp <= 1 && se === 0)
        ? (title || 'Movie')
        : (se > 1 ? ('S' + se + ' E' + ep) : ('Episode ' + ep));
      eps.push({
        id: String(se) + '-' + String(ep),
        title: label,
        number: eps.length + 1,
        url: _episodeUrl(p.subjectId, p.slug, p.type, se, ep)
      });
    }
  }
  if (!eps.length) {
    eps.push({
      id: '0-0', title: title || 'Movie', number: 1,
      url: _episodeUrl(p.subjectId, p.slug, p.type, 0, 0)
    });
  }
  return eps;
}

function _detail(showUrl) {
  var p = _parseShow(showUrl);
  if (!p.subjectId || !p.slug) return Promise.resolve(null);
  return _get('/wefeed-h5api-bff/detail?detailPath=' + encodeURIComponent(p.slug), p.slug)
    .then(function (d) {
      var s = d.subject || {};
      var res = d.resource || {};
      var type = (s.subjectType != null) ? s.subjectType : p.type;
      var slug = s.detailPath || p.slug;
      var title = s.title || p.subjectId;
      var genres = String(s.genre || '').split(',').map(_trim).filter(function (g) { return g.length > 0; });
      var studios = [];
      var staff = s.staffList || [];
      for (var i = 0; i < staff.length; i++) {
        if (staff[i] && staff[i].name) studios.push(staff[i].name);
      }
      var cast = [];
      var banner = null;
      var stills = s.stills || [];
      if (stills.length && stills[0]) banner = _cover(stills[0]);

      var detail = {
        id: String(s.subjectId || p.subjectId),
        title: title,
        url: _showUrl(s.subjectId || p.subjectId, slug, type),
        cover: _cover(s.cover), banner: banner,
        description: htmlText(s.description || ''),
        status: 'unknown', genres: genres, studios: studios, cast: cast,
        type: 'movie', sourceId: SOURCE_ID,
        episodes: _episodes({ subjectId: String(s.subjectId || p.subjectId), slug: slug, type: type }, res, title)
      };
      if (s.releaseDate) detail.year = String(s.releaseDate).slice(0, 4);
      // Metadata enrichment — only set what the API actually reports, so an
      // absent field stays absent rather than becoming a placeholder.
      var alt = s.alternativeTitle || s.originalTitle;
      if (alt && alt !== title) detail.englishTitle = alt;
      var score = _score(s);
      if (score != null) detail.score = score;
      if (s.countryName) detail.country = s.countryName;
      if (s.duration) detail.durationMins = Math.max(1, Math.round(s.duration / 60));
      return detail;
    });
}

function getDetail(url, opts) { return _detail(url); }

function getEpisodes(url, opts) {
  return _detail(url).then(function (d) { return (d && d.episodes) || []; });
}

// ── streams ─────────────────────────────────────────────────────────────────
// episodeUrl is `mb:<subjectId>|<slug>|<type>|<se>|<ep>`. The play endpoint
// soft-throttles bursts, so an empty result is retried with backoff before it
// is treated as "no source".
function _container(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0 || u.indexOf('m3u8') >= 0) return 'hls';
  if (u.indexOf('.mpd') >= 0) return 'dash';
  if (u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}

function _play(p, attempt) {
  var path = '/wefeed-h5api-bff/subject/play?subjectId=' + encodeURIComponent(p.subjectId) +
    '&se=' + encodeURIComponent(p.se) + '&ep=' + encodeURIComponent(p.ep) +
    '&detailPath=' + encodeURIComponent(p.slug) + '&streamSignType=1';
  return _get(path, p.slug).then(function (d) {
    var streams = (d.streams || []).concat(d.hls || []).concat(d.dash || []);
    if (!streams.length && attempt < 4) {
      return _delay(900 * (attempt + 1)).then(function () { return _play(p, attempt + 1); });
    }
    return streams;
  });
}

// setTimeout is provided by the runtime (and the node harness); fall back to an
// immediate resolve so a missing timer never breaks resolution outright.
function _delay(ms) {
  return new Promise(function (resolve) {
    if (typeof setTimeout === 'function') setTimeout(resolve, ms);
    else resolve();
  });
}

function getVideoSources(episodeUrl) {
  if (String(episodeUrl || '').indexOf('live:') === 0) {
    return getVideoSourcesLive(episodeUrl);
  }
  var p = _parseShow(episodeUrl);
  if (!p.subjectId || !p.slug || p.se == null || p.ep == null) return Promise.resolve([]);
  return _play(p, 0).then(function (streams) {
    var out = [];
    var playHeaders = { 'User-Agent': UA, 'Referer': PLAYER + '/', 'Origin': PLAYER };
    for (var i = 0; i < streams.length; i++) {
      var s = streams[i];
      if (!s || !s.url) continue;
      var res = s.resolutions || s.resolution || '';
      out.push({
        url: s.url,
        quality: res ? (String(res) + 'p') : null,
        label: res ? (String(res) + 'p') : null,
        container: _container(s.url),
        headers: playHeaders,
        kind: 'unknown',
        subtitles: []
      });
    }
    return out;
  }).catch(function () { return []; });
}

function _trim(s) { return String(s).replace(/^\s+|\s+$/g, ''); }

// ── browse listings (platform + filter shortcuts) ───────────────────────────
// The "Browse" / "By Platform" home rows hand back `browse:<kind>|<categoryId>`
// items; this resolves one to a page of subjects. `platform` lists everything
// a streaming service carries; `filter` runs a tabId + filterType query.
function browseFilter(categoryId, page) {
  var spec = String(categoryId || '');
  // Accept either the app's `browse:<spec>` handle or the bare spec, so a
  // caller can pass a home-row url through unchanged.
  if (spec.indexOf('browse:') === 0) spec = spec.slice('browse:'.length);
  // A raw selection from the app's filter sheet (a JSON array) is converted to
  // the same `filter|…` spec, so callers only ever pass one shape.
  if (spec.charAt(0) === '[') spec = _filtersToSpec(spec) || '';
  var bar = spec.indexOf('|');
  var kind = bar >= 0 ? spec.slice(0, bar) : spec;
  var arg = bar >= 0 ? spec.slice(bar + 1) : '';
  var p = page || 1;
  if (kind === 'platform') {
    // perPage is capped at 6 server-side ("perPage too large"); the response is
    // a monthList of that many months × perPage subjects, so one page already
    // yields ~36 titles.
    return _get('/wefeed-h5api-bff/platform/play-list?page=' + p + '&perPage=6&platform=' +
      encodeURIComponent(arg), null).then(function (d) {
      var out = [];
      var months = d.monthList || [];
      for (var i = 0; i < months.length; i++) {
        out = out.concat(_mapSubjects((months[i] || {}).subjects));
      }
      if (!out.length) out = _mapSubjects(d.subjects);
      return out;
    }).catch(function () { return []; });
  }
  if (kind === 'filter') {
    var parsed = _parseFilterQuery(arg);
    // The endpoint reads each facet as a top-level body field; a nested
    // `filterType` object is ignored and the response falls back to an
    // unrelated unfiltered feed. Verified live: flat `genre=Anime` returns
    // anime, nested returns pop-music mixes.
    var body = {
      tabId: parsed.tabId, page: p, perPage: 20,
      classify: parsed.filter.classify, country: parsed.filter.country,
      genre: parsed.filter.genre, sort: parsed.filter.sort,
      year: parsed.filter.year
    };
    return _post('/wefeed-h5api-bff/subject/filter', null, body)
      .then(function (d) {
        return _mapSubjects(d.items);
      }).catch(function () { return []; });
  }
  return Promise.resolve([]);
}

// The FILTER rail's `query` is `type=/home/movieFilter&tabId=<n>&filterType=<json>`;
// pull out the tabId and the facet map the /subject/filter POST needs.
function _parseFilterQuery(q) {
  var s = String(q || '');
  var tabId = 2;
  var mt = s.match(/tabId=(\d+)/);
  if (mt) tabId = parseInt(mt[1], 10);
  var filter = { classify: 'All', country: 'All', genre: 'All', sort: 'Latest', year: 'All' };
  var mf = s.match(/filterType=([^&]+)/);
  if (mf) {
    try {
      var j = JSON.parse(decodeURIComponent(mf[1]));
      if (j && typeof j === 'object') {
        for (var k in filter) {
          if (j[k] != null && j[k] !== '') filter[k] = j[k];
        }
      }
    } catch (e) { /* keep the default filter */ }
  }
  return { tabId: tabId, filter: filter };
}

// A generic filter schema the app renders as a sheet (Mangayomi-shaped). The
// country/genre/year lists mirror the values the site's own filter page sends;
// anything outside them matches nothing server-side. Sort uses the API's own
// values, which differ from the labels ("ForYou" is the default feed).
function getFilters() {
  var countries = [
    ['All', 'All'], ['United States', 'United States'], ['India', 'India'],
    ['United Kingdom', 'United Kingdom'], ['Korea', 'Korea'],
    ['Japan', 'Japan'], ['China', 'China'], ['Turkey', 'Turkey']
  ];
  var genres = [
    ['All', 'All'], ['Action', 'Action'], ['Adventure', 'Adventure'],
    ['Animation', 'Animation'], ['Anime', 'Anime'], ['Biography', 'Biography'],
    ['Comedy', 'Comedy'], ['Crime', 'Crime'], ['Drama', 'Drama'],
    ['Family', 'Family'], ['Fantasy', 'Fantasy'], ['History', 'History'],
    ['Horror', 'Horror'], ['Music', 'Music'], ['Mystery', 'Mystery'],
    ['Romance', 'Romance'], ['Sci-Fi', 'Sci-Fi'], ['Short', 'Short'],
    ['Sport', 'Sport'], ['Thriller', 'Thriller'], ['War', 'War'],
    ['Western', 'Western']
  ];
  var years = [['All', 'All']];
  for (var y = 2026; y >= 1990; y--) years.push([String(y), String(y)]);
  // Pairs are [apiValue, label]: the sheet shows the label and sends the value.
  var sorts = [['ForYou', 'For You'], ['Latest', 'Latest'], ['Rating', 'Rating']];
  var sel = function (name, pairs) {
    return {
      name: name, type_name: 'SelectFilter',
      values: pairs.map(function (p) { return { name: p[1], value: p[0] }; }),
      state: 0
    };
  };
  return [sel('Country', countries), sel('Genre', genres), sel('Year', years), sel('Sort', sorts)];
}

// Turn a filter-sheet selection (a JSON array of {name,values,state}) into the
// `filter|<query>` spec browseFilter parses. Country/Genre/Sort/Year come from
// the sheet; `classify` (the dub track) is not offered there, so it stays All.
function _filtersToSpec(filters) {
  var list = filters;
  if (typeof filters === 'string') {
    try { list = JSON.parse(filters); } catch (e) { return null; }
  }
  if (!list || !list.length) return null;
  var pick = function (name, def) {
    for (var i = 0; i < list.length; i++) {
      var f = list[i];
      if (f && f.name === name && f.values && f.state != null) {
        var v = f.values[f.state];
        if (v && v.value != null) return v.value;
      }
    }
    return def;
  };
  var ft = {
    classify: 'All', country: pick('Country', 'All'), genre: pick('Genre', 'All'),
    sort: pick('Sort', 'Latest'), year: pick('Year', 'All')
  };
  return 'filter|type=/home/movieFilter&tabId=2&filterType=' + JSON.stringify(ft);
}

// ── live sports ─────────────────────────────────────────────────────────────
// Matches carry a direct `playPath` m3u8 (some are still pre-match with none).
// The url packs the id and the path so getVideoSources can hand the player the
// live stream without another lookup.
function _mapMatch(m) {
  if (!m) return null;
  var t1 = m.team1 || {};
  var t2 = m.team2 || {};
  var n1 = t1.name || '?';
  var n2 = t2.name || '?';
  var s1 = t1.score, s2 = t2.score;
  var title = (s1 !== undefined && s1 !== '' && s2 !== undefined && s2 !== '')
    ? (n1 + ' ' + s1 + ' - ' + s2 + ' ' + n2)
    : (n1 + ' vs ' + n2);
  var live = m.statusLive === 'Living';
  if (live) title = '\u25CF ' + title;
  var id = String(m.id || m.matchId || '');
  var path = m.playPath || '';
  var item = {
    id: id,
    title: title,
    cover: (t1.avatar || t2.avatar || null),
    banner: null,
    url: 'live:' + id + '|' + path,
    type: 'movie',
    sourceId: SOURCE_ID
  };
  if (m.league) item.genres = [m.league];
  return item;
}

function _mapMatches(list) {
  var out = [];
  if (!list) return out;
  for (var i = 0; i < list.length; i++) {
    var m = _mapMatch(list[i]);
    if (m) out.push(m);
  }
  return out;
}

// A live rail taken straight from the home payload's SPORT_LIVE block (no
// extra call), so it rides along with getHome.
function _homeLive(d) {
  var ops = d.operatingList || [];
  for (var i = 0; i < ops.length; i++) {
    var o = ops[i];
    if (o && o.type === 'SPORT_LIVE' && o.liveList && o.liveList.length) {
      var items = _mapMatches(o.liveList);
      if (items.length) return { title: o.title || 'Live', items: items };
    }
  }
  return null;
}

// Live matches from the sports endpoint — the fuller, fresher list. Optional
// (getLive); the app may also just render the home rail.
function getLive(opts) {
  return _sportGet('/wefeed-h5api-bff/live/match-list-v5?timezone=UTC&system_language=en')
    .then(function (d) { return _mapMatches(d.list); })
    .catch(function () { return []; });
}

// Short dramas — the vertical feed's dedicated extension. MovieBox's short
// dramas are the `subjectType: 7` subjects; a general `getHome` buries their
// two rails among two dozen movie/TV rails, so a feed built from every home
// row leads with Popular Series and only reaches the shorts 400 items later.
// This returns ONLY the short-drama subjects, rail order preserved and
// de-duplicated, so the feed is shorts from the first swipe.
function getShorts(opts) {
  return _home().then(function (d) {
    var ops = d.operatingList || [];
    var out = [];
    var seen = {};
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i];
      if (!o || !o.subjects || !o.subjects.length) continue;
      for (var j = 0; j < o.subjects.length; j++) {
        var s = o.subjects[j];
        if (!s || s.subjectType !== 7) continue;
        var m = _mapSubject(s);
        if (m && !seen[m.id]) { seen[m.id] = 1; out.push(m); }
      }
    }
    return out;
  }).catch(function () { return []; });
}

function getVideoSourcesLive(url) {
  var spec = String(url || '').slice('live:'.length);
  var bar = spec.indexOf('|');
  var path = bar >= 0 ? spec.slice(bar + 1) : '';
  if (!path) return Promise.resolve([]);
  return Promise.resolve([{
    url: path,
    quality: 'Live',
    label: 'Live',
    container: _container(path),
    headers: { 'User-Agent': UA, 'Referer': SPORTS + '/', 'Origin': SPORTS },
    kind: 'unknown',
    subtitles: []
  }]);
}
