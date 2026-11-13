// Novelight provider — https://novelight.net
// Server-rendered webnovel site (Django). novelight.com just bounces to a
// lander; .net is the real host and is readable from the app's client and Node.
//
// Novel-type provider:
//   browse  → homepage sections (Popular / New Realeses / Recently added) and
//             /catalog/ (a full, paginated catalogue) share one card shape:
//             `a.manga-item`, `a.manga-line-item` or `.new-realeses__item`.
//   search  → /ajax/search-live?search=… returns {"html": "<cards>"}.
//   detail  → /book/<slug>/ carries the synopsis, tags, status/author/genres
//             and a book id; the *full* chapter list comes from
//             /book/ajax/chapter-pagination?book_id=<id>&page=N (50/page).
//   chapter → /book/ajax/read-chapter/<id> returns {"content": "<html>"}.

var SOURCE_ID = 'novelight';
var SITE = 'https://novelight.net';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'Novelight',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/static/core/img/favicon.ico',
    type: 'novel',
    version: '1.0.0'
  };
}

function _clean(s) {
  return htmlText(s || '').replace(/\s+/g, ' ').trim();
}

function _all(html, re) {
  var out = [];
  var m;
  re.lastIndex = 0;
  while ((m = re.exec(html)) !== null) {
    out.push(m);
    if (m.index === re.lastIndex) re.lastIndex++;
  }
  return out;
}

function _get(url) {
  return fetch(url, {
    headers: {
      'Accept': 'text/html,application/xhtml+xml',
      'Referer': REFERER,
      'X-Requested-With': 'XMLHttpRequest'
    }
  });
}

function _slug(url) {
  var m = String(url).match(/\/book\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

// Novelight reuses one card body across every listing surface:
//   <a href="/book/<slug>" class="manga-item|manga-list-item|manga-line-item|new-realeses__item …">
//     <img src="/media/book/poster/…" alt="Title"> … <div class="title">Title</div>
function _parseCards(html) {
  var out = [];
  var seen = {};
  var re = /<a[^>]+href="(\/book\/[^"?#]+)"[^>]*class="[^"]*(?:manga-list-item|manga-line-item|manga-item|new-realeses__item)[^"]*"[^>]*>([\s\S]*?)<\/a>/g;
  var rows = _all(html, re);
  for (var i = 0; i < rows.length; i++) {
    var link = absUrl(rows[i][1], SITE);
    if (seen[link]) continue;
    seen[link] = true;
    var block = rows[i][2];
    var imgM = block.match(/<img[^>]+src="([^"]+)"[^>]*(?:alt="([^"]*)")?/i);
    var titleM = block.match(/class="title[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    var cover = imgM ? absUrl(imgM[1], SITE) : null;
    var title = titleM ? _clean(titleM[1]) : (imgM && imgM[2] ? _clean(imgM[2]) : '');
    out.push({
      id: _slug(link),
      title: title,
      cover: cover,
      url: link,
      type: 'novel'
    });
  }
  return out;
}

function _catalog(page) {
  var url = SITE + '/catalog/' + (page && page > 1 ? '?page=' + page : '');
  return _get(url).then(function(r) {
    return _parseCards(r.body || '');
  });
}

function getHome(opts) {
  opts = opts || {};
  return _get(SITE + '/').then(function(r) {
    var html = r.body || '';
    var sections = [];
    var seenTitles = {};
    // Each <section class="section"> carries an <h2> name and its own cards.
    var re = /<section[^>]*class="[^"]*\bsection\b[^"]*"[^>]*>([\s\S]*?)<\/section>/g;
    var blocks = _all(html, re);
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i][1];
      var hM = block.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i);
      var title = hM ? _clean(hM[1]) : '';
      if (!title || seenTitles[title]) continue;
      var items = _parseCards(block);
      if (items.length) {
        seenTitles[title] = true;
        sections.push({ title: title, items: items });
      }
    }
    return sections;
  }).catch(function(e) {
    console.log('novelight home failed: ' + e);
    return _catalog(1).then(function(items) {
      return items.length ? [{ title: 'Catalogue', items: items }] : [];
    });
  });
}

function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  if (!q) return _catalog(page);
  var url = SITE + '/ajax/search-live?search=' + encodeURIComponent(q);
  console.log('novelight search url: ' + url);
  return _get(url).then(function(r) {
    var data;
    try {
      data = JSON.parse(r.body || 'null');
    } catch (e) {
      return _parseCards(r.body || '');
    }
    var results = _parseCards(data && data.html ? data.html : '');
    console.log('novelight search count: ' + results.length);
    return results;
  });
}

