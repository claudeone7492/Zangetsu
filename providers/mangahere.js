// MangaHere — https://www.mangahere.cc
// Classic server-rendered reader. Search and detail are plain HTML; the
// chapter image list comes from the site's own chapterfun.ashx endpoint as a
// packed JS array, which we unpack locally before extracting the CDN URLs.

var SOURCE_ID = 'mangahere';
var SITE = 'https://www.mangahere.cc';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'MangaHere',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/favicon.ico',
    type: 'manga',
    version: '1.0.0'
  };
}

function _clean(s) { return htmlText(s || '').replace(/\s+/g, ' ').trim(); }

function _all(html, re) {
  var out = [], m;
  re.lastIndex = 0;
  while ((m = re.exec(html)) !== null) {
    out.push(m);
    if (m.index === re.lastIndex) re.lastIndex++;
  }
  return out;
}

function _abs(url) {
  if (!url) return '';
  if (/^https?:\/\//i.test(url)) return url;
  if (url.indexOf('//') === 0) return 'https:' + url;
  return SITE + (url.charAt(0) === '/' ? '' : '/') + url;
}

function _slug(url) {
  var m = String(url).match(/\/manga\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

function _cards(html) {
  var out = [], seen = {};
  var list = _all(html, /<a[^>]+href="(\/manga\/[^"\/]+\/)"[^>]*title="([^"]*)"[^>]*>\s*<img[^>]+src="([^"]+)"/g);
  for (var i = 0; i < list.length; i++) {
    var url = _abs(list[i][1]);
    if (seen[url]) continue;
    seen[url] = true;
    out.push({ id: _slug(url), title: _clean(list[i][2]), cover: _abs(list[i][3]), url: url, type: 'manga' });
  }
  if (!out.length) {
    var titles = _all(html, /<p[^>]*class="[^"]*manga-list-[14]-item-title[^"]*"[^>]*>\s*<a[^>]+href="(\/manga\/[^"\/]+\/)"[^>]*>([\s\S]*?)<\/a>/g);
    for (var j = 0; j < titles.length; j++) {
      var u = _abs(titles[j][1]);
      if (seen[u]) continue;
      seen[u] = true;
      out.push({ id: _slug(u), title: _clean(titles[j][2]), cover: null, url: u, type: 'manga' });
    }
  }
  return out;
}

function getHome(opts) {
  return fetch(SITE + '/', { headers: { Referer: REFERER } }).then(function (r) {
    var items = _cards(r.body || '');
    return items.length ? [{ title: 'Popular', items: items }] : [];
  });
}

function search(query, page) {
  page = page || 1;
  var q = String(query || '').trim();
  var url = SITE + '/search.php?name=' + encodeURIComponent(q) + (page > 1 ? '&page=' + page : '');
  console.log('mangahere search url: ' + url);
  return fetch(url, { headers: { Referer: REFERER } }).then(function (r) {
    var out = _cards(r.body || '');
    console.log('mangahere search count: ' + out.length);
    return out;
  });
}

function _chapters(html) {
  var out = [], seen = {};
  var list = _all(html, /<a[^>]+href="(\/manga\/[^"]+\/[^"]+\.html)"[^>]*title="([^"]*)"[^>]*>[\s\S]*?<p[^>]*class="title3"[^>]*>([\s\S]*?)<\/p>/g);
  for (var i = 0; i < list.length; i++) {
    var url = _abs(list[i][1]);
    if (seen[url] || /\/c\d+(?:\.[0-9]+)?\/1\.html$/i.test(url) === false) continue;
    seen[url] = true;
    var label = _clean(list[i][3]) || _clean(list[i][2]);
    var numM = label.match(/(?:ch\.?|chapter)\s*([0-9]+(?:\.[0-9]+)?)/i) || url.match(/\/c([0-9]+(?:\.[0-9]+)?)\//i);
    var num = numM ? parseFloat(numM[1]) : null;
    out.push({ id: _slug(url) + '__' + (num != null ? num : out.length + 1), title: label, number: num, url: url, date: '' });
  }
  if (!out.length) {
    var r = html.match(/<a[^>]+class="detail-info-right-read"[^>]+href="([^"]+)"[^>]*title="([^"]*)"/i) ||
      html.match(/<a[^>]+href="([^"]+)"[^>]+class="detail-info-right-read"[^>]*title="([^"]*)"/i);
    if (r) {
      var ru = _abs(r[1]);
      var rn = ru.match(/\/c([0-9]+(?:\.[0-9]+)?)\//i);
      var rnum = rn ? parseFloat(rn[1]) : 1;
      out.push({ id: _slug(ru) + '__' + rnum, title: _clean(r[2]) || ('Chapter ' + rnum), number: rnum, url: ru, date: '' });
    }
  }
  out.sort(function (a, b) {
    if (a.number == null && b.number == null) return 0;
    if (a.number == null) return -1;
    if (b.number == null) return 1;
    return a.number - b.number;
  });
  return out;
}

function getDetail(url) {
  console.log('mangahere detail url: ' + url);
  return fetch(url, { headers: { Referer: REFERER } }).then(function (r) {
    var html = r.body || '';
    var titleM = html.match(/<span[^>]+class="detail-info-right-title-font"[^>]*>([\s\S]*?)<\/span>/i)
      || html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var coverM = html.match(/<img[^>]+class="detail-info-cover-img"[^>]+src="([^"]+)"/i);
    var descM = html.match(/<p[^>]+class="fullcontent"[^>]*>([\s\S]*?)<\/p>/i);
    var statusM = html.match(/<span[^>]+class="detail-info-right-title-tip"[^>]*>([\s\S]*?)<\/span>/i);
    var authors = [], am = html.match(/<p[^>]+class="detail-info-right-author"[^>]*>([\s\S]*?)<\/p>/i);
    if (am) authors.push(_clean(am[1]));
    var genres = [], gm = _all(html, /<p[^>]+class="detail-info-right-tag-list"[^>]*>([\s\S]*?)<\/p>/g);
    for (var i = 0; i < gm.length; i++) {
      var gl = _all(gm[i][1], /<a[^>]*>([\s\S]*?)<\/a>/g);
      for (var j = 0; j < gl.length; j++) {
        var g = _clean(gl[j][1]);
        if (g && genres.indexOf(g) === -1) genres.push(g);
      }
    }
    var chapters = _chapters(html);
    console.log('mangahere detail: title=' + (titleM ? _clean(titleM[1]) : '') + ' chapters=' + chapters.length);
    return {
      id: _slug(url),
      sourceId: SOURCE_ID,
      title: titleM ? _clean(titleM[1]) : '',
      cover: coverM ? _abs(coverM[1]) : null,
      url: url,
      author: authors.join(', '),
      status: statusM ? _clean(statusM[1]).toLowerCase() : 'unknown',
      description: descM ? _clean(descM[1]) : '',
      genres: genres,
      chapters: chapters,
      type: 'manga'
    };
  });
}

function getChapters(url) {
  return fetch(url, { headers: { Referer: REFERER } }).then(function (r) {
    return _chapters(r.body || '');
  });
}

function _unpack(js) {
  var m = String(js).match(/\}\('([\s\S]*?)',(\d+),(\d+),'([\s\S]*?)'\.split\('\|'\),0,\{\}\)\)/);
  if (!m) return '';
  var p = m[1], a = parseInt(m[2], 10), c = parseInt(m[3], 10), k = m[4].split('|');
  var e = function (n) {
    return (n < a ? '' : e(parseInt(n / a, 10))) + ((n = n % a) > 35 ? String.fromCharCode(n + 29) : n.toString(36));
  };
  for (var i = c - 1; i >= 0; i--) {
    if (k[i]) p = p.replace(new RegExp('\\b' + e(i) + '\\b', 'g'), k[i]);
  }
  return p;
}

