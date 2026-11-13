// MangaBat provider — https://www.mangabats.com (Aatricks/Emaki source port).
//
// Manga-type source. Verified live:
//   * browse  → /manga-list/{hot,new,completed}-manga carousels
//   * search  → /search/story/<q>?page=N (story_item cards)
//   * detail  → manga-info-text header + /api/manga/<slug>/chapters JSON
//   * reader  → .container-chapter-reader <img> list

var SOURCE_ID = 'mangabats';
var SITE = 'https://www.mangabats.com';
var REFERER = SITE + '/';
var LOGO = SITE + '/images/logo-bat.webp';

function getInfo() {
  return {
    name: 'MangaBat',
    lang: 'en',
    baseUrl: SITE,
    logo: LOGO,
    type: 'manga',
    version: '1.0.0'
  };
}

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _normalizeStatus(s) {
  s = (s || '').toLowerCase();
  if (s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('complete') !== -1) return 'completed';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  if (s.indexOf('cancel') !== -1 || s.indexOf('discontinued') !== -1) return 'cancelled';
  return 'unknown';
}

function _slugFromUrl(url) {
  var m = String(url).match(/\/manga\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

// One pass over every `/manga/<slug>` anchor; title from the anchor's title
// attribute (carousels) or the adjacent <img alt> (search cards), cover from
// the thumb URL that embeds the slug.
function _parseCards(html) {
  var out = [];
  var seen = {};
  var re = /<a[^>]+href="https:\/\/www\.mangabats\.com\/manga\/([^"\/]+)"([^>]*)>/g;
  var m;
  while ((m = re.exec(html)) !== null) {
    var slug = m[1];
    if (seen[slug]) continue;
    seen[slug] = true;
    var attrs = m[2] || '';
    var title = '';
    var tm = attrs.match(/title="([^"]+)"/);
    if (tm) title = _clean(tm[1]);
    if (!title) {
      var after = html.slice(m.index + m[0].length, m.index + m[0].length + 400);
      var am = after.match(/alt="([^"]+)"/);
      if (am) title = _clean(am[1]);
      if (!title) {
        var inner = after.match(/^([^<]+)</);
        if (inner) title = _clean(inner[1]);
      }
    }
    var cover = null;
    var cm = html.match(
      new RegExp('(https://img-r[0-9]\\.2xstorage\\.com/thumb/' + slug + '\\.[a-z]+)', 'i')
    );
    if (cm) cover = cm[1];
    out.push({
      id: slug,
      title: title || slug,
      cover: cover,
      url: SITE + '/manga/' + slug,
      type: 'manga'
    });
  }
  return out;
}

async function _homeRow(title, path) {
  var res = await fetch(SITE + '/manga-list/' + path + '?page=1', {
    headers: { Referer: REFERER }
  });
  if (res.status !== 200) {
    console.log('mangabats home row HTTP ' + res.status + ' ' + title);
    return null;
  }
  var items = _parseCards(res.body || '');
  return items.length ? { title: title, items: items } : null;
}

async function getHome(opts) {
  opts = opts || {};
  var rows = [
    { title: 'Popular', path: 'hot-manga' },
    { title: 'New Manga', path: 'new-manga' },
    { title: 'Completed', path: 'completed-manga' }
  ];
  var sections = [];
  for (var i = 0; i < rows.length; i++) {
    try {
      var sec = await _homeRow(rows[i].title, rows[i].path);
      if (sec) sections.push(sec);
    } catch (e) {
      console.log('mangabats home row failed: ' + rows[i].title + ' (' + e + ')');
    }
  }
  return sections;
}

// Search results live inside <div class="panel_story_list"> as .story_item
// blocks with a clean <h3 class="story_name"><a>Title</a>. Scoping to the panel
// keeps the header carousels out of the result set.
function _parseSearchResults(html) {
  var panel = html.indexOf('panel_story_list');
  var scope = panel >= 0 ? html.slice(panel) : html;
  var out = [];
  var seen = {};
  var re = /class="story_item"([\s\S]*?)(?=class="story_item"|<\/div>\s*<\/div>\s*<div class="clear|$)/g;
  var m;
  while ((m = re.exec(scope)) !== null) {
    var blk = m[1];
    var hrefM = blk.match(/href="https:\/\/www\.mangabats\.com\/manga\/([^"\/]+)"/);
    if (!hrefM) continue;
    var slug = hrefM[1];
    if (seen[slug]) continue;
    seen[slug] = true;
    var titleM = blk.match(/class="story_name"[^>]*>\s*<a[^>]*>([\s\S]*?)<\/a>/i)
      || blk.match(/alt="([^"]+)"/i);
    var coverM = blk.match(/src="(https:\/\/img-r[0-9]\.2xstorage\.com\/thumb\/[^"]+)"/i);
    out.push({
      id: slug,
      title: _clean(titleM ? titleM[1] : slug),
      cover: coverM ? coverM[1] : null,
      url: SITE + '/manga/' + slug,
      type: 'manga'
    });
  }
  return out;
}