function _bookId(html) {
  var m = html.match(/BOOK_ID\s*=\s*["']?(\d+)/);
  return m ? m[1] : null;
}

function _chapter(href, title, num) {
  var link = absUrl(href, SITE);
  var t = _clean(title || '');
  if (!t) t = 'Chapter ' + (num != null ? num : '');
  return {
    id: 'nl:' + (link.match(/chapter\/(\d+)/) || [, ''])[1],
    title: t,
    number: num != null ? num : null,
    url: link,
    date: ''
  };
}

function _parseChapterLinks(html) {
  var out = [];
  var re = /<a[^>]+href="(\/book\/chapter\/(\d+))"[^>]*class="[^"]*\bchapter\b[^"]*"[^>]*>([\s\S]*?)<\/a>/g;
  var rows = _all(html, re);
  for (var i = 0; i < rows.length; i++) {
    var block = rows[i][3];
    var titleM = block.match(/class="title"[^>]*>([\s\S]*?)<\/div>/i);
    var id = parseInt(rows[i][2], 10);
    out.push(_chapter(rows[i][1], titleM ? titleM[1] : '', id));
  }
  return out;
}

function _allChapters(html) {
  var id = _bookId(html);
  if (!id) {
    return Promise.resolve(_parseChapterLinks(html));
  }
  // The detail page inlines only the last 10; the pagination endpoint returns
  // 50 chapters per page with no total, so page until a short/empty page.
  var PER_PAGE = 50;
  var MAX_PAGES = 100;
  var collected = [];
  var seen = {};

  function fetchPage(page) {
    return _get(SITE + '/book/ajax/chapter-pagination?book_id=' + id + '&page=' + page)
      .then(function(r) {
        var data;
        try { data = JSON.parse(r.body || 'null'); } catch (e) { data = null; }
        var items = _parseChapterLinks(data && data.html ? data.html : (r.body || ''));
        for (var k = 0; k < items.length; k++) {
          if (!seen[items[k].url]) { seen[items[k].url] = true; collected.push(items[k]); }
        }
        if (items.length >= PER_PAGE && page < MAX_PAGES) return fetchPage(page + 1);
        return collected;
      })
      .catch(function(e) {
        console.log('novelight chapter page ' + page + ' failed: ' + e);
        return collected;
      });
  }

  return fetchPage(1).then(function() {
    if (collected.length === 0) return _parseChapterLinks(html);
    // Pagination returns newest-first; the reader wants oldest-first.
    collected.reverse();
    for (var i = 0; i < collected.length; i++) collected[i].number = i + 1;
    return collected;
  });
}

function _normalizeStatus(s) {
  s = String(s || '').toLowerCase();
  if (s.indexOf('releasing') !== -1 || s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('complete') !== -1) return 'completed';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

function _miniInfo(html, label) {
  // <div class="item"><div class="sub-header">Label</div><div class="info">…</div>
  var re = new RegExp(
    '<div class="sub-header">\\s*' + label + '\\s*</div>\\s*<div class="info">([\\s\\S]*?)</div>',
    'i'
  );
  var m = html.match(re);
  return m ? m[1] : '';
}

function _linksIn(chunk) {
  return _all(chunk, /<a[^>]*>([\s\S]*?)<\/a>/gi).map(function(m) { return _clean(m[1]); })
    .filter(function(x) { return x; });
}

function getDetail(url) {
  console.log('novelight detail url: ' + url);
  return _get(url).then(function(r) {
    var html = r.body || '';
    var titleM = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var title = titleM ? _clean(titleM[1]) : '';

    var bgM = html.match(/background-image:\s*url\((\/media\/book\/poster\/[^)]+)\)/i);
    var cover = bgM ? absUrl(bgM[1], SITE) : null;
    if (!cover) {
      var imgM = html.match(/<img[^>]+src="(\/media\/book\/poster\/[^"]+)"/i);
      cover = imgM ? absUrl(imgM[1], SITE) : null;
    }

    // Synopsis is the first text-info section (paragraphs).
    var synM = html.match(/<section[^>]*class="[^"]*text-info[^"]*"[^>]*>([\s\S]*?)<\/section>/i);
    var description = synM ? _clean(synM[1]) : '';

    var status = _normalizeStatus(_miniInfo(html, 'Status'));
    var author = _clean(_miniInfo(html, 'Author'));
    var genres = _linksIn(_miniInfo(html, 'Genres'));
    if (genres.length === 0) {
      var tagM = html.match(/<section[^>]*class="[^"]*tags[^"]*"[^>]*>([\s\S]*?)<\/section>/i);
      if (tagM) genres = _linksIn(tagM[1]);
    }

    return _allChapters(html).then(function(chapters) {
      console.log('novelight detail: title=' + title + ' chapters=' + chapters.length
        + ' status=' + status + ' genres=' + genres.length);
      return {
        id: _slug(url),
        sourceId: SOURCE_ID,
        title: title,
        cover: cover,
        url: url,
        author: author,
        authors: author ? [author] : [],
        status: status,
        description: description,
        genres: genres,
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
  console.log('novelight chapter url: ' + chapterUrl);
  var idM = String(chapterUrl).match(/\/book\/chapter\/(\d+)/);
  var id = idM ? idM[1] : null;
  var api = id
    ? SITE + '/book/ajax/read-chapter/' + id
    : chapterUrl;
  return _get(api).then(function(r) {
    var html;
    try {
      var data = JSON.parse(r.body || 'null');
      html = data && data.content ? data.content : '';
    } catch (e) {
      html = r.body || '';
    }
    html = html.replace(/<script[\s\S]*?<\/script>/gi, '');
    html = html.replace(/<ins[\s\S]*?<\/ins>/gi, '');

    // Body blocks are <div> per paragraph (with the occasional <strong> heading).
    var parts = [];
    var dm = /<div[^>]*>([\s\S]*?)<\/div>/gi;
    var m;
    while ((m = dm.exec(html)) !== null) {
      var t = _clean(m[1]);
      if (t) parts.push(t);
    }
    var text;
    if (parts.length) {
      text = parts.join('\n\n');
    } else {
      text = _clean(html.replace(/<br\s*\/?>/gi, '\n'));
    }

    // Next chapter: the chapter page's right-arrow button links to it.
    var nextUrl = null;
    if (id) nextUrl = SITE + '/book/chapter/' + (parseInt(id, 10) + 1);

    console.log('novelight chapter chars=' + text.length);
    return { text: text, nextUrl: nextUrl };
  });
}
