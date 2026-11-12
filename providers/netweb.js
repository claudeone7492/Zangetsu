// NetWeb gateway provider — https://netweb-cvu7.onrender.com
//
// A keyless streaming gateway: ask for a title, get playable streams,
// artwork and subtitles back as JSON. The gateway fans out to seven upstream
// "providers" (frameXTV, O2TV, ShortDrama, Dramachi, 4KHDHub, FZMovies,
// KissAsian) and returns every HLS/MP4 source it found, each already proxied
// through a worker so the app can play it directly.
//
// Browse/search/metadata come from the keyless Cinemeta catalogue add-on
// (v3-cinemeta.strem.io), which keys titles by IMDb id and exposes the TMDB id
// the gateway's /v1/stream endpoint needs. Verified live.

var GATEWAY = 'https://netweb-cvu7.onrender.com';
var CINEMETA = 'https://v3-cinemeta.strem.io';
var SOURCE_ID = 'netweb';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

function _headers() {
  return { 'User-Agent': UA, 'Accept': 'application/json, text/plain, */*' };
}

function _get(url) {
  return fetch(url, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('netweb: HTTP ' + r.status + ' for ' + url);
    try { return JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('netweb: bad JSON from ' + url); }
  });
}

function getInfo() {
  return {
    name: 'NetWeb', lang: 'en', baseUrl: GATEWAY,
    logo: GATEWAY + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// --- Cinemeta helpers ------------------------------------------------------
// Cinemeta uses 'movie' / 'series'; the gateway wants 'movie' / 'tv'.
function _gwType(kind) { return kind === 'series' ? 'tv' : 'movie'; }

function _mapMeta(x) {
  if (!x || !x.id) return null;
  var kind = (String(x.type) === 'series') ? 'series' : 'movie';
  return {
    id: String(x.id),
    title: x.name || String(x.id),
    cover: x.poster || null,
    banner: x.background || null,
    url: kind + ':' + String(x.id),
    type: 'movie',
    sourceId: SOURCE_ID
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
  // Movies and series are separate catalogues on Cinemeta; merge them.
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
      var cover = m.poster || null;
      var banner = m.background || null;
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
            title: v.name || ('Episode ' + en),
            number: en, season: sn,
            url: 'tv:' + tmdb + ':' + sn + ':' + en,
            thumbnail: v.thumbnail || null,
            date: v.firstAired || v.released || null
          });
        }
        if (!eps.length && tmdb) {
          eps = [{ id: 'tv:' + tmdb + ':1:1', title: 'Episode 1', number: 1,
                   season: 1, url: 'tv:' + tmdb + ':1:1' }];
        }
        return {
          id: String(p.id), title: title, url: 'series:' + p.id,
          cover: cover, banner: banner, description: desc,
          status: 'unknown', genres: genres, studios: [], type: 'movie',
          sourceId: SOURCE_ID, tmdbId: tmdb || null, tmdbIsTv: true,
          imdbId: p.id, episodes: eps
        };
      }

      var ep = { id: 'movie:' + tmdb, title: title, number: 1, url: 'movie:' + tmdb };
      return {
        id: String(p.id), title: title, url: 'movie:' + p.id,
        cover: cover, banner: banner, description: desc,
        status: 'unknown', genres: genres, studios: [], type: 'movie',
        sourceId: SOURCE_ID, tmdbId: tmdb || null, tmdbIsTv: false,
        imdbId: p.id, episodes: [ep]
      };
    });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d.episodes; });
}

// --- Streams ---------------------------------------------------------------
// episodeUrl is `movie:<tmdb>` or `tv:<tmdb>:<season>:<episode>`.
function getVideoSources(episodeUrl) {
  var parts = String(episodeUrl).split(':');
  var kind = parts[0] || 'movie';
  var tmdb = parts[1];
  if (!tmdb || tmdb === 'null') return Promise.resolve([]);
  var path = '/v1/stream?tmdbId=' + encodeURIComponent(tmdb) +
             '&mediaType=' + _gwType(kind);
  if (parts.length >= 4) path += '&season=' + parts[2] + '&episode=' + parts[3];

  return _get(GATEWAY + path).then(function (j) {
    var srcs = (j && j.sources) || [];
    var out = [];
    for (var i = 0; i < srcs.length; i++) {
      var s = srcs[i];
      var d = s && s.data;
      if (!d || !d.stream) continue;
      out.push({
        url: d.stream,
        quality: d.qualityLabel || (d.qualityHeight ? d.qualityHeight + 'p' : d.quality) || null,
        label: s.name || null,
        container: _container(d.type, d.stream),
        headers: d.headers || { 'User-Agent': UA },
        kind: _audioKind(d.language),
        subtitles: _mapSubtitles(d.subtitles)
      });
    }
    return out;
  });
}

function _container(type, url) {
  var t = String(type || '').toLowerCase();
  if (t === 'hls' || t === 'm3u8') return 'hls';
  if (t === 'mp4') return 'mp4';
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0) return 'hls';
  if (u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}

function _audioKind(language) {
  var l = String(language || '').toLowerCase();
  if (l.indexOf('dub') >= 0) return 'dub';
  if (l.indexOf('sub') >= 0) return 'sub';
  return 'unknown';
}

function _mapSubtitles(list) {
  var out = [];
  if (!list || !list.length) return out;
  for (var i = 0; i < list.length; i++) {
    var s = list[i];
    if (!s || !s.url) continue;
    out.push({
      url: s.url,
      lang: s.lang || s.language || 'und',
      label: s.label || s.language || null,
      format: _subFormat(s.url, s.format)
    });
  }
  return out;
}

function _subFormat(url, format) {
  if (format) return format;
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.srt') >= 0) return 'srt';
  if (u.indexOf('.vtt') >= 0) return 'vtt';
  return null;
}
