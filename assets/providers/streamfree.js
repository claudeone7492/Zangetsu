// StreamFree provider — live sports fixtures (soccer, basketball, hockey,
// combat, baseball, American football, racing, tennis, cricket).
//
// The site publishes a public, unauthenticated JSON API on `streamfree.top`
// (`/api/v1/categories`, `/api/v1/streams?category=…`) and plays each fixture
// through a JW-Player embed on `strmfree.st`. The embed page mints a short-lived
// signed HLS URL on its own CDN (`cdn1.strmfree.st`), so the provider reads the
// embed's own constants rather than guessing a URL:
//
//   const QUALITY = '1080p'; const SOURCE_SUFFIX = ''; const VARIANT = '<key>'…
//   const _0x = { "1080p": { "_t": …, "_e": …, "_n": … }, … };
//
// The playable URL is `<host>/live-cdn/<key><quality><suffix>/index.m3u8?_t&_e&_n`
// (path `live-cdn` / `live-externalcdn` / `live` chosen by `/get-stream-key`'s
// `server_name`). Verified live 2026-11-13: a match in play resolved to a real
// `#EXTM3U` playlist (HTTP 200); the same URL 404s once the match ends, because
// the fixture — not a VOD — is the stream. The signed `_e` expiry means the URL
// must be minted at play time, which is why getVideoSources re-reads the embed
// instead of caching a URL in the item.

var API = 'https://streamfree.top/api/v1';
var EMBED = 'https://strmfree.st';
var SOURCE_ID = 'streamfree';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// The API's category slugs, in the order the rails should read. Each is its own
// rail, so a user after one sport doesn't scroll past the others.
var CATEGORIES = [
  { key: 'soccer', title: 'Football' },
  { key: 'basketball', title: 'Basketball' },
  { key: 'hockey', title: 'Hockey' },
  { key: 'baseball', title: 'Baseball' },
  { key: 'football', title: 'American Football' },
  { key: 'combat', title: 'Combat' },
  { key: 'racing', title: 'Motorsport' },
  { key: 'tennis', title: 'Tennis' },
  { key: 'cricket', title: 'Cricket' }
];

var CATEGORY_TITLE = {};
for (var _i = 0; _i < CATEGORIES.length; _i++) CATEGORY_TITLE[CATEGORIES[_i].key] = CATEGORIES[_i].title;

function _headers(extra) {
  var h = { 'User-Agent': UA, 'Accept': 'application/json' };
  if (extra) for (var k in extra) h[k] = extra[k];
  return h;
}

function _json(url) {
  return fetch(url, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('streamfree: HTTP ' + r.status + ' for ' + url);
    return JSON.parse(r.body || 'null');
  });
}

