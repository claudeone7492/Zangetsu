// vidsrc.pm provider — https://vidsrc.pm
//
// vidsrc.pm fronts a set of "vidora" mirrors behind a public player key. Its
// own API returns a worker-proxied URL that rejects non-browser clients
// (HTTP 403), so the real HLS master is unwrapped from the worker's `url`
// query param and replayed through the NetWeb gateway's open proxy, which
// passes it through unchanged. Browse/search/metadata come from the keyless
// Cinemeta catalogue add-on (IMDb id -> TMDB id). Verified live.

var SITE = 'https://vidsrc.pm';
var PROXY = 'https://netweb-cvu7.onrender.com/proxy?url=';
var CINEMETA = 'https://v3-cinemeta.strem.io';
var SOURCE_ID = 'vidsrc';
// Public player key shipped in vidsrc.pm's own bundle (assets/main-*.js).
var PLAYER_KEY = 'f3b72e73c80c9a996574379798703796a1936efa3516a7105cb0e43048b46b5a';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

function _headers() {
  return { 'User-Agent': UA, 'Accept': 'application/json, text/plain, */*' };
}

function _get(url, extra) {
  var h = _headers();
  if (extra) for (var k in extra) if (extra.hasOwnProperty(k)) h[k] = extra[k];
  return fetch(url, { headers: h }).then(function (r) {
    if (!r.ok) throw new Error('vidsrc: HTTP ' + r.status + ' for ' + url);
    try { return JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('vidsrc: bad JSON from ' + url); }
  });
}

function getInfo() {
  return {
    name: 'VidSrc', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.svg', type: 'movie', version: '1.0.0'
  };
}

// --- Cinemeta helpers ------------------------------------------------------
function _mapMeta(x) {
  if (!x || !x.id) return null;
  var kind = (String(x.type) === 'series') ? 'series' : 'movie';
  return {
    id: String(x.id), title: x.name || String(x.id),
    cover: x.poster || null, banner: x.background || null,
    url: kind + ':' + String(x.id), type: 'movie', sourceId: SOURCE_ID
  };
}

function _mapMetas(list) {
  var out = [];
  if (!list || !list.length) return out;
  for (var i = 0; i < list.length; i++) {
    var m = _mapMeta(list[i]);
    if (m) out.push(m);
  }
  return out;
}

function _catalog(mediaType, catalogId, query) {
  var path = '/catalog/' + mediaType + '/' + catalogId;
  if (query) path += '/search=' + encodeURIComponent(String(query));
  return _get(CINEMETA + path + '.json').then(function (j) {
    return _mapMetas((j && j.metas) || []);
  }).catch(function () { return []; });
}

function search(query, page, opts) {
  var q = String(query || '');
  if (!q) return Promise.resolve([]);
  return Promise.all([
    _catalog('movie', 'top', q),
    _catalog('series', 'top', q)
  ]).then(function (lists) {
    var seen = {}, out = [];
    for (var i = 0; i < lists.length; i++) {
      for (var k = 0; k < lists[i].length; k++) {
        var it = lists[i][k];
        if (seen[it.url]) continue;
        seen[it.url] = 1;
        out.push(it);
      }
    }
    return out;
  });
}

function getHome(opts) {
  var rails = [
    { title: 'Popular Movies', mediaType: 'movie', catalogId: 'top' },
    { title: 'Popular Series', mediaType: 'series', catalogId: 'top' },
    { title: 'Top Rated', mediaType: 'movie', catalogId: 'imdbRating' }
  ];
  return Promise.all(rails.map(function (r) {
    return _catalog(r.mediaType, r.catalogId, null).then(function (items) {
      return items.length ? { title: r.title, items: items } : null;
    });
  })).then(function (sections) {
    var out = [];
    for (var i = 0; i < sections.length; i++) if (sections[i]) out.push(sections[i]);
    return out;
  }).catch(function () { return []; });
}

function popular(opts) { return _catalog('movie', 'top', null); }

// --- Detail ----------------------------------------------------------------
function _parseUrl(url) {
  var s = String(url);
  var i = s.indexOf(':');
  if (i < 0) return { kind: 'movie', id: s };
  return { kind: s.slice(0, i), id: s.slice(i + 1) };
}

