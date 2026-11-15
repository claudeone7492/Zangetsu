// CDNLive TV provider — live sports fixtures plus 24/7 live channels.
//
// CDNLive publishes a public JSON API on `cdnlivetv.tv` (mirrored on
// `cdnlivetv.is`) that needs no key for its free tier:
//
//   /api/v1/events/sports/?user=cdnlivetv&plan=free   → fixtures by sport
//   /api/v1/channels/?user=cdnlivetv&plan=free        → 400+ 24/7 channels
//
// Each entry points at a player page (`/api/v1/channels/player/?name=…`) that
// does NOT carry the stream URL in the clear. The page builds it from a run of
// single-character base64 fragments joined by a decoder call:
//
//   function D(s){s=s.replace(/-/g,'+')…return atob(s)};
//   var a='aHR0cHM', b='Og', c='Ly8', … ;
//   var URL = D(a)+D(b)+D(c)+…;
//
// So the provider fetches the player page and re-joins those fragments with a
// local base64 decoder — the same technique the player itself uses, with no
// key material. The result is a signed `#EXTM3U` playlist on `cdnlivetv.tv`;
// the token is minted per channel and expires, so getVideoSources re-reads the
// player page at play time rather than caching a URL in the item.
//
// Verified live 2026-11-15: decoded channels returned real `#EXTM3U` playlists
// (HTTP 200), and the sports feed carried 500+ fixtures across a dozen sports.

var API = 'https://api.cdnlivetv.tv/api/v1';
var API_ALT = 'https://api.cdnlivetv.is/api/v1';
var REFERER = 'https://cdnlivetv.tv/';
var SOURCE_ID = 'cdnlivetv';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

// Free-tier credentials. `cdnlivetv` covers channels; the sports event feed is
// also served on the free tier. A VIP pair is tried as a fallback so a fixture
// whose broadcaster is only on the paid tier still resolves.
var CHANNEL_LIST = [
  API + '/channels/?user=cdnlivetv&plan=free',
  API_ALT + '/channels/?user=cdnlivetv&plan=free'
];
var EVENT_LIST = [
  API + '/events/sports/?user=cdnlivetv&plan=free',
  API_ALT + '/events/sports/?user=streamsports99&plan=vip'
];

// Channel names that read as sport, so the sports rail leads with the channels
// a match-watcher actually wants instead of a country's general entertainment.
var SPORT_RE = /sport|espn|fox sport|sky sport|bein|dazn|eurosport|tsn|supersport|willow|star sport|sony ten|nba|nfl|nhl|mlb|epl|premier|golf|tennis|cricket|motorsport|fight|ufc|wwe/i;

