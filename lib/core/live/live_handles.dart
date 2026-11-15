/// The `live:`-family schemes a live-sports source uses for a single fixture.
///
/// Every sports source mints its own handle and each names the SAME idea — one
/// playable broadcast — but they don't share a prefix:
///   • `live:<id>|<path>`      — MovieBox, StreamFree
///   • `ev:<title>|<channels>` — CDNLive TV
///   • `ts:<json{feeds}>`      — TimStreams
///
/// These are not titles: a handle has no detail page and its provider resolves
/// it straight to a signed stream URL. Recognizing only `live:` left CDNLive's
/// and TimStreams' fixtures looking like ordinary titles, so a tap routed them
/// through the metadata catalogue / detail page and the player reported "no
/// source to play".
const List<String> kLiveHandleSchemes = ['live:', 'ev:', 'ts:'];

/// True when [url] is a live-sports fixture handle (see [kLiveHandleSchemes]).
bool isLiveHandle(String url) {
  for (final s in kLiveHandleSchemes) {
    if (url.startsWith(s)) return true;
  }
  return false;
}
