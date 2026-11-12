// VidLink provider — https://vidlink.pro
//
// vidlink.pro resolves a TMDB id to direct MP4 renditions. The id must first
// be "encrypted" by the public enc-dec.app helper (its `/api/enc-vidlink`
// endpoint), whose output is opaque and per-request; the player API then
// returns a `qualities` map of signed CDN URLs. Browse/search/metadata come
// from the keyless Cinemeta catalogue add-on (IMDb id -> TMDB id).
//
// The CDN URLs are signed and anti-hotlink gated, so playback depends on the
// device's own network/headers (the app's player supplies them); the API path
// itself is keyless and verified live.

var SITE = 'https://vidlink.pro';
var ENC = 'https://enc-dec.app/api/enc-vidlink?text=';
var CINEMETA = 'https://v3-cinemeta.strem.io';
var SOURCE_ID = 'vidlink';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';

function _headers(extra) {
  var h = { 'User-Agent': UA, 'Accept': 'application/json, text/plain, */*' };
  if (extra) for (var k in extra) if (extra.hasOwnProperty(k)) h[k] = extra[k];
  return h;
}

function _get(url, extra) {
  return fetch(url, { headers: _headers(extra) }).then(function (r) {
    if (!r.ok) throw new Error('vidlink: HTTP ' + r.status + ' for ' + url);
    try { return JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('vidlink: bad JSON from ' + url); }
  });
}

function getInfo() {
  return {
    name: 'VidLink', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'movie', version: '1.0.0'
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
function _encrypt(tmdb) {
  return _get(ENC + encodeURIComponent(String(tmdb))).then(function (j) {
    if (!j || !j.result) throw new Error('vidlink: encrypt failed');
    return String(j.result);
  });
}

function getVideoSources(episodeUrl) {
  var parts = String(episodeUrl).split(':');
  var kind = parts[0] || 'movie';
  var tmdb = parts[1];
  if (!tmdb || tmdb === 'null') return Promise.resolve([]);

  return _encrypt(tmdb).then(function (token) {
    var path;
    if (kind === 'tv') {
      if (parts.length < 4) return [];
      path = '/api/b/tv/' + token + '/' + parts[2] + '/' + parts[3];
    } else {
      path = '/api/b/movie/' + token;
    }
    return _get(SITE + path, { 'Referer': SITE + '/' }).then(function (j) {
      var stream = (j && j.stream) || {};
      var qualities = stream.qualities || {};
      var captions = stream.captions || j.captions || [];
      var subs = _mapCaptions(captions);
      var out = [];
      for (var h in qualities) {
        if (!qualities.hasOwnProperty(h)) continue;
        var q = qualities[h];
        if (!q || !q.url) continue;
        out.push({
          url: q.url,
          quality: (String(h).length ? String(h) + 'p' : null),
          label: 'VidLink · ' + (q.codecName ? q.codecName + ' ' : '') + h + 'p',
          container: _container(q.type, q.url),
          headers: { 'User-Agent': UA, 'Referer': SITE + '/' },
          kind: 'unknown', subtitles: subs
        });
      }
      // Highest quality first.
      out.sort(function (a, b) {
        return (parseInt(String(b.quality), 10) || 0) - (parseInt(String(a.quality), 10) || 0);
      });
      return out;
    });
  });
}

function _container(type, url) {
  var t = String(type || '').toLowerCase();
  if (t === 'hls' || t === 'm3u8') return 'hls';
  if (t === 'mp4' || t === 'file') return 'mp4';
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0) return 'hls';
  if (u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}

function _mapCaptions(list) {
  var out = [];
  if (!list || !list.length) return out;
  for (var i = 0; i < list.length; i++) {
    var c = list[i];
    if (!c || !c.url) continue;
    out.push({
      url: c.url,
      lang: c.lang || c.language || 'und',
      label: c.label || c.language || null,
      format: _subFormat(c.url)
    });
  }
  return out;
}

function _subFormat(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.srt') >= 0) return 'srt';
  if (u.indexOf('.vtt') >= 0) return 'vtt';
  return null;
}
