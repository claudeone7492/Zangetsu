// TimStreams provider — live sports fixtures, resolved natively.
//
// TimStreams publishes a public JSON schedule on `tim-streams.com`:
//
//   /api/live-upcoming   → { events:[…], genres:[…] }
//
// Each event carries a list of broadcaster feeds, each an embed URL. The embed
// page does NOT carry the stream URL in the clear: its player script is XOR
// obfuscated, and the URL lives behind a per-feed "ticket":
//
//   1. The page holds an integer array and a decode loop
//        String.fromCharCode(((_arr[_ix]^X)-S+256)%256)
//      Rebuilding that string in JS yields the player script, which contains
//        {"ticketUrl":"https://tims-001.sytes.net/p/<id>"}
//   2. GET the ticket → a small BINARY body. The first byte is a seed; the rest
//      is XOR'd with the ticket id (cycling) and the seed+index:
//        out[i] = body[i] ^ id[(i-1) % id.length] ^ ((seed + i - 1) & 255)
//      The decoded text is the signed `.m3u8` URL.
//
// Both steps run natively — no WASM, no browser, no keys. Step 2 needs the raw
// bytes, so the ticket fetch asks for { responseType: 'base64' } (the bridge
// ships the body as base64; see the fetch handler) and reads them with bytes().
//
// Verified live 2026-11-15: 6/6 sampled feeds decoded to real `#EXTM3U`
// playlists (HTTP 200).

var API = 'https://tim-streams.com/api/live-upcoming';
var SITE = 'https://tim-streams.com/';
var SOURCE_ID = 'timstreams';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// A fixture whose kick-off is this far in the past is treated as over; the feed
// is a live/upcoming scraper, not a replay archive.
var MAX_LIVE_MS = 4 * 60 * 60 * 1000;

function getInfo() {
  return {
    name: 'TimStreams', lang: 'en', baseUrl: 'https://tim-streams.com',
    logo: 'https://tim-streams.com/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

function _headers(extra) {
  var h = { 'User-Agent': UA, 'Accept': 'application/json, text/html, */*', 'Referer': SITE };
  if (extra) for (var k in extra) h[k] = extra[k];
  return h;
}

function _json(url) {
  return fetch(url, { headers: _headers(), timeoutMs: 15000 }).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return JSON.parse(r.body || 'null');
  });
}

function _text(url, referer) {
  return fetch(url, {
    headers: { 'User-Agent': UA, 'Accept': 'text/html,*/*', 'Referer': referer || SITE },
    timeoutMs: 15000
  }).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.body || '';
  });
}

// --- Time ------------------------------------------------------------------
// The feed prints wall-clock US/Eastern ("2026-11-15T09:30") with no zone.
// Parse it as Eastern so the live/upcoming window is right on a UTC device.
function _easternOffsetHours(y, m, d) {
  // US DST: second Sunday in March → first Sunday in November.
  function nthSunday(yy, month, nth) {
    var first = new Date(Date.UTC(yy, month, 1)).getUTCDay();
    return 1 + ((7 - first) % 7) + (nth - 1) * 7;
  }
  var start = Date.UTC(y, 2, nthSunday(y, 2, 2), 7); // 02:00 EST
  var end = Date.UTC(y, 10, nthSunday(y, 10, 1), 6); // 02:00 EDT
  var t = Date.UTC(y, m, d);
  return (t >= start && t < end) ? -4 : -5;
}