async function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  var url;
  if (q) {
    url = SITE + '/search/story/' + encodeURIComponent(q.replace(/\s+/g, '_')) + '?page=' + page;
  } else {
    url = SITE + '/manga-list/hot-manga?page=' + page;
  }
  console.log('mangabats search url: ' + url);
  var res = await fetch(url, { headers: { Referer: REFERER } });
  if (res.status !== 200) {
    console.log('mangabats search HTTP ' + res.status);
    return [];
  }
  var body = res.body || '';
  var out = q ? _parseSearchResults(body) : _parseCards(body);
  console.log('mangabats search count: ' + out.length);
  return out;
}

async function _chapters(slug) {
  var api = SITE + '/api/manga/' + slug + '/chapters';
  var out = [];
  try {
    var res = await fetch(api, {
      headers: { Referer: SITE + '/manga/' + slug, Accept: 'application/json' }
    });
    if (res.status !== 200) {
      console.log('mangabats chapters HTTP ' + res.status);
      return out;
    }
    var data = JSON.parse(res.body || '{}');
    var list = (data && data.data && data.data.chapters) || [];
    for (var i = 0; i < list.length; i++) {
      var c = list[i];
      if (!c || !c.chapter_slug) continue;
      out.push({
        id: slug + '__' + c.chapter_slug,
        title: _clean(c.chapter_name || c.chapter_slug),
        number: typeof c.chapter_num === 'number' ? c.chapter_num : null,
        url: SITE + '/manga/' + slug + '/' + c.chapter_slug,
        date: c.updated_at ? String(c.updated_at).substring(0, 10) : ''
      });
    }
  } catch (e) {
    console.log('mangabats chapters failed: ' + e);
  }
  out.sort(function (a, b) {
    if (a.number == null && b.number == null) return 0;
    if (a.number == null) return -1;
    if (b.number == null) return 1;
    return a.number - b.number;
  });
  return out;
}

async function getDetail(url) {
  console.log('mangabats detail url: ' + url);
  var slug = _slugFromUrl(url);
  var res = await fetch(url, { headers: { Referer: REFERER } });
  if (res.status !== 200) throw new Error('detail HTTP ' + res.status);
  var html = res.body || '';

  var titleM = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
  var title = titleM ? _clean(titleM[1]) : '';

  var coverM = html.match(/property="og:image"[^>]+content="([^"]+)"/i);
  var cover = coverM ? coverM[1] : null;

  var authorM = html.match(/Author\(s\):\s*<\/p>\s*([^<]+)/i)
    || html.match(/Author\(s\):\s*([^<]+)/i);
  var author = authorM ? _clean(authorM[1]) : '';

  var statusM = html.match(/Status:\s*<\/p>\s*<p>([^<]+)/i);
  var status = _normalizeStatus(statusM ? _clean(statusM[1]) : '');

  var descM = html.match(/property="og:description"[^>]+content="([^"]*)"/i)
    || html.match(/name="description"[^>]+content="([^"]*)"/i);
  var description = descM ? _clean(descM[1]) : '';

  var genres = [];
  var gm = html.match(/<a[^>]+href="[^"]*\/genre[^"]*"[^>]*>([^<]+)<\/a>/gi) || [];
  for (var g = 0; g < gm.length && genres.length < 10; g++) {
    var gv = _clean((gm[g].match(/>([^<]+)<\/a>/) || [null, ''])[1]);
    if (gv && genres.indexOf(gv) === -1) genres.push(gv);
  }

  var chapters = await _chapters(slug);
  console.log('mangabats detail: title=' + title + ' chapters=' + chapters.length + ' status=' + status);

  return {
    id: slug,
    sourceId: SOURCE_ID,
    title: title,
    cover: cover,
    url: url,
    author: author,
    status: status,
    description: description,
    genres: genres,
    chapters: chapters,
    type: 'manga'
  };
}

async function getChapters(url) {
  return _chapters(_slugFromUrl(url));
}

async function getPages(chapterUrl) {
  console.log('mangabats pages url: ' + chapterUrl);
  var res = await fetch(chapterUrl, { headers: { Referer: REFERER } });
  if (res.status !== 200) throw new Error('chapter HTTP ' + res.status);
  var html = res.body || '';
  var start = html.indexOf('container-chapter-reader');
  var seg = start >= 0 ? html.slice(start, start + 200000) : html;
  var out = [];
  var re = /<img[^>]+src=['"](https?:\/\/[^'"]+)['"]/gi;
  var m;
  var seen = {};
  while ((m = re.exec(seg)) !== null) {
    var src = m[1];
    if (seen[src]) continue;
    if (/mangabats\.com\/images|logo|default_bat/i.test(src)) continue;
    seen[src] = true;
    out.push({ url: src, index: out.length, headers: { Referer: chapterUrl } });
  }
  console.log('mangabats pages count: ' + out.length);
  if (out.length === 0) throw new Error('Chapter has no images');
  return out;
}

function getChapterContent(chapterUrl) {
  return { text: 'MangaBat is a manga-only source.', nextUrl: null };
}