function getDetail(url, opts) {
  var p = _parseUrl(url);
  var mediaType = p.kind === 'series' ? 'series' : 'movie';
  return _get(CINEMETA + '/meta/' + mediaType + '/' + encodeURIComponent(p.id) + '.json')
    .then(function (j) {
      var m = (j && j.meta) || {};
      var tmdb = m.moviedb_id || m.moviedbId || null;
      var title = m.name || String(p.id);
      var desc = htmlText(m.description || '');
      var genres = m.genres || m.genre || [];

      if (mediaType === 'series') {
        var vids = m.videos || [];
        var eps = [];
        for (var i = 0; i < vids.length; i++) {
          var v = vids[i];
          var sn = v.season, en = (v.episode != null ? v.episode : v.number);
          if (sn == null || en == null) continue;
          eps.push({
            id: 'tv:' + tmdb + ':' + sn + ':' + en,
            title: v.name || ('Episode ' + en), number: en, season: sn,
            url: 'tv:' + tmdb + ':' + sn + ':' + en,
            thumbnail: v.thumbnail || null, date: v.firstAired || v.released || null
          });
        }
        if (!eps.length && tmdb) {
          eps = [{ id: 'tv:' + tmdb + ':1:1', title: 'Episode 1', number: 1,
                   season: 1, url: 'tv:' + tmdb + ':1:1' }];
        }
        return {
          id: String(p.id), title: title, url: 'series:' + p.id,
          cover: m.poster || null, banner: m.background || null,
          description: desc, status: 'unknown', genres: genres, studios: [],
          type: 'movie', sourceId: SOURCE_ID, tmdbId: tmdb || null,
          tmdbIsTv: true, imdbId: p.id, episodes: eps
        };
      }

      return {
        id: String(p.id), title: title, url: 'movie:' + p.id,
        cover: m.poster || null, banner: m.background || null,
        description: desc, status: 'unknown', genres: genres, studios: [],
        type: 'movie', sourceId: SOURCE_ID, tmdbId: tmdb || null,
        tmdbIsTv: false, imdbId: p.id,
        episodes: [{ id: 'movie:' + tmdb, title: title, number: 1, url: 'movie:' + tmdb }]
      };
    });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d.episodes; });
}

// --- Streams ---------------------------------------------------------------
// Unwrap the vidora worker's `url` param to reach the real manifest, then send
// it through the gateway proxy (the worker itself 403s a plain client).
function _unwrap(workerUrl) {
  var s = String(workerUrl || '');
  var m = s.match(/[?&]url=([^&]+)/);
  if (m) {
    try { return decodeURIComponent(m[1]); } catch (e) { /* fall through */ }
  }
  return s;
}

function _proxied(url) { return PROXY + encodeURIComponent(String(url)); }

function getVideoSources(episodeUrl) {
  var parts = String(episodeUrl).split(':');
  var kind = parts[0] || 'movie';
  var tmdb = parts[1];
  if (!tmdb || tmdb === 'null') return Promise.resolve([]);

  var path;
  if (kind === 'tv') {
    if (parts.length < 4) return Promise.resolve([]);
    path = '/api/vidora/v1/tv/' + tmdb + '/' + parts[2] + '/' + parts[3];
  } else if (kind === 'anime') {
    if (parts.length < 4) return Promise.resolve([]);
    path = '/api/vidora/v1/anime/' + tmdb + '/' + parts[2] + '/' + parts[3];
  } else {
    path = '/api/vidora/v1/movie/' + tmdb;
  }

  return _get(SITE + path, { 'x-player-key': PLAYER_KEY, 'Referer': SITE + '/' })
    .then(function (j) {
      if (!j || !j.result || !j.sources || !j.sources.length) return [];
      var s = j.sources[0];
      var base = _proxied(_unwrap(s.url));
      var tracks = (s.tracks || []).filter(function (t) { return t && t.file; });
      var subs = [];
      for (var i = 0; i < tracks.length; i++) {
        subs.push({
          url: tracks[i].file,
          lang: _langCode(tracks[i].label || tracks[i].language || 'und'),
          label: tracks[i].label || tracks[i].language || null,
          format: _subFormat(tracks[i].file)
        });
      }

      var out = [];
      var qualities = (s.qualities || []).filter(function (q) { return q && q.url; });
      if (qualities.length > 1) {
        for (var k = 0; k < qualities.length; k++) {
          var q = qualities[k];
          out.push({
            url: _proxied(q.url),
            quality: q.height ? q.height + 'p' : (q.label || null),
            label: 'VidSrc' + (q.height ? ' · ' + q.height + 'p' : ''),
            container: _container(q.url),
            headers: { 'User-Agent': UA },
            kind: 'unknown', subtitles: subs
          });
        }
      } else {
        out.push({
          url: base,
          quality: null,
          label: 'VidSrc',
          container: _container(_unwrap(s.url)),
          headers: { 'User-Agent': UA },
          kind: 'unknown', subtitles: subs
        });
      }
      return out;
    });
}

function _container(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0 || u.indexOf('/pl/') >= 0) return 'hls';
  if (u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}

function _langCode(label) {
  var l = String(label || '').toLowerCase();
  var map = {
    english: 'en', spanish: 'es', french: 'fr', german: 'de', italian: 'it',
    portuguese: 'pt', 'portuguese (br)': 'pt', arabic: 'ar', hindi: 'hi',
    japanese: 'ja', korean: 'ko', chinese: 'zh', russian: 'ru', dutch: 'nl',
    polish: 'pl', turkish: 'tr', indonesian: 'id'
  };
  if (map[l]) return map[l];
  if (l.length === 2) return l;
  return l.slice(0, 2) || 'und';
}

function _subFormat(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.srt') >= 0) return 'srt';
  if (u.indexOf('.vtt') >= 0) return 'vtt';
  return null;
}