function _parseEastern(s) {
  var m = String(s || '').match(/(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/);
  if (!m) return 0;
  var y = +m[1], mo = +m[2] - 1, d = +m[3], hh = +m[4], mm = +m[5];
  var utc = Date.UTC(y, mo, d, hh, mm);
  return utc - _easternOffsetHours(y, mo, d) * 3600000;
}

function _status(startMs) {
  var now = Date.now();
  if (!startMs) return { badge: null, live: false, skip: false };
  if (now >= startMs) {
    if (now - startMs <= MAX_LIVE_MS) return { badge: 'LIVE', live: true, skip: false };
    return { badge: 'FT', live: false, skip: true };
  }
  var mins = Math.round((startMs - now) / 60000);
  var d = Math.floor(mins / 1440);
  var h = Math.floor((mins % 1440) / 60);
  var label = d >= 1 ? 'in ' + d + 'd' : h >= 1 ? 'in ' + h + 'h' : 'in ' + mins + 'm';
  return { badge: label, live: false, skip: false };
}

// --- Handles ---------------------------------------------------------------
// A fixture carries its broadcaster feeds, so a tap resolves every feed with no
// second schedule call.  ts:<enc(json{ n:name, s:[[feedName,url],…] })>
function _encode(title, feeds) {
  return 'ts:' + encodeURIComponent(JSON.stringify({ n: title || '', s: feeds || [] }));
}

function _decode(s) {
  if (String(s).indexOf('ts:') === 0) s = String(s).slice(3);
  try {
    var o = JSON.parse(decodeURIComponent(s));
    return { title: o.n || '', feeds: o.s || [] };
  } catch (e) {
    return { title: '', feeds: [] };
  }
}

// --- Mapping ---------------------------------------------------------------
function _genreName(genres, id) {
  for (var i = 0; i < genres.length; i++) {
    if (genres[i] && genres[i].id === id) return genres[i].name;
  }
  return '';
}

function _mapEvent(e, genres) {
  if (!e || !e.name) return null;
  if (e.vip) return null;
  var feeds = [];
  var src = e.streams || [];
  for (var i = 0; i < src.length; i++) {
    var st = src[i];
    if (st && st.url && !st.vip) feeds.push([st.name || 'Stream', st.url]);
  }
  // A fixture with no playable feed has nothing to open, so it stays out.
  if (!feeds.length) return null;
  var start = _parseEastern(e.time);
  var st2 = _status(start);
  if (st2.skip) return null;
  var genre = _genreName(genres, e.genre);
  var item = {
    id: e.url || e.name,
    title: e.name,
    cover: e.logo ? (e.logo.indexOf('http') === 0 ? e.logo : 'https://tim-streams.com' + e.logo) : null,
    banner: null,
    url: _encode(e.name, feeds),
    type: 'movie',
    sourceId: SOURCE_ID,
    liveBadge: st2.badge,
    liveStartMs: start || null,
    liveInfo: [genre, feeds.length > 1 ? feeds.length + ' feeds' : null].filter(Boolean).join(' \u00B7 ') || null
  };
  if (genre) item.genres = [genre];
  return item;
}

// --- Browse ----------------------------------------------------------------
var _cache = null;

function _events() {
  if (_cache) return Promise.resolve(_cache);
  return _json(API).then(function (d) {
    var genres = (d && d.genres) || [];
    var out = [];
    var evs = (d && d.events) || [];
    for (var i = 0; i < evs.length; i++) {
      var m = _mapEvent(evs[i], genres);
      if (m) out.push(m);
    }
    if (out.length) _cache = out;
    return out;
  }).catch(function () { return []; });
}

// Every playable fixture, in-play first so the rail leads with what a viewer
// can actually watch right now.
function getLive(opts) {
  return _events().then(function (items) {
    var copy = items.slice();
    copy.sort(function (a, b) {
      var la = a.liveBadge === 'LIVE' ? 0 : 1;
      var lb = b.liveBadge === 'LIVE' ? 0 : 1;
      if (la !== lb) return la - lb;
      return (a.liveStartMs || 0) - (b.liveStartMs || 0);
    });
    return copy;
  }).catch(function () { return []; });
}

function getHome(opts) {
  return _events().then(function (items) {
    var sections = [];
    var live = [];
    for (var i = 0; i < items.length; i++) if (items[i].liveBadge === 'LIVE') live.push(items[i]);
    if (live.length) sections.push({ title: 'Live Now', items: live });
    if (items.length) sections.push({ title: 'Upcoming', items: items });
    return sections;
  }).catch(function () { return []; });
}

function popular(opts) {
  return getLive(opts);
}

function search(query, page, opts) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  return _events().then(function (items) {
    var out = [];
    for (var i = 0; i < items.length; i++) {
      if (String(items[i].title || '').toLowerCase().indexOf(q) >= 0) out.push(items[i]);
    }
    return out;
  }).catch(function () { return []; });
}

// --- Detail / streams ------------------------------------------------------

