import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';

import 'potoken_js.dart';

/// YouTube PO tokens, minted with BotGuard.
///
/// A port of Hikari's `potoken/HikariPoTokenProvider.kt` + `PoTokenWebView.kt`.
/// Hikari runs the BotGuard VM in a hidden WebView; there is no WebView on the
/// stream-resolution path here, so the same program runs in the QuickJS runtime
/// the provider packs already use (`flutter_js`). Both run the identical
/// challenge → VM → `GenerateIT` → mint sequence, which is what the token is.
///
/// Why a token at all: YouTube serves roughly the first megabyte of an audio
/// stream to a player with no PO token and answers every later range with 403,
/// so a song stops after about a minute. The web-family clients refuse the
/// request outright. Native clients (the ones [YouTubeMusicSource] tries first)
/// do not take a token at all, which is why a mint failure costs nothing but a
/// lost fallback.
///
/// Everything here degrades: no JavaScript runtime, no network, or a refused
/// challenge all mean "no token", and the caller carries on. A failure is not
/// retried for [retryAfter], so a broken device does not pay for it per song.
class YouTubePoToken {
  const YouTubePoToken._();

  /// BotGuard's own public key, the one its page ships.
  static const String _apiKey = 'AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw';
  static const String _requestKey = 'O43z0dpjhgX20SCx4KAo';
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.3';
  static const String _visitorClientVersion = '2.20250925.01.00';

  static const Duration retryAfter = Duration(seconds: 90);

  /// How long the VM is given to come up before the attempt is written off.
  /// Hikari allows 40 s on a television thread; this runs on the app's isolate,
  /// so it is deliberately short — a token that is not ready quickly is not
  /// worth a stalled frame, and the native clients are still there.
  static const Duration _vmBudget = Duration(seconds: 2);

