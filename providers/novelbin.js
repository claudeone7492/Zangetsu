// NovelBin provider — https://novelbin.xyz
//
// The HTML chapter route on novelbin.cc rate-limits aggressively (429 on the
// first chapter read after a detail walk). The same catalogue is served by the
// site's static JSON API on boxnovela.b-cdn.net, which the xyz front end uses:
//
//   lists/popular.json            -> popular cards
//   lists/status_<status>_1.json  -> paged status rails ({data:[...]})
//   lists/search.json             -> full title/slug index (one 7.7 MB fetch)
//   novel/<slug>.json             -> metadata
//   chapters/<novelId>.json       -> full chapter list
//   read/<novelId>/<index>.json   -> chapter HTML (zero-based index)
//
// Every request needs the xyz Origin/Referer or the CDN answers 403.

var SOURCE_ID = 'novelbin';
var SITE = 'https://novelbin.xyz';
var CDN = 'https://boxnovela.b-cdn.net';
var REFERER = SITE + '/';

var _popularCache = null;
var _searchIndex = null;

function getInfo() {
  return {
    name: 'NovelBin',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/favicon.ico',
    type: 'novel',
    version: '2.0.0'
  };
}

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _slug(url) {
  var m = String(url).match(/\/novel\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

function _headers() {
  return {
    'Accept': 'application/json,text/plain,*/*',
    'Referer': REFERER,
    'Origin': SITE
  };
}

function _getJson(path) {
  return fetch(CDN + '/' + path, { headers: _headers() }).then(function(r) {
    if (r.status !== 200) throw new Error(path + ' HTTP ' + r.status);
    return JSON.parse(r.body || 'null');
  });
}

function _card(x) {
  return {
    id: x.slug || String(x.id || ''),
    title: _clean(x.title),
    cover: x.cover || null,
    url: SITE + '/novel/' + (x.slug || x.id),
    type: 'novel'
  };
}

function _popular() {
  if (_popularCache) return Promise.resolve(_popularCache);
  return _getJson('lists/popular.json').then(function(list) {
    _popularCache = Array.isArray(list) ? list.map(_card) : [];
    return _popularCache;
  });
}

function _statusRow(title, status) {
  return _getJson('lists/status_' + status + '_1.json').then(function(payload) {
    var list = payload && Array.isArray(payload.data) ? payload.data : [];
    return list.length ? { title: title, items: list.map(_card) } : null;
  }).catch(function() { return null; });
}

function getHome(opts) {
  opts = opts || {};
  return _popular().then(function(popular) {
    var rows = popular.length ? [{ title: 'Popular', items: popular }] : [];
    return _statusRow('Ongoing', 'ongoing').then(function(sec) {
      if (sec) rows.push(sec);
      return _statusRow('Completed', 'completed');
    }).then(function(sec) {
      if (sec) rows.push(sec);
      return rows;
    });
  });
}

function _searchIndexOnce() {
  if (_searchIndex) return Promise.resolve(_searchIndex);
  return _getJson('lists/search.json').then(function(list) {
    _searchIndex = Array.isArray(list) ? list : [];
    return _searchIndex;
  });
}

function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim().toLowerCase();
  if (!q) return _popular();

  // Most queries hit the small popular rail; only fall back to the full index
  // when it does not, so a common search does not download 7.7 MB.
  return _popular().then(function(popular) {
    var hits = popular.filter(function(x) {
      return x.title.toLowerCase().indexOf(q) !== -1;
    });
    if (hits.length) return hits;
    return _searchIndexOnce().then(function(index) {
      var out = [];
      for (var i = 0; i < index.length && out.length < 30; i++) {
        var x = index[i];
        var title = String(x.title || '');
        var alt = String(x.alternative_titles || '');
        if (title.toLowerCase().indexOf(q) === -1 &&
            alt.toLowerCase().indexOf(q) === -1) continue;
        out.push(_card(x));
      }
      console.log('novelbin search count: ' + out.length);
      return out;
    });
  });
}

function _normalizeStatus(s) {
  s = String(s || '').toLowerCase();
  if (s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('complete') !== -1) return 'completed';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

function _chapters(novelId, list) {
  var out = [];
  for (var i = 0; i < list.length; i++) {
    var c = list[i] || {};
    var index = c.index != null ? c.index : i;
    var num = index + 1;
    out.push({
      id: String(c.id != null ? c.id : novelId + '-' + num),
      title: _clean(c.title) || ('Chapter ' + num),
      number: num,
      url: SITE + '/read/' + novelId + '/chapter-' + num + '?total=' + list.length,
      date: ''
    });
  }
  return out;
}

function getDetail(url) {
  var slug = _slug(url);
  console.log('novelbin detail url: ' + slug);
  return _getJson('novel/' + encodeURIComponent(slug) + '.json').then(function(book) {
    if (!book) throw new Error('novel not found: ' + slug);
    var id = book.id != null ? book.id : slug;
    return _getJson('chapters/' + encodeURIComponent(id) + '.json').then(function(list) {
      var chapters = _chapters(id, Array.isArray(list) ? list : []);
      console.log('novelbin detail: title=' + book.title + ' chapters=' + chapters.length);
      return {
        id: slug,
        sourceId: SOURCE_ID,
        title: _clean(book.title),
        cover: book.cover || null,
        url: SITE + '/novel/' + slug,
        author: _clean(book.author || ''),
        authors: book.author ? [_clean(book.author)] : [],
        status: _normalizeStatus(book.status),
        description: _clean(book.description || ''),
        genres: Array.isArray(book.genres) ? book.genres.slice() : [],
        chapters: chapters,
        type: 'novel'
      };
    });
  });
}

function getChapters(url) {
  return getDetail(url).then(function(d) { return d.chapters; });
}

function getPages() {
  return [];
}

function getChapterContent(chapterUrl) {
  var m = String(chapterUrl).match(/\/read\/([^\/?#]+)\/chapter-([0-9]+)/i);
  if (!m) return Promise.reject('novelbin: not a chapter url: ' + chapterUrl);
  var novelId = m[1];
  var num = parseInt(m[2], 10);
  var zero = Math.max(0, num - 1);

  return _getJson('read/' + encodeURIComponent(novelId) + '/' + zero + '.json').then(function(ch) {
    var content = ch && ch.content ? String(ch.content) : '';
    content = content.replace(/<script[\s\S]*?<\/script>/gi, '');
    content = content.replace(/<ins[\s\S]*?<\/ins>/gi, '');

    var paragraphs = [];
    var pm = /<p[^>]*>([\s\S]*?)<\/p>/gi;
    var p;
    while ((p = pm.exec(content)) !== null) {
      var t = _clean(p[1]);
      if (t) paragraphs.push(t);
    }
    var text = paragraphs.length
      ? paragraphs.join('\n\n')
      : _clean(content.replace(/<br\s*\/?>/gi, '\n'));

    var totalM = String(chapterUrl).match(/[?&]total=([0-9]+)/);
    var total = totalM ? parseInt(totalM[1], 10)
      : (ch && ch.total_chapters != null ? parseInt(ch.total_chapters, 10) : null);
    var nextUrl = total && num < total
      ? SITE + '/read/' + novelId + '/chapter-' + (num + 1)
      : '';
    console.log('novelbin chapter chars=' + text.length);
    return { text: text, nextUrl: nextUrl };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
