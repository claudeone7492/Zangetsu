// Nuvio Live Sports provider — the public Nuvio sports addon.
//
// The addon exposes a Stremio catalog and stream API:
//   /catalog/tv/<catalog>.json  -> fixtures, one entry per match
//   /stream/tv/<id>.json        -> direct HLS mirrors, proxied by the addon
//
// The fixture list is English and already grouped by competition, so the
// Sports screen can show "Premier League", "La Liga", … without translating
// anything. Streams are proxied through `api/manifest.m3u8`, which rewrites the
// upstream playlist and keeps the provider's headers out of the player.

var BASE = 'https://nuviosports.xyz';
var SOURCE_ID = 'nuviotv';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
var CATALOGS = [
  'nuvio_sports_football',
  'nuvio_sports_live',
  'nuvio_sports_upcoming'
];

var _cache = null;

function _headers() {
  return {
    'User-Agent': UA,
    'Accept': 'application/json',
    'Referer': BASE + '/'
  };
}

function _getJson(path) {
  return fetch(BASE + path, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('nuvio: HTTP ' + r.status);
    return r.body || '{}';
  }).then(function (body) { return JSON.parse(body); });
}

function _cleanName(raw) {
  return String(raw || '')
    .replace(/^[\s\u{1F534}\u23F1\uFE0F]*LIVE\s*:\s*/iu, '')
    .replace(/^[\s\u23F1\uFE0F]+/u, '')
    .replace(/[\u{E0000}-\u{E007F}]/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function _query(poster, key) {
  var m = new RegExp('[?&]' + key + '=([^&]*)').exec(String(poster || ''));
  if (!m) return '';
  try {
    return decodeURIComponent(m[1].replace(/\+/g, ' '));
  } catch (e) {
    return m[1];
  }
}

function _league(meta) {
  var desc = String(meta.description || '');
  var m = /League:\s*([^\n\r]+)/i.exec(desc);
  if (m) return m[1].trim();
  return _query(meta.poster, 'lg');
}

function _startMs(meta) {
  var t = Date.parse(meta.released || '');
  return isNaN(t) ? null : t;
}

function _badge(meta, start) {
  if (/^(\u{1F534}|\u{1F534}\uFE0F)?\s*LIVE/i.test(String(meta.name || '')) ||
      String(meta.releaseInfo || '').toUpperCase() === 'LIVE') {
    return 'LIVE';
  }
  if (start == null) return null;
  var sec = Math.floor((start - Date.now()) / 1000);
  if (sec <= 0) return 'LIVE';
  var mins = Math.ceil(sec / 60);
  if (mins < 60) return 'in ' + mins + 'm';
  var hours = Math.floor(mins / 60);
  var rem = mins % 60;
  return 'in ' + hours + 'h' + (rem ? ' ' + rem + 'm' : '');
}

function _map(meta) {
  if (!meta || !meta.id) return null;
  var title = _cleanName(meta.name);
  if (!title) return null;
  var league = _league(meta);
  var channel = _query(meta.poster, 'ch');
  var start = _startMs(meta);
  var item = {
    id: meta.id,
    title: title,
    cover: meta.poster || meta.background || null,
    banner: meta.background || null,
    url: 'nuviotv:' + meta.id,
    type: 'movie',
    sourceId: SOURCE_ID,
    liveBadge: _badge(meta, start),
    liveSport: 'soccer'
  };
  if (start != null) item.liveStartMs = start;
  var info = [league, channel].filter(Boolean).join(' \u00B7 ');
  if (info) item.liveInfo = info;
  if (league) item.genres = [league];
  if (meta.description) item.description = String(meta.description);
  return item;
}

function _all() {
  if (_cache) return Promise.resolve(_cache);
  return Promise.all(CATALOGS.map(function (id) {
    return _getJson('/catalog/tv/' + id + '.json').then(function (d) {
      return (d && d.metas) || [];
    }).catch(function () { return []; });
  })).then(function (lists) {
    var byId = {};
    var order = [];
    for (var i = 0; i < lists.length; i++) {
      for (var j = 0; j < lists[i].length; j++) {
        var meta = lists[i][j];
        if (!meta || !meta.id) continue;
        var genres = (meta.genres || []).join(' ').toLowerCase();
        var poster = String(meta.poster || '').toLowerCase();
        var desc = String(meta.description || '').toLowerCase();
        var isAmerican = /american[ _-]?football/.test(genres) ||
          /cat=american_football/.test(poster) ||
          /category:\s*american football/.test(desc);
        var isFootball = !isAmerican && (
          /football/.test(genres) ||
          /cat=football/.test(poster) ||
          /category:\s*football/.test(desc));
        if (!isFootball) continue;
        if (!byId[meta.id]) order.push(meta.id);
        byId[meta.id] = meta;
      }
    }
    _cache = order.map(function (id) { return byId[id]; });
    return _cache;
  });
}

function _idOf(url) {
  var s = String(url || '');
  return s.indexOf('nuviotv:') === 0 ? s.slice(8) : s;
}

function getInfo() {
  return {
    name: 'Nuvio Live Sports', lang: 'en', baseUrl: BASE,
    logo: BASE + '/logo.png', type: 'movie', version: '1.0.0'
  };
}

function getHome() {
  return _all().then(function (metas) {
    var live = [], soon = [];
    for (var i = 0; i < metas.length; i++) {
      var item = _map(metas[i]);
      if (!item) continue;
      if (item.liveBadge === 'LIVE') live.push(item);
      else soon.push(item);
    }
    var out = [];
    if (live.length) out.push({ title: 'Live Football', items: live.slice(0, 60) });
    if (soon.length) out.push({ title: 'Upcoming Football', items: soon.slice(0, 60) });
    return out;
  }).catch(function () { return []; });
}

function getLive() {
  return _all().then(function (metas) {
    var out = [];
    for (var i = 0; i < metas.length; i++) {
      var item = _map(metas[i]);
      if (item) out.push(item);
    }
    return out;
  }).catch(function () { return []; });
}

function popular() {
  return getLive();
}

function search(query) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  return _all().then(function (metas) {
    var out = [];
    for (var i = 0; i < metas.length && out.length < 60; i++) {
      var item = _map(metas[i]);
      if (!item) continue;
      var hay = (item.title + ' ' + (item.liveInfo || '')).toLowerCase();
      if (hay.indexOf(q) >= 0) out.push(item);
    }
    return out;
  }).catch(function () { return []; });
}

function getDetail(url) {
  var id = _idOf(url);
  return _all().then(function (metas) {
    for (var i = 0; i < metas.length; i++) {
      if (String(metas[i].id) !== id) continue;
      var item = _map(metas[i]);
      if (!item) return null;
      var ep = { id: item.url, title: item.title, number: 1, url: item.url };
      return {
        id: item.url, title: item.title, url: item.url, cover: item.cover,
        description: item.description || item.liveInfo || 'Live football',
        status: 'unknown', genres: item.genres, studios: [],
        type: 'movie', sourceId: SOURCE_ID, episodes: [ep]
      };
    }
    return null;
  }).catch(function () { return null; });
}

function getEpisodes(url) {
  return getDetail(url).then(function (d) { return d ? d.episodes : []; });
}

function getVideoSources(episodeUrl) {
  var id = _idOf(episodeUrl);
  return _getJson('/stream/tv/' + encodeURIComponent(id) + '.json').then(function (d) {
    var streams = (d && d.streams) || [];
    var out = [];
    var seen = {};
    for (var i = 0; i < streams.length && out.length < 30; i++) {
      var s = streams[i];
      if (!s || !s.url || seen[s.url]) continue;
      seen[s.url] = true;
      var title = String(s.title || '').split('\n')[0];
      out.push({
        url: s.url,
        quality: s.resolution || null,
        label: [s.name || 'Live', title].filter(Boolean).join(' \u00B7 '),
        container: 'hls',
        headers: {
          'User-Agent': UA,
          'Referer': BASE + '/',
          'Origin': BASE
        },
        kind: 'unknown',
        subtitles: []
      });
    }
    return out;
  }).catch(function () { return []; });
}