function getInfo() {
  return {
    name: 'StreamFree', lang: 'en', baseUrl: 'https://streamfree.top',
    logo: EMBED + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// --- Mapping ---------------------------------------------------------------

// A fixture is "live" when at least one of its sources is flagged `live`; that
// is the only field the API updates the instant a broadcast starts, so it is
// what the badge keys on. `match_timestamp` is the kickoff (seconds), used for
// the countdown on an upcoming fixture and to age a just-finished one.
function _status(r, nowSec) {
  var src = r.sources || [];
  var live = false;
  for (var i = 0; i < src.length; i++) if (src[i] && src[i].live) live = true;
  if (live) return { badge: 'LIVE', live: true };
  var start = r.match_timestamp;
  if (!start) return { badge: null, live: false };
  if (nowSec < start - 600) return { badge: _countdown(start - nowSec), live: false };
  if (nowSec <= start + 12600) return { badge: 'SOON', live: false };
  return { badge: 'FT', live: false };
}

function _countdown(sec) {
  var m = Math.floor(sec / 60);
  var d = Math.floor(m / 1440);
  if (d >= 1) return 'in ' + d + 'd';
  var h = Math.floor(m / 60);
  if (h >= 1) return 'in ' + h + 'h ' + (m % 60) + 'm';
  return 'in ' + m + 'm';
}

// The second line: the competition, and the broadcaster when the API names one.
function _info(r) {
  var parts = [];
  if (r.league) parts.push(r.league);
  var src = r.sources || [];
  for (var i = 0; i < src.length; i++) {
    if (src[i] && src[i].broadcast) { parts.push(src[i].broadcast); break; }
  }
  return parts.length ? parts.join(' \u00B7 ') : null;
}

// The playable embed URL the API hands out for a fixture (the FHD source when
// there is a choice). This is what getVideoSources re-reads for a fresh token.
function _embedUrl(r) {
  var src = r.sources || [];
  for (var i = 0; i < src.length; i++) {
    var u = src[i] && src[i].url;
    if (u && u.indexOf('http') === 0) return u;
  }
  return null;
}

// The url packs the stream key, the category (the embed path segment) and the
// embed URL when the API already lists one. The key names the fixture for
// get-stream-key; the category rebuilds the embed path for a fixture that had
// no source yet at browse time. `live:<key>|<category>|<enc embedUrl>`.
function _handle(key, category, embed) {
  return 'live:' + key + '|' + (category || '') + '|' + encodeURIComponent(embed || '');
}

function _mapMatch(r, category, nowSec) {
  if (!r || !r.stream_key) return null;
  var st = _status(r, nowSec);
  var embed = _embedUrl(r);
  var item = {
    id: r.stream_key,
    title: r.name || r.stream_key,
    cover: r.thumbnail_url || null,
    banner: null,
    url: _handle(r.stream_key, category, embed),
    type: 'movie',
    sourceId: SOURCE_ID,
    liveBadge: st.badge,
    liveStartMs: r.match_timestamp ? r.match_timestamp * 1000 : null
  };
  var info = _info(r);
  if (info) item.liveInfo = info;
  if (r.league) item.genres = [r.league];
  return item;
}

// --- Browse ----------------------------------------------------------------

var _cache = {};
function _category(key) {
  if (_cache[key]) return Promise.resolve(_cache[key]);
  return _json(API + '/streams?category=' + encodeURIComponent(key)).then(function (d) {
    var list = (d && d.streams) || [];
    if (list.length) _cache[key] = list;
    return list;
  }).catch(function () { return []; });
}

function _nowSec() { return Math.floor(Date.now() / 1000); }

function getHome(opts) {
  var now = _nowSec();
  return Promise.all(CATEGORIES.map(function (c) {
    return _category(c.key).then(function (list) {
      var items = [];
      for (var i = 0; i < list.length; i++) {
        var m = _mapMatch(list[i], c.key, now);
        if (m) items.push(m);
      }
      return items.length ? { title: c.title, items: items } : null;
    });
  })).then(function (sections) {
    var out = [];
    for (var i = 0; i < sections.length; i++) if (sections[i]) out.push(sections[i]);
    return out;
  }).catch(function () { return []; });
}

// The live-sports feed: every fixture across every category, in-play first so
// the row leads with what a user can actually watch. This is the extension the
// Live screen folds in beside MovieBox's own matches.
function getLive(opts) {
  var now = _nowSec();
  return Promise.all(CATEGORIES.map(function (c) {
    return _category(c.key).then(function (list) {
      return list.map(function (r) { return _mapMatch(r, c.key, now); });
    });
  })).then(function (groups) {
    var all = [];
    for (var i = 0; i < groups.length; i++) {
      for (var j = 0; j < groups[i].length; j++) if (groups[i][j]) all.push(groups[i][j]);
    }
    all.sort(function (a, b) {
      var la = a.liveBadge === 'LIVE' ? 0 : 1;
      var lb = b.liveBadge === 'LIVE' ? 0 : 1;
      if (la !== lb) return la - lb;
      return (a.liveStartMs || 0) - (b.liveStartMs || 0);
    });
    return all;
  }).catch(function () { return []; });
}

function popular(opts) {
  return _category('soccer').then(function (list) {
    var now = _nowSec(), out = [];
    for (var i = 0; i < list.length; i++) {
      var m = _mapMatch(list[i], 'soccer', now);
      if (m) out.push(m);
    }
    return out;
  }).catch(function () { return []; });
}

function search(query, page, opts) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  var now = _nowSec();
  return Promise.all(CATEGORIES.map(function (c) { return _category(c.key); }))
    .then(function (groups) {
      var out = [];
      for (var i = 0; i < groups.length; i++) {
        for (var j = 0; j < groups[i].length; j++) {
          var r = groups[i][j];
          var hay = ((r.name || '') + ' ' + (r.league || '')).toLowerCase();
          if (hay.indexOf(q) < 0) continue;
          var m = _mapMatch(r, CATEGORIES[i].key, now);
          if (m) out.push(m);
        }
      }
      return out;
    }).catch(function () { return []; });
}

// --- Detail / streams ------------------------------------------------------

// A `live:` fixture has no show to browse — the handle IS the stream. This
// detail is a one-episode stub so the pack verifier and any generic
// detail→play path still work; the Live screen opens the player directly, and
// the player takes the fixture's real name from the tapped item/episode.
function getDetail(url, opts) {
  var h = _decode(url);
  if (!h.key) return Promise.resolve(null);
  var ep = { id: url, title: 'Live', number: 1, url: url };
  return Promise.resolve({
    id: url, title: 'Live', url: url, cover: null,
    description: 'Live sports broadcast', status: 'unknown', genres: [], studios: [],
    type: 'movie', sourceId: SOURCE_ID, episodes: [ep]
  });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d ? d.episodes : []; });
}

