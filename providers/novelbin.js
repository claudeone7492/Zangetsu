// NovelBin provider — https://novelbin.cc
// Server-rendered webnovel site ("civic" theme). novelbin.com/.me are dead
// (Cloudflare 503, empty body); novelbin.cc is the live mirror and is readable
// from both the app's Dart client and Node.
//
// Novel-type provider:
//   browse  → the four homepage registers (featured / activity / completed /
//             top) share one `a.civic-book-row` card shape.
//   search  → /search?keyword=… renders the same cards.
//   detail  → /book/<slug>/ carries schema.org JSON-LD (title/author/genres/
//             description) plus a fact grid (status) and a book id we use to
//             pull the *full* chapter list from /ajax/chapter-list.
//   chapter → /book/<slug>/chapter-N renders the text in #chr-content.

var SOURCE_ID = 'novelbin';
var SITE = 'https://novelbin.cc';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'NovelBin',
    lang: 'en',
    baseUrl: SITE,
    logo: SITE + '/favicon.ico',
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

function _slug(url) {
  var m = String(url).match(/\/book\/([^\/?#]+)/);
  return m ? m[1] : String(url);
}

// One card shape is reused by the homepage registers and the search page:
//   <a href="/book/<slug>/" title="Title" class="civic-book-row …">
//     <img src="/files/image/<slug>.jpg" alt="Cover of Title">
//     <span class="civic-book-main"><h3>Title</h3>
//       <span class="civic-book-author">Author</span>
//       <span class="civic-book-genre">Genre</span></span> …
function _parseCards(html) {
  var out = [];
  var seen = {};
  var re = /<a[^>]+href="(\/book\/[^"?#]+)"[^>]*class="[^"]*civic-book-row[^"]*"[^>]*>([\s\S]*?)<\/a>/g;
  var rows = _all(html, re);
  for (var i = 0; i < rows.length; i++) {
    var link = absUrl(rows[i][1], SITE);
    if (seen[link]) continue;
    seen[link] = true;
    var block = rows[i][2];
    var titleM = block.match(/<h3[^>]*>([\s\S]*?)<\/h3>/i);
    var imgM = block.match(/<img[^>]+src="([^"]+)"/i);
    var authorM = block.match(/civic-book-author[^>]*>([\s\S]*?)<\/span>/i);
    var genreM = block.match(/civic-book-genre[^>]*>([\s\S]*?)<\/span>/i);
    out.push({
      id: _slug(link),
      title: titleM ? _clean(titleM[1]) : '',
      cover: imgM ? absUrl(imgM[1], SITE) : null,
      url: link,
      author: authorM ? _clean(authorM[1]) : '',
      description: genreM ? _clean(genreM[1]) : '',
      type: 'novel'
    });
  }
  return out;
}

function _get(url) {
  return fetch(url, {
    headers: {
      'Accept': 'text/html,application/xhtml+xml',
      'Referer': REFERER
    }
  });
}

// The homepage is a set of <section class="civic-register"> blocks, each with
// an <h2> register name and its own card list.
function _homeSections(html) {
  var sections = [];
  var re = /<section[^>]*class="[^"]*civic-register[^"]*"[\s\S]*?(?=<section[^>]*class="[^"]*civic-register|<\/main>|$)/g;
  var blocks = _all(html, re);
  for (var i = 0; i < blocks.length; i++) {
    var block = blocks[i][0];
    var hM = block.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i);
    var title = hM ? _clean(hM[1]) : ('Register ' + (i + 1));
    var items = _parseCards(block);
    if (items.length) sections.push({ title: title, items: items });
  }
  return sections;
}

function getHome(opts) {
  opts = opts || {};
  return _get(SITE + '/').then(function(r) {
    if (r.status !== 200) {
      console.log('novelbin home HTTP ' + r.status);
      return [];
    }
    var sections = _homeSections(r.body || '');
    if (sections.length === 0) {
      // Fall back to a single flat rail if the register markup changed.
      var items = _parseCards(r.body || '');
      if (items.length) sections.push({ title: 'Latest', items: items });
    }
    return sections;
  });
}

function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  var url = q
    ? SITE + '/search?keyword=' + encodeURIComponent(q)
    : SITE + '/allvisit/';
  console.log('novelbin search url: ' + url);
  return _get(url).then(function(r) {
    var results = _parseCards(r.body || '');
    console.log('novelbin search count: ' + results.length);
    return results;
  });
}

function _jsonLd(html) {
  var re = /<script[^>]+type="application\/ld\+json"[^>]*>([\s\S]*?)<\/script>/gi;
  var blocks = _all(html, re);
  for (var i = 0; i < blocks.length; i++) {
    try {
      var obj = JSON.parse(blocks[i][1]);
      if (obj && obj['@type'] === 'Book') return obj;
    } catch (e) { /* not the block we want */ }
  }
  return null;
}