  static Dio? _dio;
  static Dio get _http =>
      _dio ??= Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          headers: const {'Accept': 'application/json'},
        ),
      );

  static JavascriptRuntime? _runtime;
  static String? _visitor;
  static String? _pot;
  static DateTime? _expiresAt;
  static DateTime? _failedAt;
  static Future<({String visitor, String pot})?>? _inFlight;

  /// True when this build could mint a token at all: Android, outside a failure
  /// window. Not a promise that the network or YouTube will agree.
  static bool get isAvailable => !kIsWeb && Platform.isAndroid && !_inBackoff;

  static bool get _inBackoff {
    final failed = _failedAt;
    return failed != null && DateTime.now().difference(failed) < retryAfter;
  }

  /// A brand-new anonymous visitor id, or null. Cached after the first success.
  static Future<String?> visitorData() async {
    final known = _visitor;
    if (known != null && known.isNotEmpty) return known;
    try {
      final response = await _http.post<dynamic>(
        'https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false',
        data: {
          'context': {
            'client': {
              'clientName': 'WEB',
              'clientVersion': _visitorClientVersion,
              'hl': 'en',
              'gl': 'US',
            },
          },
        },
        options: Options(
          headers: {
            'Origin': 'https://www.youtube.com',
            'X-YouTube-Client-Name': '1',
            'X-YouTube-Client-Version': _visitorClientVersion,
          },
        ),
      );
      final data = response.data;
      final context = data is Map ? data['responseContext'] : null;
      final raw = context is Map ? context['visitorData'] : null;
      final visitor = raw is String && raw.isNotEmpty ? raw : null;
      if (visitor == null) return null;
      _visitor = visitor;
      return visitor;
    } catch (e) {
      debugPrint('[potoken] visitor id failed: $e');
      return null;
    }
  }

  /// The visitor id and the streaming token bound to it, or null.
  ///
  /// Both come from one visitor: a token minted for another visitor id is
  /// refused, so callers must send [visitor] with [pot].
  static Future<({String visitor, String pot})?> streaming() {
    final cached = _cached();
    if (cached != null) return Future.value(cached);
    if (_inBackoff || kIsWeb || !Platform.isAndroid) {
      return Future.value(null);
    }
    return _inFlight ??= _build().whenComplete(() => _inFlight = null);
  }

  /// The token bound to one video, for the `player` request's
  /// `serviceIntegrityDimensions.poToken`. The streaming token covers the
  /// stream request; this covers the lookup.
  static Future<String?> mint({required String videoId}) async {
    final pair = await streaming();
    if (pair == null) return null;
    try {
      return _mintWith(videoId);
    } catch (e) {
      debugPrint('[potoken] mint failed for $videoId: $e');
      return null;
    }
  }

  /// Drops the visitor and token; the next [streaming] starts from a fresh pair.
  static void rotate() {
    _visitor = null;
    _pot = null;
    _expiresAt = null;
    _runtime?.dispose();
    _runtime = null;
  }

  static ({String visitor, String pot})? _cached() {
    final visitor = _visitor;
    final pot = _pot;
    final expires = _expiresAt;
    if (visitor == null || pot == null || expires == null) return null;
    if (!expires.isAfter(DateTime.now())) return null;
    return (visitor: visitor, pot: pot);
  }

  static Future<({String visitor, String pot})?> _build() async {
    try {
      final visitor = await visitorData();
      if (visitor == null) throw StateError('no visitor id');
      // xhr: false — BotGuard's networking is done in Dart, and the XHR
      // shim would only add surface area to the sandbox this runs in.
      final runtime = _runtime ??= getJavascriptRuntime(xhr: false);
      final challenge = await _botguard(
        'https://www.youtube.com/api/jnn/v1/Create',
        '[ "$_requestKey" ]',
      );
      final response = _runVm(runtime, parseChallengeData(challenge));
      final integrity = await _botguard(
        'https://www.youtube.com/api/jnn/v1/GenerateIT',
        '[ "$_requestKey", ${_jsonString(response)} ]',
      );
      final token = parseIntegrityTokenData(integrity);
      _setToken(runtime, token.tokenJs);
      final pot = _mintWith(visitor);
      // A minute of margin: a token that expires mid-song is a 403 mid-song.
      _expiresAt = DateTime.now().add(token.lifetime - const Duration(minutes: 1));
      _visitor = visitor;
      _pot = pot;
      debugPrint('[potoken] ready for a fresh visitor id');
      return (visitor: visitor, pot: pot);
    } catch (e) {
      _failedAt = DateTime.now();
      debugPrint('[potoken] no token: $e');
      rotate();
      return null;
    }
  }

  static String _mintWith(String identifier) {
    final runtime = _runtime;
    if (runtime == null) throw StateError('no runtime');
    final out = runtime.evaluate(
      '__bg.mint(${_jsonString(stringToU8(identifier))})',
    );
    if (out.isError) throw StateError('mint: ${out.stringResult}');
    final text = out.stringResult;
    if (text.isEmpty) throw StateError('mint returned nothing');
    return u8ToBase64(text);
  }

  static void _setToken(JavascriptRuntime runtime, String tokenJs) {
    final out = runtime.evaluate('__bg.setToken(${_jsonString(tokenJs)})');
    if (out.isError) throw StateError('token: ${out.stringResult}');
  }

  /// Loads the VM, waits for it, takes one snapshot and returns the response
  /// YouTube's `GenerateIT` signs.
  static String _runVm(JavascriptRuntime runtime, BotGuardChallenge challenge) {
    final glue = runtime.evaluate(_glue);
    if (glue.isError) throw StateError('glue: ${glue.stringResult}');

    final init = runtime.evaluate('__bg.init(${_jsonString(challenge.json)})');
    if (init.isError) throw StateError('init: ${init.stringResult}');

    final deadline = DateTime.now().add(_vmBudget);
    while (!_ask(runtime, 'ready')) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('VM did not come up');
      }
      runtime.executePendingJob();
    }

    final snapshot = runtime.evaluate('__bg.snapshot()');
    if (snapshot.isError) throw StateError('snapshot: ${snapshot.stringResult}');
    while (!_ask(runtime, 'done')) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('snapshot did not answer');
      }
      runtime.executePendingJob();
    }
    final response = runtime.evaluate('__bg.response()');
    if (response.isError || response.stringResult.isEmpty) {
      throw StateError('no snapshot response');
    }
    return response.stringResult;
  }

  /// The glue answers `'ok'` or `''`, so a boolean probe is a string compare.
  static bool _ask(JavascriptRuntime runtime, String step) =>
      runtime.evaluate('__bg.$step()').stringResult == 'ok';

  static Future<String> _botguard(String url, String data) async {
    final response = await _http.post<dynamic>(
      url,
      data: data,
      options: Options(
        contentType: 'application/json+protobuf',
        responseType: ResponseType.plain,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
          'x-goog-api-key': _apiKey,
          'x-user-agent': 'grpc-web-javascript/0.1',
        },
      ),
    );
    final body = response.data;
    if (response.statusCode != 200 || body is! String) {
      throw StateError('BotGuard answered ${response.statusCode}');
    }
    return body;
  }

  static String _jsonString(String value) =>
      '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

  /// BotGuard's glue, ported from Hikari's `assets/po_token.html` with the
  /// timer-driven promise chain replaced by explicit steps: QuickJS has no
  /// `setInterval`, so the caller pumps jobs and asks `ready`/`done` instead.
  static const String _glue = r'''
globalThis.__bg = (function () {
  var st = { fn: null, response: null, token: null, signals: [] };
  return {
    init: function (json) {
      var c = JSON.parse(json);
      st.fn = null; st.response = null; st.signals = [];
      var interp = c.interpreterJavascript
        .privateDoNotAccessOrElseSafeScriptWrappedValue;
      if (!interp) throw new Error('Could not load VM');
      (new Function(interp))();
      var vm = globalThis[c.globalName];
      if (!vm || !vm.a) throw new Error('Could not load program');
      vm.a(c.program, function (asyncSnapshot) {
        st.fn = { asyncSnapshot: asyncSnapshot };
      }, true, undefined, function () {}, [[], []]);
      return 'ok';
    },
    ready: function () { return (st.fn && st.fn.asyncSnapshot) ? 'ok' : ''; },
    snapshot: function () {
      st.fn.asyncSnapshot(function (r) { st.response = r; },
        [undefined, undefined, st.signals, undefined]);
      return 'ok';
    },
    done: function () { return st.response == null ? '' : 'ok'; },
    response: function () {
      return st.response == null ? '' : String(st.response);
    },
    setToken: function (js) {
      st.token = (new Function('return ' + js))();
      return 'ok';
    },
    mint: function (u8Literal) {
      var id = (new Function('return ' + u8Literal))();
      var getMinter = st.signals[0];
      if (!getMinter) throw new Error('PMD:Undefined');
      var mint = getMinter(st.token);
      if (typeof mint !== 'function') throw new Error('APF:Failed');
      var out = mint(id);
      if (!out) throw new Error('YNJ:Undefined');
      if (!(out instanceof Uint8Array)) throw new Error('ODM:Invalid');
      var text = '';
      for (var i = 0; i < out.length; i++) {
        if (i) text += ',';
        text += out[i];
      }
      return text;
    }
  };
})();
if (!globalThis.window) globalThis.window = globalThis;
if (!globalThis.self) globalThis.self = globalThis;
if (!globalThis.navigator) globalThis.navigator = { userAgent: 'Mozilla/5.0' };
if (!globalThis.location) globalThis.location = { href: 'https://www.youtube.com/' };
''';
}