function _decode(itemUrl) {
  var s = String(itemUrl || '');
  if (s.indexOf('live:') === 0) s = s.slice('live:'.length);
  var parts = s.split('|');
  var key = parts[0] || '';
  var category = parts.length > 1 ? parts[1] : '';
  var embed = '';
  if (parts.length > 2) { try { embed = decodeURIComponent(parts[2]); } catch (e) { embed = ''; } }
  return { key: key, category: category, embed: embed };
}

// The embed's own constants: the quality, the suffix, the variant base and the
// per-quality token. Read with anchored patterns so a future layout tweak
// returns null (and getVideoSources falls back) instead of a wrong URL.
function _embedConstants(html) {
  function grab(re) { var m = String(html).match(re); return m ? m[1] : null; }
  var quality = grab(/const QUALITY = '([^']*)'/);
  var suffix = grab(/const SOURCE_SUFFIX = '([^']*)'/);
  var base = grab(/const VARIANT = '([^']*)'/);
  if (!quality || base === null) return null;
  var tokens = {};
  var tm = String(html).match(/const _0x = (\{[\s\S]*?\});/);
  if (tm) { try { tokens = JSON.parse(tm[1]); } catch (e) { tokens = {}; } }
  var tok = tokens[quality] || null;
  return { quality: quality, suffix: suffix || '', base: base, token: tok };
}

function _serverPath(serverName) {
  if (serverName === 'externalcdn') return 'live-externalcdn';
  if (serverName && serverName !== 'origin') return 'live-cdn';
  return 'live';
}

// Turn an embed page into one playable HLS source. `server_name` from
// /get-stream-key picks the CDN path; the embed supplies the token. Headers
// carry the embed referer the CDN expects.
function _resolveEmbed(embedUrl, key) {
  var embedHeaders = { 'User-Agent': UA, 'Referer': embedUrl, 'Origin': EMBED };
  var htmlFetch = fetch(embedUrl, { headers: embedHeaders }).then(function (r) {
    if (!r.ok) throw new Error('streamfree: embed HTTP ' + r.status);
    return r.body || '';
  });
  var keyFetch = fetch(EMBED + '/get-stream-key/' + encodeURIComponent(key),
    { headers: embedHeaders }).then(function (r) {
      return r.ok ? JSON.parse(r.body || '{}') : {};
    }).catch(function () { return {}; });

  return Promise.all([htmlFetch, keyFetch]).then(function (both) {
    var html = both[0], keyInfo = both[1] || {};
    if (keyInfo.is_external && keyInfo.external_url) {
      return [_source(keyInfo.external_url, embedHeaders, 'external')];
    }
    var c = _embedConstants(html);
    if (!c) return [];
    var variant = c.base + c.quality + c.suffix;
    var url = EMBED + '/' + _serverPath(keyInfo.server_name) + '/' +
      encodeURIComponent(variant) + '/index.m3u8';
    if (c.token && c.token._t) {
      url += '?_t=' + encodeURIComponent(c.token._t) +
        '&_e=' + encodeURIComponent(c.token._e) +
        '&_n=' + encodeURIComponent(c.token._n);
    }
    return [_source(url, embedHeaders, c.quality)];
  });
}

function _source(url, headers, label) {
  return {
    url: url,
    quality: label || 'Live',
    label: label ? 'Live ' + label : 'Live',
    container: 'hls',
    headers: { 'User-Agent': UA, 'Referer': headers.Referer, 'Origin': headers.Origin },
    kind: 'unknown',
    subtitles: []
  };
}

function getVideoSources(episodeUrl) {
  var h = _decode(episodeUrl);
  if (!h.key) return Promise.resolve([]);
  var embed = h.embed;
  // A handle minted before kickoff carries no embed URL (the API lists none
  // until the broadcast starts), so build the canonical one from the key and
  // the category the fixture was browsed under.
  if (!embed) {
    embed = EMBED + '/embed/' + (h.category || 'soccer') + '/' + h.key + '1080p';
  }
  return _resolveEmbed(embed, h.key).catch(function () { return []; });
}
