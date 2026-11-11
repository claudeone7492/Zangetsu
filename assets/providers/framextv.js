// frameXTV provider — https://framextv.cc (API: api.framextv.tech, with .cc /
// .xyz / .pro mirrors). Movies, TV and anime, keyed by TMDB id. The backend
// fans out to several upstream "providers" (bowler, giant, sparky, …) and
// returns HLS/MP4 sources plus subtitle tracks. Verified live.

var SOURCE_ID = 'framextv';
var BASES = [
  'https://api.framextv.tech',
  'https://api.framextv.cc',
  'https://api.framextv.xyz',
  'https://api.framextv.pro'
];
var BASE = BASES[0];
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function _headers() {
  return { 'User-Agent': UA, 'Accept': 'application/json, text/plain, */*' };
}

function _get(path) {
  return fetch(BASE + path, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('frameXTV: HTTP ' + r.status);
    try { return JSON.parse(r.body || 'null'); }
    catch (e) { throw new Error('frameXTV: bad JSON (' + r.status + ')'); }
  });
}

function getInfo() {
  return {
    name: 'frameXTV', lang: 'en', baseUrl: 'https://framextv.cc',
    logo: 'https://framextv.cc/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// Search results carry a TMDB id and a media kind. `anime` ids are TMDB tv
// ids but must be streamed through type=anime, so the kind is folded into the
// url (`kind:id`) and split back out by getDetail / getVideoSources.
function _kindOf(x) {
  var t = String((x && x.type) || '').toLowerCase();
  if (t === 'anime') return 'anime';
  if (t === 'tv' || t === 'series') return 'tv';
  return 'movie';
}

function _mapItems(results) {
  var out = [];
  if (!results || !results.length) return out;
  for (var i = 0; i < results.length; i++) {
    var x = results[i];
    if (!x || x.id == null) continue;
    var kind = _kindOf(x);
    out.push({
      id: String(x.id), title: x.title || String(x.id),
      cover: x.poster || x.image || null, banner: x.backdrop || null,
      url: kind + ':' + String(x.id),
      type: kind === 'anime' ? 'anime' : 'movie', sourceId: SOURCE_ID
    });
  }
  return out;
}

function search(query, page, opts) {
  var p = page || 1;
  return _get('/api/search?query=' + encodeURIComponent(String(query || '')) +
              '&page=' + p).then(function (j) {
    return _mapItems((j && j.results) || []);
  });
}

// Browse: /api/home bundles the hero plus named rails; a rail is just a
// search-shaped result page, so one fetch yields every row.
function _home() {
  return _get('/api/home');
}

function getHome(opts) {
  return _home().then(function (j) {
    var rails = (j && j.rails) || {};
    var titles = {
      trending_movies: 'Trending Movies', popular_movies: 'Popular Movies',
      popular_tv: 'Popular Series', popular_anime: 'Popular Anime',
      new_releases: 'New Releases', action_movies: 'Action',
      scifi_movies: 'Sci-Fi', thriller_movies: 'Thriller',
      comedy_movies: 'Comedy', airing_anime: 'Airing Now'
    };
    var out = [];
    for (var key in titles) {
      if (!titles.hasOwnProperty(key)) continue;
      var rail = rails[key];
      var items = _mapItems((rail && rail.results) || []);
      if (items.length) out.push({ title: titles[key], items: items });
    }
    return out;
  }).catch(function () { return []; });
}

function popular(opts) {
  return _home().then(function (j) {
    var rails = (j && j.rails) || {};
    var dr = (opts && opts.dateRange != null) ? opts.dateRange : 7;
    var key = dr <= 1 ? 'trending_movies'
            : (dr <= 30 ? 'popular_movies' : 'new_releases');
    var rail = rails[key] || rails.popular_movies || {};
    return _mapItems((rail && rail.results) || []);
  }).catch(function () { return []; });
}

function _parseUrl(url) {
  var s = String(url);
  var i = s.indexOf(':');
  if (i < 0) return { kind: 'movie', id: s };
  return { kind: s.slice(0, i), id: s.slice(i + 1) };
}

function getDetail(url, opts) {
  var p = _parseUrl(url);
  if (p.kind === 'movie') return _movieDetail(p.id);
  return _tvDetail(p.kind, p.id);
}

function _movieDetail(id) {
  return _get('/api/search?query=' + encodeURIComponent(id) + '&page=1')
    .then(function (j) {
      var results = (j && j.results) || [];
      var hit = null;
      for (var i = 0; i < results.length; i++) {
        if (String(results[i].id) === String(id)) { hit = results[i]; break; }
      }
      hit = hit || { id: id, title: String(id) };
      return {
        id: String(id), title: hit.title || String(id), url: 'movie:' + id,
        cover: hit.poster || hit.image || null, banner: hit.backdrop || null,
        description: htmlText(hit.overview || ''), status: 'unknown',
        genres: [], studios: [], type: 'movie', sourceId: SOURCE_ID,
        episodes: [{ id: 'movie:' + id, title: hit.title || 'Movie',
                     number: 1, url: 'movie:' + id }]
      };
    });
}

function _tvDetail(kind, id) {
  return _get('/api/' + (kind === 'anime' ? 'tv' : 'tv') + '/' + id)
    .then(function (j) {
      var seasons = (j && j.seasons) || [];
      // Load each season's episode list (skip season 0 "Specials" when it
      // carries an implausible episode count — the API reports 300 for GoT).
      var jobs = [];
      for (var i = 0; i < seasons.length; i++) {
        var s = seasons[i];
        var sn = s.season_number;
        if (sn == null) continue;
        jobs.push(_season(kind, id, sn, s.name));
      }
      return Promise.all(jobs).then(function (lists) {
        var eps = [];
        for (var i = 0; i < lists.length; i++) {
          for (var k = 0; k < lists[i].length; k++) eps.push(lists[i][k]);
        }
        if (!eps.length) eps = [{ id: kind + ':' + id, title: j.title || 'Episode 1',
                                  number: 1, url: kind + ':' + id + ':1:1' }];
        return {
          id: String(id), title: (j && j.title) || String(id),
          url: kind + ':' + id, cover: j.poster || null, banner: j.backdrop || null,
          description: htmlText((j && j.overview) || ''), status: 'unknown',
          genres: (j && j.genres) || [], studios: [], type: 'movie',
          sourceId: SOURCE_ID, episodes: eps
        };
      });
    });
}

function _season(kind, id, seasonNumber, seasonName) {
  return _get('/api/tv/' + id + '/season/' + seasonNumber).then(function (j) {
    var raw = (j && j.episodes) || [];
    var out = [];
    for (var i = 0; i < raw.length; i++) {
      var e = raw[i];
      var n = e.episode_number != null ? e.episode_number : (i + 1);
      out.push({
        id: kind + ':' + id + ':' + seasonNumber + ':' + n,
        title: e.name || ('Episode ' + n),
        number: n, season: seasonNumber,
        url: kind + ':' + id + ':' + seasonNumber + ':' + n,
        thumbnail: e.still || null, date: e.air_date || null
      });
    }
    return out;
  }).catch(function () { return []; });
}

function getEpisodes(url, opts) {
  return getDetail(url, opts).then(function (d) { return d.episodes; });
}

// episodeUrl is `kind:id` (movie) or `kind:id:season:episode` (tv/anime).
function getVideoSources(episodeUrl) {
  var parts = String(episodeUrl).split(':');
  var kind = parts[0] || 'movie';
  var id = parts[1];
  var path = '/api/stream?type=' + kind + '&id=' + id;
  if (parts.length >= 4) path += '&season=' + parts[2] + '&episode=' + parts[3];
  return _get(path).then(function (j) {
    if (!j || !j.success || !j.sources || !j.sources.length) return [];
    var topSubs = _mapSubtitles(j.subtitles);
    var out = [];
    for (var i = 0; i < j.sources.length; i++) {
      var s = j.sources[i];
      if (!s || !s.url) continue;
      var subs = _mapSubtitles(s.subtitles);
      out.push({
        url: s.url,
        quality: s.quality || null,
        label: _label(j.provider, s),
        container: _container(s.type, s.url),
        headers: { 'User-Agent': UA, 'Referer': 'https://framextv.cc/' },
        kind: s.audio === 'dub' ? 'dub' : (s.audio === 'sub' ? 'sub' : 'unknown'),
        subtitles: subs.length ? subs : topSubs
      });
    }
    return out;
  });
}

function _label(provider, s) {
  var bits = [];
  if (provider) bits.push('frameXTV · ' + provider);
  if (s.server) bits.push(s.server);
  return bits.join(' · ') || null;
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

function _mapSubtitles(list) {
  var out = [];
  if (!list || !list.length) return out;
  for (var i = 0; i < list.length; i++) {
    var s = list[i];
    if (!s || !s.url) continue;
    out.push({
      url: s.url, lang: s.lang || s.language || 'und',
      label: s.label || s.language || null,
      format: s.format || (String(s.url).indexOf('.srt') >= 0 ? 'srt' : 'vtt')
    });
  }
  return out;
}
