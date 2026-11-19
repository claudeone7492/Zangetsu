/// Wraps a third-party JS plugin module so it answers OUR provider contract.
///
/// Each family publishes modules in a slightly different dialect:
///
/// | family   | how it exports                      | list/search/detail/streams              |
/// |----------|-------------------------------------|-----------------------------------------|
/// | Nuvio    | `module.exports = {…}` or globals   | `getHome/getSearch/getDetail/getStreams`|
/// | Vega     | CommonJS `module.exports`           | same four                               |
/// | Sora     | `module.exports` (+ `manifest`)     | `getHome/getSearch/getDetail/getStreams`|
/// | SkyStream| globals                             | same four                               |
/// | Hikari   | `module.exports` (Hikari SDK names) | `getHome/getItem/getStreams`            |
/// | Kotatsu  | `module.exports`                    | `getHome/getSearch/getDetail/getStreams`|
///
/// Rather than six adapters, the wrapper evaluates the module once, then
/// resolves each method from a list of aliases in priority order and registers
/// ONE normalised object at `__providers[<sourceId>]` — the same slot a
/// first-party provider occupies, so everything downstream (scheduler,
/// Cloudflare bridge, settings push, health) works unchanged.
///
/// Returns the JS to evaluate. The module's own `fetch`/`console` resolve
/// against the host bridge, exactly like a first-party provider.
String wrapJsPackModule(String sourceId, String moduleJs) {
  final src = sourceId.replaceAll("'", r"\'");
  return '''
(function(){
  var __SOURCE_ID = '$src';
  var __module = { exports: {} };
  var module = __module;
  var exports = __module.exports;
  var fetch = function(url, opts) { return globalThis.__fetch(__SOURCE_ID, url, opts); };
  var extractVideo = function(url, opts) { return globalThis.extractVideo(url, opts); };
  var console = {
    log:   function() { globalThis.__console(__SOURCE_ID, 'log', arguments); },
    warn:  function() { globalThis.__console(__SOURCE_ID, 'warn', arguments); },
    error: function() { globalThis.__console(__SOURCE_ID, 'error', arguments); },
    info:  function() { globalThis.__console(__SOURCE_ID, 'info', arguments); },
    debug: function() { globalThis.__console(__SOURCE_ID, 'debug', arguments); }
  };
  // Some families ship an ES-module `export default {…}`; strip the two ES
  // keywords the runtime would reject and let the object fall through to the
  // globals path below.
  var __code = String(${_jsonString(moduleJs)});
  __code = __code.replace(/\\bexport\\s+default\\s+/g, 'var __default = ');
  __code = __code.replace(/\\bexport\\s+(const|let|var|function|async\\s+function)\\s+/g, '\$1 ');
  try { eval(__code); } catch (e) {
    globalThis.__console(__SOURCE_ID, 'error', ['module eval failed: ' + e]);
  }
  var __exp = __module.exports;
  if ((!__exp || Object.keys(__exp).length === 0) && typeof __default !== 'undefined') {
    __exp = __default;
  }
  __exp = __exp || {};

  // First defined function among the aliases wins. A family that names its
  // detail call `getItem` (Hikari) lands on the same slot as one that calls it
  // `getDetail` (Nuvio) — the app only ever sees the canonical name.
  function pick(names) {
    for (var i = 0; i < names.length; i++) {
      var n = names[i];
      if (typeof __exp[n] === 'function') return __exp[n];
      if (typeof globalThis[n] === 'function') return globalThis[n];
      if (typeof eval('typeof ' + n) === 'string' && eval('typeof ' + n) === 'function') {
        return eval(n);
      }
    }
    return null;
  }

  var __info = pick(['getInfo', 'info', 'manifest']) ;
  globalThis.__providers['$src'] = {
    getInfo: function() {
      if (__info) { try { return __info(); } catch (e) {} }
      var m = (typeof __exp.manifest === 'object' && __exp.manifest) || {};
      return {
        name: __exp.name || m.name || '$src',
        lang: __exp.lang || m.lang || 'en',
        baseUrl: __exp.baseUrl || m.baseUrl || m.site || '',
        logo: __exp.logo || m.logo || null,
        type: __exp.type || m.type || 'movie',
        version: __exp.version || m.version || '1.0.0'
      };
    },
    getHome:         pick(['getHome', 'home', 'getPopular', 'popular']),
    popular:         pick(['popular', 'getPopular', 'getHome', 'home']),
    search:          pick(['search', 'getSearch', 'getSearchResults']),
    getDetail:       pick(['getDetail', 'getItem', 'detail', 'getInfo2']),
    getEpisodes:     pick(['getEpisodes', 'getEpisodeList', 'getChapters', 'episodes']),
    getVideoSources: pick(['getVideoSources', 'getStreams', 'getLinks', 'getVideoList', 'streams']),
    getPages:        pick(['getPages', 'getChapterPages']),
    getText:         pick(['getText', 'getChapterText'])
  };
})();
''';
}

/// JSON-encode a JS body safely for embedding in the wrapper above.
String _jsonString(String value) {
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r')
      .replaceAll('\t', r'\t');
  return '"$escaped"';
}
