// NetShort provider — https://netshort.com
//
// NetShort is a short-drama service: a "show" (shortPlay) is a vertical series
// of one-to-three-minute episodes. The site is a Next.js app whose server-side
// render embeds the whole page payload as JSON inside `self.__next_f.push([1,
// "…"])` calls — the same data the browser receives on a plain GET. That is
// what this provider reads: no scraping of markup, no auth, no keys.
//
//   GET /                          → the whole catalogue, as `{"list":[…]}` rails
//   GET <shortPlayNameUrl>         → show detail + `videoEpisodeInfos` (the
//                                    episode list, each with an `isLock` flag)
//
// Only the freely-available episodes are offered. NetShort gates the rest
// behind its coin wall and serves their streams solely from a private signed
// API (an RSA-wrapped AES key per request) that this provider deliberately does
// NOT talk to — locked episodes are simply listed as unavailable, never
// unlocked. The one public stream the detail page exposes (its `playVoucher`)
// is the show's first, free episode.
//
// URLs carry what the next call needs: a show is `ns:<shortPlayId>|<path>` and
// an episode is `ns:<shortPlayId>|<path>|<episodeNo>`. Verified live.

var SOURCE_ID = 'netshort';
var SITE = 'https://netshort.com';
var UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function _headers() {
  return {
    'User-Agent': UA,
    'Accept': 'text/html,application/xhtml+xml',
    'Referer': SITE + '/'
  };
}

function _get(url) {
  return fetch(url, { headers: _headers() }).then(function (r) {
    if (!r.ok) throw new Error('NetShort: HTTP ' + r.status);
    return String(r.body || '');
  });
}

function getInfo() {
  return {
    name: 'NetShort', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'movie', version: '1.0.0'
  };
}

