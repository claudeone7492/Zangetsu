// ScoreZone provider — live sports channels from ScoreZone's public IPTV
// bridge.
//
// The bridge is a Cloudflare Worker that answers only when the request carries
// the ScoreZone origin (`Origin` + `Referer`). It returns ~450 channels, 69 of
// them sport, each with a short-lived signed `/live/<token>/media.ts` URL.
// Because the URL expires (~15 minutes) and is signed per response,
// getVideoSources refetches the list instead of caching the URL.
//
// Verified live 2026-11-22: the sports list answered 200 (211 KB) and a
// channel URL returned 1.7 MB of `video/mp2t`.

var API = 'https://scorezone-live.scorezone.workers.dev/api/iptv/channels';
var ORIGIN = 'https://scorezonetv.live';
var SOURCE_ID = 'scorezone';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

var _cache = null;

function _headers() {
  return {
    'User-Agent': UA,
    'Accept': 'application/json',
    'Origin': ORIGIN,
    'Referer': ORIGIN + '/'
  };
}

function _load(force) {
  if (!force && _cache && _cache.length) return Promise.resolve(_cache);
  return fetch(API, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('scorezone: HTTP ' + r.status);
    return r.body || '{}';
  }).then(function (body) {
    var data = JSON.parse(body);
    var channels = (data && data.channels) || [];
    if (channels.length) _cache = channels;
    return channels;
  }).catch(function () { return []; });
}

function _isSports(c) {
  var genres = c.genres || [];
  for (var i = 0; i < genres.length; i++) {
    if (/sport/i.test(genres[i])) return true;
  }
  return false;
}

// The bridge tags only "Sports"; this narrows to football/soccer channels so
// the Sports screen's football rail is not padded with NBA/NFL channels.
function _isFootball(c) {
  var text = String(c.name || '') + ' ' + (c.genres || []).join(' ');
  return /football|soccer|futbol|calcio|bein|dazn|sky sport|supersport|tnt sport|premier|liga|serie a|bundesliga|ligue 1|eredivisie|primeira/i.test(text);
}

function _map(c) {
  var id = 'sz:' + String(c.id || '');
  return {
    id: id,
    title: c.name || 'Live channel',
    cover: c.poster || null,
    url: id,
    type: 'movie',
    sourceId: SOURCE_ID,
    liveSport: 'soccer',
    liveBadge: 'LIVE',
    liveInfo: '24/7' + (c.country ? ' · ' + c.country : ''),
    genres: ['Football Channels']
  };
}

function getInfo() {
  return {
    name: 'ScoreZone', lang: 'en', baseUrl: ORIGIN,
    logo: ORIGIN + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

function getHome(opts) {
  return _load(false).then(function (channels) {
    var football = [], sports = [];
    for (var i = 0; i < channels.length; i++) {
      var c = channels[i];
      if (!c || !c.url) continue;
      if (_isFootball(c)) football.push(_map(c));
      else if (_isSports(c)) sports.push(_map(c));
    }
    var out = [];
    if (football.length) out.push({ title: 'Football Channels', items: football });
    if (sports.length) out.push({ title: 'Sports Channels', items: sports });
    return out;
  }).catch(function () { return []; });
}

function popular(opts) {
  return getLive();
}

// Only football channels: these are 24/7 linear channels, so they are always
// "live" and belong under the Sports screen's channel rail rather than mixed
// into fixture leagues.
function getLive() {
  return _load(false).then(function (channels) {
    var out = [];
    for (var i = 0; i < channels.length; i++) {
      var c = channels[i];
      if (c && c.url && _isFootball(c)) out.push(_map(c));
    }
    return out;
  }).catch(function () { return []; });
}

function search(query, page, opts) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  return _load(false).then(function (channels) {
    var out = [];
    for (var i = 0; i < channels.length && out.length < 60; i++) {
      var c = channels[i];
      if (!c || !c.url) continue;
      if (String(c.name || '').toLowerCase().indexOf(q) < 0) continue;
      out.push(_map(c));
    }
    return out;
  }).catch(function () { return []; });
}

function _idOf(url) {
  var s = String(url || '');
  return s.indexOf('sz:') === 0 ? s.slice(3) : s;
}

function _find(id) {
  return _load(true).then(function (channels) {
    for (var i = 0; i < channels.length; i++) {
      if (String(channels[i].id) === id) return channels[i];
    }
    return null;
  });
}

function getDetail(url, opts) {
  var id = _idOf(url);
  return _find(id).then(function (c) {
    if (!c) return null;
    var title = c.name || 'Live channel';
    var ep = { id: url, title: title, number: 1, url: url };
    return {
      id: url, title: title, url: url, cover: c.poster || null,
      description: '24/7 live channel' + (c.country ? ' · ' + c.country : ''),
      status: 'unknown', genres: ['Football Channels'], studios: [],
      type: 'movie', sourceId: SOURCE_ID, episodes: [ep]
    };
  }).catch(function () { return null; });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d ? d.episodes : []; });
}

function getVideoSources(episodeUrl) {
  var id = _idOf(episodeUrl);
  return _find(id).then(function (c) {
    if (!c || !c.url) return [];
    return [{
      url: c.url,
      quality: null,
      label: c.name || 'Live',
      container: 'unknown',
      headers: {
        'User-Agent': UA,
        'Origin': ORIGIN,
        'Referer': ORIGIN + '/'
      },
      kind: 'unknown',
      subtitles: []
    }];
  }).catch(function () { return []; });
}