function _imagesFromPayload(body) {
  var code = _unpack(body);
  var pixM = code.match(/pix="([^"]+)"/);
  var pvM = code.match(/pvalue=\[([\s\S]*?)\]/);
  if (!pixM || !pvM) return [];
  var names = _all(pvM[1], /"([^"]+)"/g);
  var out = [];
  for (var i = 0; i < names.length; i++) {
    var name = names[i][1];
    if (!/\.(?:jpg|jpeg|png|webp)(?:\?|$)/i.test(name)) continue;
    var url = /^https?:\/\//i.test(name) ? name : (name.indexOf('//') === 0 ? 'https:' + name : pixM[1] + name);
    if (url.indexOf('//') === 0) url = 'https:' + url;
    if (out.indexOf(url) === -1) out.push(url);
  }
  return out;
}

async function getPages(chapterUrl) {
  console.log('mangahere pages url: ' + chapterUrl);
  var res = await fetch(chapterUrl, { headers: { Referer: REFERER } });
  if (res.status !== 200) throw new Error('chapter HTTP ' + res.status);
  var html = res.body || '';
  var cidM = html.match(/var chapterid\s*=\s*([0-9]+)/i);
  var countM = html.match(/var imagecount\s*=\s*([0-9]+)/i);
  if (!cidM) throw new Error('Chapter has no id');
  var cid = cidM[1];
  var count = countM ? parseInt(countM[1], 10) : 1;
  var base = chapterUrl.replace(/\/[^\/]*$/, '');
  var pages = [], seen = {};
  var next = 1;
  async function worker() {
    while (next <= count) {
      var page = next++;
      var url = base + '/chapterfun.ashx?cid=' + cid + '&page=' + page + '&key=';
      try {
        var r = await fetch(url, { headers: { Referer: chapterUrl } });
        if (r.status !== 200) continue;
        var imgs = _imagesFromPayload(r.body || '');
        for (var i = 0; i < imgs.length; i++) {
          if (seen[imgs[i]]) continue;
          seen[imgs[i]] = true;
          pages.push({ url: imgs[i], index: pages.length, headers: { Referer: chapterUrl } });
        }
      } catch (e) {}
    }
  }
  var workers = [];
  for (var w = 0; w < 8; w++) workers.push(worker());
  await Promise.all(workers);
  console.log('mangahere pages count: ' + pages.length);
  if (!pages.length) throw new Error('Chapter has no images');
  return pages;
}

function getChapterContent(chapterUrl) {
  return { text: 'MangaHere is a manga-only source.', nextUrl: null };
}