function getInfo() {
  return {
    name: 'CDNLive TV', lang: 'en', baseUrl: 'https://cdnlivetv.tv',
    logo: 'https://cdnlivetv.tv/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

function _headers(extra) {
  var h = { 'User-Agent': UA, 'Accept': 'application/json', 'Referer': REFERER };
  if (extra) for (var k in extra) h[k] = extra[k];
  return h;
}

function _json(urls) {
  // Try each mirror in turn; first that answers with JSON wins.
  var i = 0;
  function attempt() {
    if (i >= urls.length) return Promise.resolve(null);
    var url = urls[i++];
    return fetch(url, { headers: _headers(), timeoutMs: 15000 }).then(function (r) {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return JSON.parse(r.body || 'null');
    }).catch(function () { return attempt(); });
  }
  return attempt();
}

function _text(url, referer) {
  return fetch(url, {
    headers: { 'User-Agent': UA, 'Accept': 'text/html,*/*', 'Referer': referer || REFERER },
    timeoutMs: 15000
  }).then(function (r) {
    if (!r.ok) throw new Error('HTTP ' + r.status);
    return r.body || '';
  });
}

// --- base64 → UTF-8 string ------------------------------------------------
// globalThis.base64ToBytes decodes base64url to a byte array; the player pages
// carry plain ASCII URLs, but decode UTF-8 properly so a non-ASCII fragment
// cannot corrupt the join.
function _b64Str(b64) {
  var bytes = globalThis.base64ToBytes(String(b64).replace(/-/g, '+').replace(/_/g, '/'));
  var out = '';
  var i = 0;
  while (i < bytes.length) {
    var c = bytes[i++];
    if (c < 0x80) {
      out += String.fromCharCode(c);
    } else if (c < 0xE0) {
      out += String.fromCharCode(((c & 0x1F) << 6) | (bytes[i++] & 0x3F));
    } else if (c < 0xF0) {
      out += String.fromCharCode(((c & 0x0F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F));
    } else {
      var cp = ((c & 0x07) << 18) | ((bytes[i++] & 0x3F) << 12) | ((bytes[i++] & 0x3F) << 6) | (bytes[i++] & 0x3F);
      cp -= 0x10000;
      out += String.fromCharCode(0xD800 + ((cp >> 10) & 0x3FF), 0xDC00 + (cp & 0x3FF));
    }
  }
  return out;
}

// Rebuild the stream URL from a player page's fragment join.
function _decodePlayer(html) {
  var m = String(html).match(/var\s+[A-Za-z0-9_]+\s*=\s*((?:[A-Za-z0-9_]+\([A-Za-z0-9_]+\)\s*\+?\s*)+);/);
  if (!m) return null;
  var calls = m[1].match(/[A-Za-z0-9_]+\([A-Za-z0-9_]+\)/g) || [];
  var out = '';
  for (var i = 0; i < calls.length; i++) {
    var vn = calls[i].replace(/.*\(([A-Za-z0-9_]+)\)/, '$1');
    var vm = String(html).match(new RegExp("var\\s+" + vn + "\\s*=\\s*'([^']*)'"));
    if (vm) out += _b64Str(vm[1]);
  }
  return out.indexOf('.m3u8') >= 0 ? out : null;
}

// Fetch a channel's player page and decode its stream URL.
function _resolvePlayer(playerUrl) {
  return _text(playerUrl).then(function (html) {
    var url = _decodePlayer(html);
    if (url) return url;
    // Mirror fallback: the token is bound to the host it was minted on.
    var alt = playerUrl.indexOf('cdnlivetv.tv') >= 0
      ? playerUrl.replace('cdnlivetv.tv', 'cdnlivetv.is')
      : playerUrl.replace('cdnlivetv.is', 'cdnlivetv.tv');
    return _text(alt).then(function (h2) { return _decodePlayer(h2); });
  }).catch(function () { return null; });
}

// --- Handles ---------------------------------------------------------------
// A channel carries name + player url so detail/sources need no refetch.
//   ch:<enc(name)>|<enc(url)>
// An event carries its broadcaster channel list, so a tap resolves every
// server without a second feed call.
//   ev:<enc(title)>|<enc(json[{name,url}])>
function _encodeChannel(name, url) {
  return 'ch:' + encodeURIComponent(name || '') + '|' + encodeURIComponent(url || '');
}

function _decodeChannel(s) {
  if (s.indexOf('ch:') === 0) s = s.slice(3);
  var bar = s.indexOf('|');
  if (bar < 0) return { name: '', url: s };
  var name = '', url = '';
  try { name = decodeURIComponent(s.slice(0, bar)); } catch (e) { name = ''; }
  try { url = decodeURIComponent(s.slice(bar + 1)); } catch (e) { url = ''; }
  return { name: name, url: url };
}

function _encodeEvent(title, channels) {
  return 'ev:' + encodeURIComponent(title || '') + '|' + encodeURIComponent(JSON.stringify(channels || []));
}

function _decodeEvent(s) {
  if (s.indexOf('ev:') === 0) s = s.slice(3);
  var bar = s.indexOf('|');
  var title = '', channels = [];
  if (bar < 0) return { title: s, channels: [] };
  try { title = decodeURIComponent(s.slice(0, bar)); } catch (e) { title = ''; }
  try { channels = JSON.parse(decodeURIComponent(s.slice(bar + 1))) || []; } catch (e) { channels = []; }
  return { title: title, channels: channels };
}

// --- Mapping ---------------------------------------------------------------

function _parseStart(v) {
  // "2026-11-15 12:00" → epoch ms. Date parses the space form as local time,
  // which is the best guess the feed offers (it carries no zone).
  var t = Date.parse(String(v || '').replace(' ', 'T'));
  return isNaN(t) ? 0 : t;
}

function _status(startMs, endMs) {
  var now = Date.now();
  if (!startMs) return { badge: null, live: false };
  if (now >= startMs && (!endMs || now <= endMs)) return { badge: 'LIVE', live: true };
  if (now < startMs) {
    var mins = Math.round((startMs - now) / 60000);
    var d = Math.floor(mins / 1440);
    var h = Math.floor((mins % 1440) / 60);
    var label = d >= 1 ? 'in ' + d + 'd' : h >= 1 ? 'in ' + h + 'h' : 'in ' + mins + 'm';
    return { badge: label, live: false };
  }
  return { badge: 'FT', live: false };
}

function _mapEvent(e, sport) {
  if (!e || !e.event) return null;
  var chans = [];
  var src = e.channels || [];
  for (var i = 0; i < src.length; i++) {
    var c = src[i];
    if (c && c.url) chans.push({ name: c.channel_name || c.name || 'Server', url: c.url });
  }
  // A fixture with no broadcaster has nothing to play — a tap could only
  // explain that, so it stays out of the rail.
  if (!chans.length) return null;
  var start = _parseStart(e.start);
  var end = _parseStart(e.end);
  var st = _status(start, end);
  var item = {
    id: e.gameID || e.event,
    title: e.event,
    cover: e.homeTeamIMG || null,
    banner: null,
    url: _encodeEvent(e.event, chans),
    type: 'movie',
    sourceId: SOURCE_ID,
    liveBadge: st.badge,
    liveStartMs: start || null,
    liveInfo: [e.tournament || sport, e.country].filter(Boolean).join(' \u00B7 ') || null
  };
  if (e.tournament) item.genres = [e.tournament];
  // Canonical sport slug, lowercased. The API buckets by sport name, so this
  // is mostly a lowercase; both soccer spellings are folded onto the one slug
  // the app filters on, so a feed that ever says 'Football' for the world's
  // game still lands in the rail.
  if (sport) {
    var slug = String(sport).toLowerCase();
    if (slug === 'football' || slug === 'soccer') slug = 'soccer';
    item.liveSport = slug;
  }
  return item;
}

function _mapChannel(c) {
  if (!c || !c.name || !c.url) return null;
  if (c.status && c.status !== 'online') return null;
  return {
    id: c.name,
    title: c.name,
    cover: c.image || null,
    banner: null,
    url: _encodeChannel(c.name, c.url),
    type: 'movie',
    sourceId: SOURCE_ID
  };
}

// --- Browse ----------------------------------------------------------------
var _cache = {};

function _channels() {
  if (_cache.channels) return Promise.resolve(_cache.channels);
  return _json(CHANNEL_LIST).then(function (d) {
    var list = (d && d.channels) || [];
    if (list.length) _cache.channels = list;
    return list;
  });
}

function _events() {
  if (_cache.events) return Promise.resolve(_cache.events);
  return _json(EVENT_LIST).then(function (d) {
    var root = (d && d['cdn-live-tv']) || d || {};
    var out = [];
    for (var sport in root) {
      if (!Object.prototype.hasOwnProperty.call(root, sport)) continue;
      var arr = root[sport];
      if (!arr || !arr.length || typeof arr.push !== 'function') continue;
      for (var i = 0; i < arr.length; i++) {
        var m = _mapEvent(arr[i], sport);
        if (m) out.push(m);
      }
    }
    if (out.length) _cache.events = out;
    return out;
  });
}

function _mapChannels(list, limit) {
  var out = [];
  var n = (limit && list.length > limit) ? limit : list.length;
  for (var i = 0; i < n; i++) {
    var m = _mapChannel(list[i]);
    if (m) out.push(m);
  }
  return out;
}

function _sportChannels(list, limit) {
  var out = [];
  for (var i = 0; i < list.length && out.length < limit; i++) {
    if (SPORT_RE.test(list[i].name || '')) {
      var m = _mapChannel(list[i]);
      if (m) out.push(m);
    }
  }
  return out;
}

function getHome(opts) {
  return Promise.all([_events(), _channels()]).then(function (both) {
    var events = both[0], channels = both[1];
    var sections = [];
    if (events.length) sections.push({ title: 'Live Sports', items: events.slice(0, 60) });
    var sport = _sportChannels(channels, 40);
    if (sport.length) sections.push({ title: 'Sports Channels', items: sport });
    var all = _mapChannels(channels, 80);
    if (all.length) sections.push({ title: 'Live Channels', items: all });
    return sections;
  }).catch(function () { return []; });
}

// The live-sports feed: every playable fixture, in-play first so the rail
// leads with what a user can actually watch.
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

function popular(opts) {
  return _channels().then(function (list) {
    var sport = _sportChannels(list, 40);
    return sport.length ? sport : _mapChannels(list, 40);
  }).catch(function () { return []; });
}

function search(query, page, opts) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  return Promise.all([_channels(), _events()]).then(function (both) {
    var out = [];
    var chans = both[0], events = both[1];
    for (var i = 0; i < chans.length; i++) {
      if (String(chans[i].name || '').toLowerCase().indexOf(q) >= 0) {
        var m = _mapChannel(chans[i]);
        if (m) out.push(m);
      }
    }
    for (var j = 0; j < events.length; j++) {
      if (String(events[j].title || '').toLowerCase().indexOf(q) >= 0) out.push(events[j]);
    }
    return out;
  }).catch(function () { return []; });
}

// --- Detail / streams ------------------------------------------------------

// A `ch:` channel or `ev:` fixture has no show to browse — the handle IS the
// stream. This detail is a one-episode stub so the generic detail→play path
// works; the Live screen opens the player directly.
function getDetail(url, opts) {
  var title = 'Live';
  if (String(url).indexOf('ev:') === 0) title = _decodeEvent(url).title || 'Live';
  else title = _decodeChannel(url).name || 'Live';
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

function _source(url, label) {
  return {
    url: url,
    quality: label || 'Live',
    label: label ? 'Live ' + label : 'Live',
    container: 'hls',
    headers: { 'User-Agent': UA, 'Referer': REFERER },
    kind: 'unknown',
    subtitles: []
  };
}

function getVideoSources(episodeUrl) {
  var s = String(episodeUrl || '');
  if (s.indexOf('ev:') === 0) {
    var ev = _decodeEvent(s);
    var chans = ev.channels || [];
    if (!chans.length) return Promise.resolve([]);
    return Promise.all(chans.slice(0, 6).map(function (c) {
      return _resolvePlayer(c.url).then(function (u) { return u ? _source(u, c.name) : null; });
    })).then(function (urls) {
      return urls.filter(Boolean);
    }).catch(function () { return []; });
  }
  var ch = _decodeChannel(s);
  if (!ch.url) return Promise.resolve([]);
  return _resolvePlayer(ch.url).then(function (u) {
    return u ? [_source(u, ch.name)] : [];
  }).catch(function () { return []; });
}
