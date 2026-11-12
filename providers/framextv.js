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

// The provider ids the backend can fan a stream out to. Fetched once per
// session: the list is static, and re-reading it on every play would add a
// round-trip to playback start.
var _providerIdsCache = null;
function _providerIds() {
  if (_providerIdsCache) return Promise.resolve(_providerIdsCache);
  return _get('/api/providers').then(function (j) {
    var list = (j && j.providers) || [];
    var ids = [];
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id) ids.push(list[i].id);
    }
    _providerIdsCache = ids;
    return ids;
  }).catch(function () { return []; });
}

// A stream request that answers null instead of throwing, so one dead provider
// in the fan-out can't reject the whole batch.
function _streamOnce(path) {
  return _get(path).then(function (j) { return j || null; })
    .catch(function () { return null; });
}

// episodeUrl is `kind:id` (movie) or `kind:id:season:episode` (tv/anime).
//
// The backend fans a title out to ~25 upstream providers and answers with
// whichever one it picked, the relays it recommends (`alternates`), and any
// providers that failed (`errors`). The default answer alone is a single
// provider's mirrors, so a title the picked provider can't serve returns
// nothing even though others can. This queries the default first, then every
// other provider in parallel, and merges everything into one source list.
function getVideoSources(episodeUrl) {
  var parts = String(episodeUrl).split(':');
  var kind = parts[0] || 'movie';
  var id = parts[1];
  var base = '/api/stream?type=' + kind + '&id=' + id;
  if (parts.length >= 4) base += '&season=' + parts[2] + '&episode=' + parts[3];

  return _streamOnce(base).then(function (first) {
    var primary = (first && first.provider) || null;
    // The top-level subtitle list belongs to whichever provider answered, so
    // it is the fallback for a source that carried none of its own.
    var topSubs = _mapSubtitles(first && first.subtitles);

    var out = [];
    var seen = {};
    function add(list, providerId, subs) {
      if (!list) return;
      for (var i = 0; i < list.length; i++) {
        var s = list[i];
        if (!s || !s.url || seen[s.url]) continue;
        seen[s.url] = 1;
        var own = _mapSubtitles(s.subtitles);
        out.push({
          url: s.url,
          quality: s.quality || null,
          label: _label(providerId, s),
          container: _container(s.type, s.url),
          headers: { 'User-Agent': UA, 'Referer': 'https://framextv.cc/' },
          kind: s.audio === 'dub' ? 'dub' : (s.audio === 'sub' ? 'sub' : 'unknown'),
          subtitles: own.length ? own : subs
        });
      }
    }
    add(first && first.sources, primary, topSubs);

    // Every provider except the one that already answered: the backend's own
    // relays first, then the full list. De-duplicated so a relay that is also
    // in the list is only asked once.
    var wanted = [];
    var wantedSeen = {};
    function want(pid) {
      if (!pid || pid === primary || wantedSeen[pid]) return;
      wantedSeen[pid] = 1; wanted.push(pid);
    }
    var alts = (first && first.alternates) || [];
    for (var a = 0; a < alts.length; a++) want(alts[a]);

    return _providerIds().then(function (ids) {
      for (var k = 0; k < ids.length; k++) want(ids[k]);
      var jobs = [];
      for (var w = 0; w < wanted.length; w++) {
        (function (pid) {
          jobs.push(_streamOnce(base + '&provider=' + encodeURIComponent(pid))
            .then(function (j) {
              if (j && j.success) add(j.sources, pid, topSubs);
            }));
        })(wanted[w]);
      }
      return Promise.all(jobs).then(function () { return out; });
    });
  }).catch(function () { return []; });
}

function _label(provider, s) {
  var bits = [];
  if (provider) bits.push('frameXTV · ' + provider);
  if (s.server) bits.push(s.server);
  if (s.quality) bits.push(s.quality);
  if (s.hasMultipleAudio || (s.audioTracks && s.audioTracks.length > 1)) {
    bits.push('multi-audio');
  }
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