function _chapterList(html, url) {
  // Preferred: the full list from the book's chapter-list endpoint, keyed by
  // the numeric book id embedded in the add-to-bookcase button.
  var idM = html.match(/addToBookcase\((\d+)\)/);
  var fromAjax = idM
    ? _get(SITE + '/ajax/chapter-list/?bookid=' + idM[1]).then(function(r) {
        try {
          var data = JSON.parse(r.body || 'null');
          if (data && data.chapters && data.chapters.length) {
            return data.chapters.map(function(c, i) {
              return _chapter(c.url, c.title, c.index != null ? c.index : i + 1);
            });
          }
        } catch (e) { /* fall through to inline */ }
        return _inlineChapters(html);
      })
    : Promise.resolve(_inlineChapters(html));
  return fromAjax.then(function(list) {
    if (!list || !list.length) throw new Error('no chapters for ' + url);
    return list;
  });
}

function _chapter(href, title, num) {
  var link = absUrl(href, SITE);
  var t = _clean(title || '');
  if (!t) {
    var m = link.match(/chapter-([0-9]+)/i);
    t = m ? 'Chapter ' + m[1] : 'Chapter';
  }
  return {
    id: _slug(link) + '#' + (link.match(/chapter-([^\/?#]+)/) || [, ''])[1],
    title: t,
    number: num != null ? num : null,
    url: link,
    date: ''
  };
}

function _inlineChapters(html) {
  var out = [];
  var re = /<a[^>]+href="(\/book\/[^"]+\/chapter-[0-9]+)"[^>]*>([\s\S]*?)<\/a>/gi;
  var rows = _all(html, re);
  var seen = {};
  for (var i = 0; i < rows.length; i++) {
    var link = absUrl(rows[i][1], SITE);
    if (seen[link]) continue;
    seen[link] = true;
    // Anchor body is <span>NNN</span><strong>Title</strong>…
    var strongM = rows[i][2].match(/<strong[^>]*>([\s\S]*?)<\/strong>/i);
    var numM = link.match(/chapter-([0-9]+)/i);
    out.push(_chapter(rows[i][1], strongM ? strongM[1] : '', numM ? parseInt(numM[1], 10) : null));
  }
  return out;
}

function _normalizeStatus(s) {
  s = String(s || '').toLowerCase();
  if (s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('complete') !== -1) return 'completed';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

function getDetail(url) {
  console.log('novelbin detail url: ' + url);
  return _get(url).then(function(r) {
    var html = r.body || '';
    var ld = _jsonLd(html) || {};

    var titleM = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i);
    var title = _clean(ld.name || (titleM ? titleM[1] : ''));

    var imgM = html.match(/<img[^>]+src="(\/files\/image\/[^"]+)"/i);
    var cover = ld.image || (imgM ? absUrl(imgM[1], SITE) : null);

    var authorM = html.match(/class="civic-author"[^>]*>([\s\S]*?)<\/p>/i);
    var author = _clean(ld.author ? ld.author.name : (authorM ? authorM[1] : ''));

    var genres = [];
    if (ld.genre) {
      genres = Array.isArray(ld.genre) ? ld.genre.slice() : [ld.genre];
    }
    if (genres.length === 0) {
      var taxM = html.match(/civic-taxonomy-links[^>]*>([\s\S]*?)<\/div>/i);
      if (taxM) {
        genres = _all(taxM[1], /<a[^>]*>([\s\S]*?)<\/a>/gi).map(function(m) { return _clean(m[1]); })
          .filter(function(g) { return g; });
      }
    }

    var statusM = html.match(/<dt>\s*Status\s*<\/dt>\s*<dd>([\s\S]*?)<\/dd>/i);
    var status = _normalizeStatus(statusM ? statusM[1] : '');

    var description = _clean(ld.description || '');
    if (!description) {
      var synM = html.match(/civic-detail-summary[\s\S]*?<p[^>]*>([\s\S]*?)<\/p>/i);
      description = synM ? _clean(synM[1]) : '';
    }

    return _chapterList(html, url).then(function(chapters) {
      console.log('novelbin detail: title=' + title + ' chapters=' + chapters.length
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
  console.log('novelbin chapter url: ' + chapterUrl);
  return _get(chapterUrl).then(function(r) {
    var html = r.body || '';
    var bodyM = html.match(/<div[^>]+id="chr-content"[^>]*>([\s\S]*?)<\/div>/i);
    var content = bodyM ? bodyM[1] : '';
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

    // Next-chapter link — an anchor whose text is exactly "Next".
    var nextUrl = null;
    var nextM = _all(html, /<a[^>]+href="([^"]+)"[^>]*>\s*(?:<[^>]+>\s*)*Next\s*<\/a>/gi);
    if (nextM.length) nextUrl = absUrl(nextM[0][1], SITE);
    if (!nextUrl) {
      var bumpM = String(chapterUrl).match(/^(.*\/chapter-)(\d+)\/?$/i);
      if (bumpM) nextUrl = bumpM[1] + (parseInt(bumpM[2], 10) + 1);
    }

    console.log('novelbin chapter chars=' + text.length);
    return { text: text, nextUrl: nextUrl };
  });
}