// A fixture handle IS the stream, so the detail is a one-episode stub and the
// Live screen opens the player directly.
function getDetail(url, opts) {
  var title = _decode(url).title || 'Live';
  var ep = { id: url, title: title, number: 1, url: url };
  return Promise.resolve({
    id: url, title: title, url: url, cover: null,
    description: 'Live broadcast', status: 'unknown', genres: [], studios: [],
    type: 'movie', sourceId: SOURCE_ID, episodes: [ep]
  });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d ? d.episodes : []; });
}

// --- Native extraction -----------------------------------------------------

// Rebuild the player script from the page's XOR-obfuscated integer array.
function _decodeObfuscated(html) {
  var am = String(html).match(/var\s+\w+\s*=\s*\[([\d,\s]+)\]/);
  if (!am) return null;
  var lm = String(html).match(
    /String\.fromCharCode\(\s*\(+[^\^]+\^\s*(\w+)\s*\)\s*-\s*(\w+)\s*\+\s*256\s*\)\s*(?:%|&)\s*(?:256|255)\)/);
  if (!lm) return null;
  var arr = am[1].split(',');
  var xm = String(html).match(new RegExp(lm[1] + '\\s*=\\s*(\\d+)'));
  var sm = String(html).match(new RegExp(lm[2] + '\\s*=\\s*(\\d+)'));
  if (!xm || !sm) return null;
  var x = parseInt(xm[1], 10), s = parseInt(sm[1], 10), out = '';
  for (var i = 0; i < arr.length; i++) {
    out += String.fromCharCode(((parseInt(arr[i], 10) ^ x) - s + 256) % 256);
  }
  return out;
}

// GET the ticket and XOR-decode the signed .m3u8 URL from its raw bytes.
function _ticket(ticketUrl, embedUrl) {
  var origin = '';
  try { origin = embedUrl.match(/^https?:\/\/[^/]+/)[0]; } catch (e) { origin = ''; }
  return fetch(ticketUrl, {
    headers: { 'User-Agent': UA, 'Referer': embedUrl, 'Origin': origin },
    responseType: 'base64',
    timeoutMs: 15000
  }).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    var b = r.bytes();
    if (!b || b.length < 2) return null;
    var tk = ticketUrl.substring(ticketUrl.lastIndexOf('/') + 1);
    var seed = b[0] & 255, out = '';
    for (var i = 1; i < b.length; i++) {
      out += String.fromCharCode((b[i] & 255) ^ (tk.charCodeAt((i - 1) % tk.length) & 255) ^ ((seed + i - 1) & 255));
    }
    var m = out.match(/https?:\/\/[^"'\s<>]+\.m3u8[^"'\s<>]*/);
    return m ? m[0] : null;
  }).catch(function () { return null; });
}

function _resolveEmbed(embedUrl) {
  return _text(embedUrl, SITE).then(function (html) {
    var dec = _decodeObfuscated(html);
    if (!dec) return null;
    var um = dec.match(/https?:\/\/[^"'\s<>]+\.m3u8[^"'\s<>]*/);
    if (um) return um[0];
    var tm = dec.match(/"ticketUrl"\s*:\s*"([^"]+)"/);
    if (!tm) return null;
    return _ticket(tm[1], embedUrl);
  }).catch(function () { return null; });
}

function _source(url, label, embedUrl) {
  var origin = '';
  try { origin = embedUrl.match(/^https?:\/\/[^/]+/)[0]; } catch (e) { origin = ''; }
  var hdrs = { 'User-Agent': UA };
  if (embedUrl) hdrs.Referer = embedUrl;
  if (origin) hdrs.Origin = origin;
  return {
    url: url,
    quality: label || 'Live',
    label: label ? 'Live ' + label : 'Live',
    container: 'hls',
    headers: hdrs,
    kind: 'unknown',
    subtitles: []
  };
}

function getVideoSources(episodeUrl) {
  var d = _decode(episodeUrl);
  var feeds = d.feeds || [];
  if (!feeds.length) return Promise.resolve([]);
  return Promise.all(feeds.slice(0, 8).map(function (f) {
    var name = f[0], embed = f[1];
    return _resolveEmbed(embed).then(function (u) {
      return u ? _source(u, name, embed) : null;
    });
  })).then(function (rows) {
    return rows.filter(Boolean);
  }).catch(function () { return []; });
}
