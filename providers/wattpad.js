// Wattpad provider — https://www.wattpad.com (kattpad-port, novel type).
//
// Novel-type source backed by Wattpad's public JSON APIs (no auth needed):
//   * browse  → api/v3/stories?limit=&offset=  (newest/hot)
//   * search  → api/v4/search/stories?query=&limit=&offset=
//   * detail  → api/v3/stories/<id>?fields=…,parts(id,title,url)
//   * chapter → api/v4/parts/<partId>?fields=id,text_url → text_url.text
//               returns HTML paragraphs (<p data-p-id=…>)
//
// Note the two hosts: v3 lives on www.wattpad.com, v4 on api.wattpad.com.

var SOURCE_ID = 'wattpad';
var WWW = 'https://www.wattpad.com';
var API4 = 'https://api.wattpad.com';
var LOGO = 'https://www.wattpad.com/favicon.ico';

function getInfo() {
  return {
    name: 'Wattpad',
    lang: 'en',
    baseUrl: WWW,
    logo: LOGO,
    type: 'novel',
    version: '1.0.0'
  };
}

function _clean(s) {
  return String(s || '').replace(/\s+/g, ' ').trim();
}

function _decodeEntities(s) {
  return String(s || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&hellip;/g, '…')
    .replace(/&mdash;/g, '—')
    .replace(/&ndash;/g, '–');
}

function _storyUrl(id) {
  return WWW + '/story/' + id;
}

function _storyId(url) {
  var m = String(url).match(/\/story\/(\d+)/) || String(url).match(/(\d{4,})/);
  return m ? m[1] : String(url);
}

function _partId(url) {
  var m = String(url).match(/^wp:(\d+)$/) || String(url).match(/\/parts\/(\d+)/)
    || String(url).match(/\/(\d{5,})/);
  return m ? m[1] : String(url);
}

function _card(story) {
  return {
    id: String(story.id),
    title: _clean(story.title),
    cover: story.cover || null,
    url: _storyUrl(story.id),
    author: story.user ? story.user.name : '',
    description: _clean(story.description || ''),
    type: 'novel'
  };
}

async function _json(url) {
  var res = await fetch(url, { headers: { Accept: 'application/json' } });
  if (res.status !== 200) {
    console.log('wattpad HTTP ' + res.status + ' ' + url);
    return null;
  }
  try {
    return JSON.parse(res.body || 'null');
  } catch (e) {
    console.log('wattpad bad JSON: ' + e);
    return null;
  }
}

async function _browseRow(title, filter) {
  var url = WWW + '/api/v3/stories?limit=20' + (filter ? '&filter=' + filter : '');
  var data = await _json(url);
  if (!data || !data.stories) return null;
  var items = data.stories.map(_card);
  return items.length ? { title: title, items: items } : null;
}

async function getHome(opts) {
  opts = opts || {};
  var rows = [
    { title: 'Hot', filter: 'hot' },
    { title: 'New', filter: 'new' },
    { title: 'Recently Updated', filter: '' }
  ];
  var sections = [];
  for (var i = 0; i < rows.length; i++) {
    try {
      var sec = await _browseRow(rows[i].title, rows[i].filter);
      if (sec) sections.push(sec);
    } catch (e) {
      console.log('wattpad home row failed: ' + rows[i].title + ' (' + e + ')');
    }
  }
  return sections;
}

async function search(query, page, opts) {
  page = page || 1;
  opts = opts || {};
  var q = String(query || '').trim();
  var offset = (page - 1) * 20;
  var url = q
    ? API4 + '/v4/search/stories?query=' + encodeURIComponent(q) + '&limit=20&offset=' + offset
    : WWW + '/api/v3/stories?limit=20&offset=' + offset;
  console.log('wattpad search url: ' + url);
  var data = await _json(url);
  if (!data || !data.stories) return [];
  var out = data.stories.map(_card);
  console.log('wattpad search count: ' + out.length);
  return out;
}

async function getDetail(url) {
  console.log('wattpad detail url: ' + url);
  var id = _storyId(url);
  var api = WWW + '/api/v3/stories/' + id
    + '?fields=id,title,url,cover,description,categories,tags,completed,numParts,user(name),parts(id,title,url,length)';
  var data = await _json(api);
  if (!data) throw new Error('detail failed for ' + id);

  var chapters = [];
  var parts = data.parts || [];
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i];
    chapters.push({
      id: String(p.id),
      title: _clean(p.title || ('Part ' + (i + 1))),
      number: i + 1,
      url: 'wp:' + p.id,
      date: ''
    });
  }

  var tags = (data.tags || []).slice(0, 10);

  console.log('wattpad detail: title=' + data.title + ' parts=' + chapters.length);

  return {
    id: String(data.id || id),
    sourceId: SOURCE_ID,
    title: _clean(data.title),
    cover: data.cover || null,
    url: url,
    author: data.user ? data.user.name : '',
    status: data.completed ? 'completed' : 'ongoing',
    description: _clean(data.description || ''),
    genres: tags,
    chapters: chapters,
    type: 'novel'
  };
}

async function getChapters(url) {
  var detail = await getDetail(url);
  return detail.chapters;
}

async function getChapterContent(chapterUrl) {
  var partId = _partId(chapterUrl);
  var api = API4 + '/v4/parts/' + partId + '?fields=id,text_url';
  var data = await _json(api);
  if (!data || !data.text_url || !data.text_url.text) {
    throw new Error('chapter has no text_url');
  }
  var res = await fetch(data.text_url.text, { headers: { Accept: 'text/html' } });
  if (res.status !== 200) throw new Error('chapter HTTP ' + res.status);
  var html = res.body || '';
  // Text URLs paginate a long part: the response carries the next page id.
  var nextM = html.match(/data-next-page=["']([^"']+)["']/i);
  var text = _decodeEntities(html.replace(/<[^>]+>/g, '')).replace(/\n{3,}/g, '\n\n').trim();
  console.log('wattpad chapter text len: ' + text.length);
  return {
    text: text,
    nextUrl: nextM ? (data.text_url.text + nextM[1]) : null
  };
}

function getPages() {
  return [];
}
