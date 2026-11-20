/// The JS plugin-pack families the app speaks.
///
/// Every family is "a repo of JavaScript modules, each module a source". They
/// differ only in the shape of the repo index and of the module's exports, so
/// the app runs them through ONE engine ([JsPackManager]) parameterised by a
/// descriptor here — instead of six near-identical managers drifting apart.
///
/// Each family keeps its own id prefix (`nuvio:`, `vega:`, …) so the source
/// picker can label the ecosystem and [SourceRepository] can route to it, and
/// its own Hive box so installing/removing one family never touches another.
enum JsPackEngine {
  /// `tapframe/nuvio-providers` and friends. QuickJS modules exporting
  /// `getHome/getSearch/getDetail/getStreams`; provisioned from a JSON index.
  nuvio(prefix: 'nuvio:', box: 'nuvio_packs', label: 'Nuvio'),

  /// `Zenda-Cross/vega-providers`. CommonJS modules; repo index is a bare
  /// JSON array of `{name, url}` entries.
  vega(prefix: 'vega:', box: 'vega_packs', label: 'Vega'),

  /// `xdfkenny/Sora-Modules`. ESM/CommonJS modules with a `manifest`.
  sora(prefix: 'sora:', box: 'sora_packs', label: 'Sora'),

  /// `akashdh11/skystream-plugins`. Plain JS modules.
  skystream(prefix: 'sky:', box: 'skystream_packs', label: 'SkyStream'),

  /// `KotatsuApp/kotatsu-parsers` — Kotatsu parsers are Kotlin; the curated
  /// JS-port subset is served in the same module shape, so it rides this
  /// engine like the others rather than needing a native host.
  kotatsu(prefix: 'kot:', box: 'kotatsu_packs', label: 'Kotatsu');

  const JsPackEngine({
    required this.prefix,
    required this.box,
    required this.label,
  });

  /// Id prefix that routes a source to this family (`nuvio:<moduleId>`).
  final String prefix;

  /// Hive box that persists this family's installed modules.
  final String box;

  /// Human label for the picker badge / Settings.
  final String label;

  /// The family a source id belongs to, or null when it belongs to none.
  static JsPackEngine? forSourceId(String sourceId) {
    for (final e in JsPackEngine.values) {
      if (sourceId.startsWith(e.prefix)) return e;
    }
    return null;
  }

  /// The module id inside a `prefix:id` source id (or the id unchanged).
  String moduleIdOf(String sourceId) => sourceId.startsWith(prefix)
      ? sourceId.substring(prefix.length)
      : sourceId;
}

/// Every family, for boot provisioning and the Extensions hub.
const List<JsPackEngine> kAllJsPackEngines = JsPackEngine.values;
