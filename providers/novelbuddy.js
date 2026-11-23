// NovelBuddy provider — https://novelbuddy.me
// Next.js site backed by https://api.novelbuddy.me. Pages embed their state in
// __NEXT_DATA__; the chapters endpoint returns the complete archive and chapter
// bodies ship inside initialChapter.content.

var SOURCE_ID = 'novelbuddy';
var SITE = 'https://novelbuddy.me';
var API = 'https://api.novelbuddy.me';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelBuddy', lang: 'en', baseUrl: SITE,
    logo: SITE + '/favicon.ico', type: 'novel', version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }
function _abs(href) { return absUrl(href || '', SITE); }
function _next(html) {
  var m = String(html || '').match(/<script id="__NEXT_DATA__" type="application\/json">([\s\S]*?)<\/script>/i);
  if (!m) return null;
  try { return JSON.parse(m[1]); } catch (e) { return null; }
}

function _blockText(html) {
  var s = String(html || '')
    .replace(/<script[\s\S]*?<\/script>/gi, '')
    .replace(/<style[\s\S]*?<\/style>/gi, '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|h[1-6]|li|tr|blockquote)>/gi, '\n\n')
    .replace(/<[^>]+>/g, '');
  s = s.replace(/&#x([0-9a-fA-F]+);/g, function(_, h) { return String.fromCodePoint(parseInt(h, 16)); })
    .replace(/&#(\d+);/g, function(_, d) { return String.fromCodePoint(parseInt(d, 10)); })
    .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'").replace(/&hellip;/g, '…').replace(/&mdash;/g, '—');
  return s.replace(/\r/g, '').replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n').trim();
}

function _item(it) {
  return {
    id: it.id || it.slug, title: it.name || it.title || '',
    cover: it.cover || null, url: _abs(it.url || ''),
    author: (it.authors && it.authors[0] && it.authors[0].name) || '',
    description: _blockText(it.summary || ''), status: it.status || '', type: 'novel'
  };
}

function getHome() {
  return fetch(SITE + '/home', { headers: { 'Referer': REFERER } }).then(function(r) {
    var d = _next(r.body || '');
    var pp = d && d.props && d.props.pageProps || {};
    var shelves = [
      ['Popular', pp.popularItems],
      ['Trending', pp.trendingItems],
      ['Latest', (pp.latest && pp.latest.items) || pp.latest],
      ['Rising', pp.risingItems],
      ['Top Updates', pp.topUpdateItems]
    ];
    var out = [];
    for (var i = 0; i < shelves.length; i++) {
      var items = (shelves[i][1] || []).map(_item);
      if (items.length) out.push({ title: shelves[i][0], items: items });
    }
    return out;
  });
}

function search(query, page) {
  var q = String(query || '').trim();
  var u = SITE + '/search?q=' + encodeURIComponent(q).replace(/%20/g, '+') +
    (page > 1 ? '&page=' + page : '');
  return fetch(u, { headers: { 'Referer': REFERER } }).then(function(r) {
    var d = _next(r.body || '');
    var pp = d && d.props && d.props.pageProps || {};
    return (pp.ssrItems || []).map(_item);
  });
}

function _chapterObj(c) {
  return {
    id: c.id || c.slug, title: c.name || c.title || '',
    number: c.number != null ? c.number : null,
    url: _abs(c.url || ''), date: c.updated_at || c.updatedAt || ''
  };
}

function getDetail(url) {
  return fetch(url, { headers: { 'Referer': REFERER } }).then(function(r) {
    var d = _next(r.body || '');
    var pp = d && d.props && d.props.pageProps || {};
    var m = pp.initialManga || {};
    var api = fetch(API + '/titles/' + encodeURIComponent(m.id || '') + '/chapters', {
      headers: { 'Referer': REFERER, 'Accept': 'application/json' }
    }).then(function(ar) {
      try {
        var j = JSON.parse(ar.body || '{}');
        return (j.data && j.data.chapters || []).map(_chapterObj);
      } catch (e) { return (m.chapters || []).map(_chapterObj); }
    });
    return api.then(function(list) {
      list.sort(function(a, b) { return (a.number || 0) - (b.number || 0); });
      return {
        id: m.id || m.slug || '', sourceId: SOURCE_ID, title: m.name || '',
        cover: m.cover || null, url: _abs(m.url || url),
        author: (m.authors && m.authors[0] && m.authors[0].name) || '',
        authors: (m.authors || []).map(function(a) { return a.name; }),
        status: m.status || '', description: _blockText(m.summary || ''),
        genres: (m.genres || []).map(function(g) { return g.name; }),
        chapters: list, type: 'novel'
      };
    });
  });
}

function getChapters(url) { return getDetail(url).then(function(d) { return d.chapters; }); }
function getPages() { return []; }

function getChapterContent(chapterUrl) {
  return fetch(chapterUrl, { headers: { 'Referer': REFERER } }).then(function(r) {
    var d = _next(r.body || '');
    var pp = d && d.props && d.props.pageProps || {};
    var c = pp.initialChapter || {};
    var n = pp.nextChapter;
    return { text: _blockText(c.content || ''), nextUrl: n ? _abs(n.url || '') : null };
  });
}

function getText(chapterUrl) { return getChapterContent(chapterUrl); }
