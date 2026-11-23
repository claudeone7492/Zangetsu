// MangaDex provider — official public API (https://api.mangadex.org).
// Uses a non-browser User-Agent because MangaDex serves a bot challenge to
// browser-shaped requests on the API host.

var SOURCE_ID = 'mangadex';
var SITE = 'https://mangadex.org';
var API = 'https://api.mangadex.org';
var UPLOADS = 'https://uploads.mangadex.org';
var UA = 'Zangetsu/1.0 (https://github.com/claudeone7492/Zangetsu)';
var CONTENT_RATINGS = 'contentRating%5B%5D=safe&contentRating%5B%5D=suggestive';

function getInfo() {
  return {
    name: 'MangaDex',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/favicon.ico',
    type: 'manga',
    version: '1.0.0'
  };
}

function _headers() {
  return { 'User-Agent': UA, 'Accept': 'application/json' };
}

async function _getJson(url) {
  var res = await fetch(url, { headers: _headers() });
  if (res.status !== 200) throw new Error('MangaDex HTTP ' + res.status + ' ' + url);
  return JSON.parse(res.body || '{}');
}

function _pickTitle(titles) {
  if (!titles) return '';
  var order = ['en', 'ja-ro', 'ja', 'ko', 'zh'];
  for (var i = 0; i < order.length; i++) {
    if (titles[order[i]]) return titles[order[i]];
  }
  var keys = Object.keys(titles);
  return keys.length ? titles[keys[0]] : '';
}

function _coverUrl(manga) {
  var rels = manga.relationships || [];
  for (var i = 0; i < rels.length; i++) {
    if (rels[i].type === 'cover_art' && rels[i].attributes && rels[i].attributes.fileName) {
      return UPLOADS + '/covers/' + manga.id + '/' + rels[i].attributes.fileName + '.256.jpg';
    }
  }
  return null;
}

function _toItem(m) {
  return {
    id: m.id,
    title: _pickTitle(m.attributes && m.attributes.title),
    cover: _coverUrl(m),
    url: SITE + '/title/' + m.id,
    type: 'manga'
  };
}

async function _searchPage(query, page, extra) {
  var limit = 24;
  var offset = (Math.max(1, page || 1) - 1) * limit;
  var url = API + '/manga?limit=' + limit + '&offset=' + offset +
    '&includes%5B%5D=cover_art&' + CONTENT_RATINGS +
    '&order%5BfollowedCount%5D=desc';
  if (query) url += '&title=' + encodeURIComponent(query);
  if (extra) url += extra;
  var data = await _getJson(url);
  return (data.data || []).map(_toItem);
}

async function search(query, page, opts) {
  var out = await _searchPage(String(query || '').trim(), page, '');
  console.log('mangadex search count: ' + out.length);
  return out;
}

async function getHome(opts) {
  var popular = await _searchPage('', 1, '');
  var latest = await _searchPage('', 1, '&order%5BfollowedCount%5D=asc');
  return [
    { title: 'Popular', items: popular },
    { title: 'Latest', items: latest }
  ];
}

function _parseChapterNumber(value) {
  if (value == null || value === '') return null;
  var n = parseFloat(String(value).replace(/[^0-9.]/g, ''));
  return isNaN(n) ? null : n;
}

async function _chapters(mangaId) {
  var byNumber = {};
  var order = [];
  var limit = 500;
  for (var offset = 0; offset < 3000; offset += limit) {
    var url = API + '/manga/' + mangaId + '/feed?limit=' + limit + '&offset=' + offset +
      '&order%5Bchapter%5D=asc&includeExternalUrl=0';
    var data = await _getJson(url);
    var list = data.data || [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      var a = c.attributes || {};
      if (a.externalUrl || !a.pages) continue;
      var num = _parseChapterNumber(a.chapter);
      var key = num == null ? c.id : String(num);
      var lang = a.translatedLanguage || '';
      // MangaDex usually carries several languages per chapter. Keep one
      // readable copy, preferring English.
      var existing = byNumber[key];
      if (existing && (existing.lang === 'en' || lang !== 'en')) continue;
      var title = a.title ? String(a.title) : '';
      var label = 'Chapter ' + (a.chapter || '?');
      if (lang && lang !== 'en') label += ' [' + lang + ']';
      if (title) label += ' - ' + title;
      var entry = {
        id: c.id,
        title: label,
        number: num,
        url: SITE + '/chapter/' + c.id,
        date: a.publishAt || '',
        lang: lang
      };
      if (!existing) order.push(key);
      byNumber[key] = entry;
    }
    if (list.length < limit) break;
  }
  var out = order.map(function (key) { return byNumber[key]; });
  out.sort(function (a, b) {
    if (a.number == null && b.number == null) return 0;
    if (a.number == null) return -1;
    if (b.number == null) return 1;
    return a.number - b.number;
  });
  return out;
}

async function getDetail(url) {
  var id = String(url).match(/\/title\/([^\/?#]+)/);
  id = id ? id[1] : String(url);
  var data = await _getJson(API + '/manga/' + id +
    '?includes%5B%5D=cover_art&includes%5B%5D=author&includes%5B%5D=artist');
  var m = data.data;
  if (!m) throw new Error('MangaDex title not found');
  var a = m.attributes || {};
  var authors = [];
  var rels = m.relationships || [];
  for (var i = 0; i < rels.length; i++) {
    if ((rels[i].type === 'author' || rels[i].type === 'artist') && rels[i].attributes && rels[i].attributes.name) {
      if (authors.indexOf(rels[i].attributes.name) === -1) authors.push(rels[i].attributes.name);
    }
  }
  var genres = [];
  var tags = a.tags || [];
  for (var t = 0; t < tags.length; t++) {
    var name = _pickTitle(tags[t].attributes && tags[t].attributes.name);
    if (name) genres.push(name);
  }
  var desc = '';
  if (a.description) desc = a.description.en || a.description.ja || Object.values(a.description)[0] || '';
  var chapters = await _chapters(id);
  console.log('mangadex detail: title=' + _pickTitle(a.title) + ' chapters=' + chapters.length);
  return {
    id: id,
    sourceId: SOURCE_ID,
    title: _pickTitle(a.title),
    cover: _coverUrl(m),
    url: SITE + '/title/' + id,
    description: desc,
    status: a.status || 'unknown',
    authors: authors,
    genres: genres,
    chapters: chapters,
    type: 'manga'
  };
}

function getChapters(url) {
  var id = String(url).match(/\/title\/([^\/?#]+)/);
  return _chapters(id ? id[1] : String(url));
}

async function getPages(chapterUrl) {
  var id = String(chapterUrl).match(/\/chapter\/([^\/?#]+)/);
  id = id ? id[1] : String(chapterUrl);
  var data = await _getJson(API + '/at-home/server/' + id);
  var base = data.baseUrl;
  var hash = data.chapter && data.chapter.hash;
  var files = (data.chapter && data.chapter.data) || [];
  if (!base || !hash || !files.length) throw new Error('MangaDex chapter has no pages');
  var out = [];
  for (var i = 0; i < files.length; i++) {
    out.push({
      url: base + '/data/' + hash + '/' + files[i],
      index: i,
      headers: { 'Referer': SITE + '/' }
    });
  }
  console.log('mangadex pages: ' + out.length);
  return out;
}

function getChapterContent() {
  return { text: 'MangaDex is a manga-only source.', nextUrl: null };
}