// ── RSC payload extraction ──────────────────────────────────────────────────
// Reassemble the page payload from the `self.__next_f.push([1,"…"])` stream.
// Each argument is a JSON string literal holding one slice of the document.
function _payload(html) {
  var out = '';
  var re = /self\.__next_f\.push\(\[1,\s*("(?:[^"\\]|\\.)*")\]\)/g;
  var m;
  while ((m = re.exec(html))) {
    try { out += JSON.parse(m[1]); } catch (e) { /* skip malformed slice */ }
  }
  return out;
}

// Bracket-match the JSON value that follows `key` (an array or object) and
// return it parsed, or null when the key is absent.
function _valueAfter(text, key) {
  var at = text.indexOf('"' + key + '":');
  if (at < 0) return null;
  var open = at + key.length + 3;
  var oc = text.charAt(open);
  if (oc !== '[' && oc !== '{') return null;
  var cc = oc === '[' ? ']' : '}';
  var depth = 0, inStr = false, esc = false;
  for (var i = open; i < text.length; i++) {
    var c = text.charAt(i);
    if (inStr) {
      if (esc) esc = false;
      else if (c === '\\') esc = true;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === oc) depth++;
    else if (c === cc) {
      depth--;
      if (depth === 0) {
        try { return JSON.parse(text.slice(open, i + 1)); } catch (e) { return null; }
      }
    }
  }
  return null;
}

// ── mapping ─────────────────────────────────────────────────────────────────
function _showUrl(shortPlayId, path) { return 'ns:' + shortPlayId + '|' + (path || ''); }
function _episodeUrl(shortPlayId, path, episodeNo) {
  return _showUrl(shortPlayId, path) + '|' + episodeNo;
}

function _mapShow(s) {
  if (!s || !s.shortPlayId) return null;
  return {
    id: String(s.shortPlayId),
    title: s.shortPlayNameNoHL || s.shortPlayName || String(s.shortPlayId),
    cover: s.shortPlayCover || null,
    banner: null,
    url: _showUrl(s.shortPlayId, s.shortPlayNameUrl),
    type: 'movie',
    sourceId: SOURCE_ID
  };
}

// The catalogue is embedded as several `{"list":[…]}` rails; collect them all
// and de-duplicate by shortPlayId (the same show can appear in more than one).
function _catalogue(payload) {
  var out = [];
  var seen = {};
  var re = /"list":\[/g;
  var m;
  while ((m = re.exec(payload))) {
    var arr = _valueAfter(payload.slice(m.index), 'list');
    if (!arr || !arr.length) continue;
    for (var i = 0; i < arr.length; i++) {
      var it = arr[i];
      if (!it || !it.shortPlayId || seen[it.shortPlayId]) continue;
      seen[it.shortPlayId] = 1;
      var mapped = _mapShow(it);
      if (mapped) out.push(mapped);
    }
  }
  return out;
}

function _homeCatalogue() {
  return _get(SITE + '/').then(function (html) {
    return _catalogue(_payload(html));
  });
}

function getHome(opts) {
  return _homeCatalogue().then(function (items) {
    if (!items.length) return [];
    return [{ title: 'NetShort Short Dramas', items: items }];
  }).catch(function () { return []; });
}

function popular(opts) {
  return _homeCatalogue().then(function (items) {
    return items.slice(0, 40);
  }).catch(function () { return []; });
}

// ── shorts feed ─────────────────────────────────────────────────────────────
// NetShort is a short-drama service end to end, so the whole public catalogue
// is the feed.
function getShorts(opts) {
  return _homeCatalogue().catch(function () { return []; });
}

// ── search ──────────────────────────────────────────────────────────────────
// NetShort's keyword search is served only by the private signed API, so this
// filters the public catalogue by title instead. It is exact enough for a
// short-drama library (every show is in the home payload) and needs no key.
function search(query, page, opts) {
  var q = String(query || '').toLowerCase().trim();
  if (!q) return Promise.resolve([]);
  return _homeCatalogue().then(function (items) {
    return items.filter(function (m) {
      return String(m.title).toLowerCase().indexOf(q) !== -1;
    });
  }).catch(function () { return []; });
}

// ── detail / episodes ───────────────────────────────────────────────────────
function _parseShow(url) {
  var s = String(url || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  return { shortPlayId: parts[0], path: parts[1] };
}

function _detail(showUrl) {
  var p = _parseShow(showUrl);
  if (!p.shortPlayId || !p.path) return Promise.resolve(null);
  return _get(SITE + p.path).then(function (html) {
    var payload = _payload(html);
    var name = _stringAfter(payload, 'shortPlayNameNoHL') ||
               _stringAfter(payload, 'shortPlayName');
    var cover = _stringAfter(payload, 'shortPlayCover');
    var intro = _stringAfter(payload, 'shotIntroduce');
    var labels = _valueAfter(payload, 'labelList') || [];
    var infos = _valueAfter(payload, 'videoEpisodeInfos') || [];
    var voucher = _stringAfter(payload, 'playVoucher');

    var genres = [];
    for (var i = 0; i < labels.length; i++) {
      if (labels[i] && labels[i].labelName) genres.push(labels[i].labelName);
    }

    var episodes = [];
    for (var j = 0; j < infos.length; j++) {
      var e = infos[j];
      var n = e.episodeNo != null ? e.episodeNo : (j + 1);
      episodes.push({
        id: String(e.episodeId || n),
        title: 'Episode ' + n,
        number: n,
        url: _episodeUrl(p.shortPlayId, p.path, n),
        thumbnail: e.episodeCover || null
      });
    }

    return {
      id: p.shortPlayId,
      title: name || p.shortPlayId,
      url: _showUrl(p.shortPlayId, p.path),
      cover: cover || null, banner: null,
      description: htmlText(intro || ''),
      status: 'unknown', genres: genres, studios: [], type: 'movie',
      sourceId: SOURCE_ID,
      episodes: episodes,
      // The detail page embeds its current (free) episode's stream.
      _voucher: voucher || null
    };
  });
}

function getDetail(url, opts) {
  return _detail(url);
}

function getEpisodes(url, opts) {
  return _detail(url).then(function (d) { return d ? d.episodes : []; });
}

// ── streams ─────────────────────────────────────────────────────────────────
// episodeUrl is `ns:<shortPlayId>|<path>|<episodeNo>`. Only the show's first
// episode has a publicly-served stream; later free episodes and all locked ones
// are coin-gated behind the private API and are reported as no source.
function getVideoSources(episodeUrl) {
  var s = String(episodeUrl || '');
  var i = s.indexOf(':');
  if (i >= 0) s = s.slice(i + 1);
  var parts = s.split('|');
  var path = parts[1], episodeNo = parts[2];
  if (!parts[0] || !path || !episodeNo) return Promise.resolve([]);
  if (String(episodeNo) !== '1') return Promise.resolve([]);
  return _detail(_showUrl(parts[0], path)).then(function (d) {
    var video = d && d._voucher;
    if (!video) return [];
    return [{
      url: video,
      quality: null,
      label: (d.title || 'NetShort') + ' · Ep 1',
      container: _container(video),
      headers: { 'User-Agent': UA, 'Referer': SITE + '/' },
      kind: 'unknown',
      subtitles: []
    }];
  }).catch(function () { return []; });
}

function _container(url) {
  var u = String(url || '').toLowerCase();
  if (u.indexOf('.m3u8') >= 0) return 'hls';
  if (u.indexOf('mime_type=video_mp4') >= 0 || u.indexOf('.mp4') >= 0) return 'mp4';
  return 'unknown';
}

// ── scalar readers ──────────────────────────────────────────────────────────
// The payload is one long JSON blob; these pull a scalar by key without a full
// parse (the blob contains values a whole-document parse would reject).
function _stringAfter(text, key) {
  var m = new RegExp('"' + key + '":("(?:[^"\\\\]|\\\\.)*")').exec(text);
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch (e) { return null; }
}
