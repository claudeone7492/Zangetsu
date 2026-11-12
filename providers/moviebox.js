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

function _headers(slug, extra) {
  var h = {
    'User-Agent': UA,
    'Accept': 'application/json, text/plain, */*',
    'Referer': _referer(slug),
    'Origin': PLAYER,
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
// every endpoint here is idempotent.
function _request(method, path, slug, body, retried) {
  return _ensureToken().then(function () {
    var h = _headers(slug, body != null ? { 'Content-Type': 'application/json' } : null);
    if (_token) h['Authorization'] = 'Bearer ' + _token;
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
      if (!retried && /token/i.test(msg)) {
        _token = null;
        return _request(method, path, slug, body, true);
      }
      throw new Error('MovieBox: ' + msg);
    }
    return (j && j.data) || {};
  });
}

function _get(path, slug) { return _request('GET', path, slug, null, false); }
function _post(path, slug, body) { return _request('POST', path, slug, body, false); }

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

function _mapSubject(s) {
  if (!s || s.subjectId == null) return null;
  var type = s.subjectType;
  if (type != null && !MOVIE_TYPES[type]) return null;
  var slug = s.detailPath || '';
  return {
    id: String(s.subjectId),
    title: s.title || String(s.subjectId),
    cover: _cover(s.cover),
    banner: null,
    url: _showUrl(s.subjectId, slug, type),
    type: 'movie',
    sourceId: SOURCE_ID
  };
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
// BANNER rail (art, not a poster row) and non-subject rails we skip.
function _home() { return _get(HOME_PATH, null); }

function getHome(opts) {
  return _home().then(function (d) {
    var ops = d.operatingList || [];
    var out = [];
    for (var i = 0; i < ops.length; i++) {
      var o = ops[i];
      if (!o || !o.title) continue;
      var items = _mapSubjects(o.subjects);
      if (items.length) out.push({ title: o.title, items: items });
    }
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
