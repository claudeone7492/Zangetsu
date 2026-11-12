// IPTV provider — live channels from the iptv-org and Free-TV playlists,
// served through the JsDelivr CDN.
//
// iptv-org publishes per-category M3U playlists on its `gh-pages` branch; the
// same files are mirrored by JsDelivr (`cdn.jsdelivr.net/gh/...@gh-pages`) and
// by GitHub Pages (`iptv-org.github.io`). Each entry is a live HLS/TS channel,
// so the provider exposes channels as browse rails and lets search filter the
// full index by name. Verified live (JsDelivr + GitHub Pages mirrors).

var JSDELIVR = 'https://cdn.jsdelivr.net/gh/iptv-org/iptv@gh-pages';
var PAGES = 'https://iptv-org.github.io/iptv';
var FREETV = 'https://cdn.jsdelivr.net/gh/Free-TV/IPTV@master/playlist.m3u8';
var SOURCE_ID = 'iptv';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

var CATEGORIES = [
  { key: 'animation', title: 'Animation' },
  { key: 'movies', title: 'Movies' },
  { key: 'series', title: 'Series' },
  { key: 'news', title: 'News' },
  { key: 'sports', title: 'Sports' },
  { key: 'kids', title: 'Kids' },
  { key: 'documentary', title: 'Documentary' },
  { key: 'music', title: 'Music' }
];

function _headers() { return { 'User-Agent': UA, 'Accept': '*/*' }; }

function _text(url) {
  return fetch(url, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('iptv: HTTP ' + r.status + ' for ' + url);
    return r.body || '';
  });
}

// Try the JsDelivr mirror, then GitHub Pages. Returns the first that answers.
function _playlist(rel) {
  return _text(JSDELIVR + rel).catch(function () {
    return _text(PAGES + rel);
  });
}

function getInfo() {
  return {
    name: 'IPTV', lang: 'en', baseUrl: PAGES,
    logo: 'https://iptv-org.github.io/logo.svg', type: 'movie', version: '1.0.0'
  };
}

// --- M3U parsing -----------------------------------------------------------
function _attr(line, key) {
  var m = line.match(new RegExp(key + '="([^"]*)"'));
  return m ? m[1] : null;
}

function _parseM3u(text) {
  var lines = String(text || '').split('\n');
  var out = [], cur = null;
  for (var i = 0; i < lines.length; i++) {
    var ln = lines[i].replace(/\r$/, '');
    if (ln.indexOf('#EXTINF') === 0) {
      var c = ln.lastIndexOf(',');
      cur = {
        name: c >= 0 ? ln.slice(c + 1).trim() : '',
        logo: _attr(ln, 'tvg-logo'),
        group: _attr(ln, 'group-title'),
        url: null
      };
    } else if (ln && ln.charAt(0) !== '#') {
      if (cur && ln.indexOf('://') > 0) {
        cur.url = ln.trim();
        if (cur.name || cur.url) out.push(cur);
      }
      cur = null;
    }
  }
  return out;
}

// A channel item carries its name + stream url, so detail/sources need no
// refetch. `ch:<enc(name)>|<enc(url)>`.
function _encode(name, url) {
  return 'ch:' + encodeURIComponent(name || '') + '|' + encodeURIComponent(url || '');
}

function _decode(itemUrl) {
  var s = String(itemUrl || '');
  if (s.indexOf('ch:') === 0) s = s.slice(3);
  var bar = s.indexOf('|');
  if (bar < 0) return { name: '', url: s };
  var name = '', url = '';
  try { name = decodeURIComponent(s.slice(0, bar)); } catch (e) { name = ''; }
  try { url = decodeURIComponent(s.slice(bar + 1)); } catch (e) { url = ''; }
  return { name: name, url: url };
}

function _mapChannels(chs, limit) {
  var out = [];
  var n = (limit && chs.length > limit) ? limit : chs.length;
  for (var i = 0; i < n; i++) {
    var c = chs[i];
    if (!c || !c.url) continue;
    out.push({
      id: _encode(c.name, c.url),
      title: c.name || c.group || 'Channel',
      cover: c.logo || null,
      url: _encode(c.name, c.url),
      type: 'movie', sourceId: SOURCE_ID
    });
  }
  return out;
}

// --- Browse ----------------------------------------------------------------
// One rail per category, parsed from its playlist. Cached per runtime session.
var _catCache = {};
function _category(key) {
  if (_catCache[key]) return Promise.resolve(_catCache[key]);
  return _playlist('/categories/' + key + '.m3u').then(function (t) {
    var chs = _parseM3u(t);
    if (chs.length) _catCache[key] = chs;
    return chs;
  }).catch(function () { return []; });
}

function getHome(opts) {
  return Promise.all(CATEGORIES.map(function (c) {
    return _category(c.key).then(function (chs) {
      var items = _mapChannels(chs, 40);
      return items.length ? { title: c.title, items: items } : null;
    });
  })).then(function (sections) {
    var out = [];
    for (var i = 0; i < sections.length; i++) if (sections[i]) out.push(sections[i]);
    return out;
  }).catch(function () { return []; });
}

function popular(opts) {
  return _category('movies').then(function (chs) { return _mapChannels(chs, 60); })
    .catch(function () { return []; });
}

// Full index, cached — search filters it by channel name.
var _index = null;
function _fullIndex() {
  if (_index && _index.length) return Promise.resolve(_index);
  return _playlist('/index.m3u').then(function (t) {
    var chs = _parseM3u(t);
    if (chs.length) _index = chs;
    return chs;
  }).catch(function () { return []; });
}

function search(query, page, opts) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  return _fullIndex().then(function (chs) {
    var out = [], seen = {};
    for (var i = 0; i < chs.length && out.length < 60; i++) {
      var c = chs[i];
      if (!c || !c.url) continue;
      if (String(c.name || '').toLowerCase().indexOf(q) < 0) continue;
      if (seen[c.url]) continue;
      seen[c.url] = 1;
      out.push({
        id: _encode(c.name, c.url), title: c.name || 'Channel',
        cover: c.logo || null, url: _encode(c.name, c.url),
        type: 'movie', sourceId: SOURCE_ID
      });
    }
    return out;
  });
}

// --- Detail / streams ------------------------------------------------------
function getDetail(url, opts) {
  var c = _decode(url);
  if (!c.url) return Promise.resolve(null);
  var ep = { id: url, title: c.name || 'Live', number: 1, url: url };
  return Promise.resolve({
    id: url, title: c.name || 'Live', url: url, cover: null,
    description: 'Live channel', status: 'unknown', genres: [], studios: [],
    type: 'movie', sourceId: SOURCE_ID, episodes: [ep]
  });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d ? d.episodes : []; });
}

function getVideoSources(episodeUrl) {
  var c = _decode(episodeUrl);
  if (!c.url) return Promise.resolve([]);
  return Promise.resolve([{
    url: c.url,
    quality: null,
    label: c.name || 'Live',
    container: _container(c.url),
    headers: { 'User-Agent': UA },
    kind: 'unknown',
    subtitles: []
  }]);
}

function _container(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0) return 'hls';
  if (u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}
