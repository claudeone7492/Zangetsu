// Inkitt provider — https://www.inkitt.com
// Inkitt exposes a public read API under https://www.inkitt.com/api/1/… (the
// separate api.inkitt.com host no longer resolves). The story page and the
// reader are server-rendered, so chapter lists and chapter text come from HTML.
//
// Novel-type provider:
//   browse  → /api/1/homepage/trending_stories and /api/1/homepage/fandoms
//             return {response:{title, items}} story lists.
//   search  → /api/2/search/blended?q=… groups hits by type; take the "story"
//             group.
//   detail  → /api/1/stories/<id> has title/blurb/author/status/genres; the
//             chapter list is scraped from /stories/<id> (it links every
//             chapter, /stories/<id>/chapters/<n>).
//   chapter → /stories/<id>/chapters/<n> renders the text in
//             <div id="chapterText"> as <p data-content=…>.

var SOURCE_ID = 'inkitt';
var SITE = 'https://www.inkitt.com';
var API = SITE + '/api/1';
var REFERER = SITE + '/';

function getInfo() {
  return {
    name: 'Inkitt',
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

function _get(url, json) {
  return fetch(url, {
    headers: {
      'Accept': json ? 'application/json' : 'text/html,application/xhtml+xml',
      'Referer': REFERER
    }
  });
}

function _parseJson(body) {
  try { return JSON.parse(body || 'null'); } catch (e) { return null; }
}

function _storyUrl(id) {
  return SITE + '/stories/' + id;
}

// Story items come from several endpoints; normalise the shared fields.
function _storyCard(it) {
  if (!it || it.id == null) return null;
  var cover = (it.cover && it.cover.url) || it.small_cover_url || null;
  var author = it.author ? it.author.name
    : (it.user ? (it.user.name || it.user.username) : '');
  return {
    id: String(it.id),
    title: _clean(it.title || ''),
    cover: cover,
    url: _storyUrl(it.id),
    author: _clean(author),
    description: _clean(it.teaser || ''),
    type: 'novel'
  };
}

function _storyList(resp) {
  var out = [];
  var seen = {};
  var items = resp && resp.items ? resp.items : [];
  for (var i = 0; i < items.length; i++) {
    var card = _storyCard(items[i]);
    if (card && !seen[card.id]) { seen[card.id] = true; out.push(card); }
  }
  return out;
}

function getHome(opts) {
  opts = opts || {};
  return Promise.all([
    _get(API + '/homepage/trending_stories', true).then(function(r) {
      return _parseJson(r.body);
    }).catch(function() { return null; }),
    _get(API + '/homepage/fandoms', true).then(function(r) {
      return _parseJson(r.body);
    }).catch(function() { return null; })
  ]).then(function(res) {
    var sections = [];
    var trend = res[0] && res[0].response;
    if (trend) {
      var items = _storyList(trend);
      if (items.length) sections.push({ title: trend.title || 'Trending Stories', items: items });
    }
    var fandoms = res[1] && res[1].response;
    if (fandoms && fandoms.items) {
      var flat = [];
      var seen = {};
      for (var h = 0; h < fandoms.items.length; h++) {
        var hub = fandoms.items[h];
        var stories = hub.stories || [];
        for (var s = 0; s < stories.length; s++) {
          var card = _storyCard(stories[s]);
          if (card && !seen[card.id]) { seen[card.id] = true; flat.push(card); }
        }
      }
      if (flat.length) sections.push({ title: fandoms.title || 'Featured Collections', items: flat });
    }
    console.log('inkitt home sections: ' + sections.length);
    return sections;
  });
}

function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  if (!q) return Promise.resolve([]);
  var url = SITE + '/api/2/search/blended?q=' + encodeURIComponent(q)
    + '&mode=story&per_page=30&page=' + page;
  console.log('inkitt search url: ' + url);
  return _get(url, true).then(function(r) {
    var data = _parseJson(r.body) || {};
    var groups = data.results || [];
    var out = [];
    var seen = {};
    for (var i = 0; i < groups.length; i++) {
      if (groups[i].type !== 'story') continue;
      var items = groups[i].items || [];
      for (var k = 0; k < items.length; k++) {
        var card = _storyCard(items[k]);
        if (card && !seen[card.id]) { seen[card.id] = true; out.push(card); }
      }
    }
    console.log('inkitt search count: ' + out.length);
    return out;
  });
}

function _chaptersFromHtml(html, id) {
  var out = [];
  var seen = {};
  var re = new RegExp('<a[^>]+href="/stories/' + id + '/chapters/(\\d+)"[^>]*>([\\s\\S]*?)</a>', 'g');
  var rows = _all(html, re);
  for (var i = 0; i < rows.length; i++) {
    var n = parseInt(rows[i][1], 10);
    if (seen[n]) continue;
    seen[n] = true;
    // Anchor body: <span>1</span><span>Chapter 1</span> (the second span is the name).
    var spans = _all(rows[i][2], /<span[^>]*>([\s\S]*?)<\/span>/gi).map(function(m) { return _clean(m[1]); });
    var title = spans.length > 1 ? spans[spans.length - 1] : ('Chapter ' + n);
    out.push({
      id: 'inkitt:' + id + ':' + n,
      title: title || ('Chapter ' + n),
      number: n,
      url: SITE + '/stories/' + id + '/chapters/' + n,
      date: ''
    });
  }
  out.sort(function(a, b) { return a.number - b.number; });
  return out;
}

function _normalizeStatus(s) {
  s = String(s || '').toLowerCase();
  if (s.indexOf('complete') !== -1) return 'completed';
  if (s.indexOf('progress') !== -1 || s.indexOf('ongoing') !== -1) return 'ongoing';
  if (s.indexOf('hiatus') !== -1) return 'hiatus';
  return 'unknown';
}

function _storyId(url) {
  var m = String(url).match(/\/stories\/(\d+)/);
  return m ? m[1] : null;
}

function getDetail(url) {
  console.log('inkitt detail url: ' + url);
  var id = _storyId(url);
  if (!id) return Promise.reject(new Error('bad inkitt url: ' + url));
  return Promise.all([
    _get(API + '/stories/' + id, true).then(function(r) { return _parseJson(r.body); }),
    _get(_storyUrl(id)).then(function(r) { return r.body || ''; }).catch(function() { return ''; })
  ]).then(function(res) {
    var d = (res[0] && res[0].response) || {};
    var html = res[1];

    var author = d.author ? d.author.name : '';
    var genres = [];
    var seenGenres = {};
    var sg = d.story_genres || [];
    for (var i = 0; i < sg.length; i++) {
      var g = sg[i].main_genre || sg[i];
      if (g && g.name && !seenGenres[g.name]) { seenGenres[g.name] = true; genres.push(g.name); }
    }
    var tags = [];
    var seenTags = {};
    var pills = d.pills || [];
    for (var p = 0; p < pills.length; p++) {
      if (pills[p] && pills[p].name && !seenTags[pills[p].name]) {
        seenTags[pills[p].name] = true;
        tags.push(pills[p].name);
      }
    }

    var chapters = _chaptersFromHtml(html, id);
    // Fallback: the page sometimes omits the list; synthesise from the count.
    if (chapters.length === 0 && d.chapters_count > 0) {
      for (var n = 1; n <= d.chapters_count; n++) {
        chapters.push({
          id: 'inkitt:' + id + ':' + n,
          title: 'Chapter ' + n,
          number: n,
          url: SITE + '/stories/' + id + '/chapters/' + n,
          date: ''
        });
      }
    }

    console.log('inkitt detail: title=' + d.title + ' chapters=' + chapters.length
      + ' status=' + d.story_status + ' genres=' + genres.length);
    return {
      id: id,
      sourceId: SOURCE_ID,
      title: _clean(d.title || ''),
      cover: (d.cover && d.cover.url) || d.small_cover_url || null,
      url: url,
      author: _clean(author),
      authors: author ? [_clean(author)] : [],
      status: _normalizeStatus(d.story_status),
      description: _clean(d.blurb || ''),
      genres: genres,
      tags: tags,
      chapters: chapters,
      type: 'novel'
    };
  });
}

function getChapters(url) {
  return getDetail(url).then(function(d) { return d.chapters; });
}

function getPages() {
  return [];
}

function getChapterContent(chapterUrl) {
  console.log('inkitt chapter url: ' + chapterUrl);
  return _get(chapterUrl).then(function(r) {
    var html = r.body || '';
    var boxM = html.match(/<div[^>]+id="chapterText"[^>]*>([\s\S]*?)<\/div>\s*<\/article>/i)
      || html.match(/<div[^>]+id="chapterText"[^>]*>([\s\S]*?)<\/div>/i);
    var box = boxM ? boxM[1] : '';
    box = box.replace(/<script[\s\S]*?<\/script>/gi, '');
    box = box.replace(/<ins[\s\S]*?<\/ins>/gi, '');

    var paragraphs = [];
    var pm = /<p[^>]*>([\s\S]*?)<\/p>/gi;
    var m;
    while ((m = pm.exec(box)) !== null) {
      var t = _clean(m[1]);
      if (t) paragraphs.push(t);
    }
    var text = paragraphs.length
      ? paragraphs.join('\n\n')
      : _clean(box.replace(/<br\s*\/?>/gi, '\n'));

    // Next chapter — bump the trailing number in the URL.
    var nextUrl = null;
    var nm = String(chapterUrl).match(/^(.*\/chapters\/)(\d+)\/?$/i);
    if (nm) nextUrl = nm[1] + (parseInt(nm[2], 10) + 1);

    console.log('inkitt chapter chars=' + text.length);
    return { text: text, nextUrl: nextUrl };
  });
}
