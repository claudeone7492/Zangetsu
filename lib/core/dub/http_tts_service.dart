import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A neural voice, as offered by [HttpTtsService].
///
/// A hosted voice is identified by its language alone — the endpoint picks the
/// speaker — so unlike a device voice there is no separate name to choose. The
/// catalogue is therefore one entry per language, which is also what the viewer
/// actually cares about when dubbing a programme that is not in their language.
class NeuralVoice {
  const NeuralVoice({required this.iso, required this.label, required this.labelKey});

  /// Language tag the endpoint expects (`en`, `pt-BR`).
  final String iso;

  /// English name, kept as the fallback for a locale the app has no name for.
  final String label;

  /// Stable id the UI localises the name with, e.g. `voiceLangGerman`.
  final String labelKey;

  /// The BCP-47 tag handed to the endpoint. Region is dropped because the
  /// catalogue is keyed on the language, and the endpoint treats `pt-BR` and
  /// `pt` alike for voice selection.
  String get languageCode => iso.split('-').first;
}

/// Turns text into spoken audio with a hosted neural voice.
///
/// This is the D2 engine's other half: D1 speaks through the device's TTS
/// engine, which is offline and instant but sounds synthetic. A hosted voice
/// sounds like a person, at the cost of a network round-trip per line.
///
/// The endpoint is the keyless one the app already uses for translation, which
/// matters more than it looks: a neural voice that needed an API key would be a
/// second key to configure before dub worked at all, and the feature would sit
/// behind a signup. Same vendor, same zero-configuration contract.
///
/// Two constraints shape this class, both measured against the live endpoint:
///
///  * **200 characters per request.** Longer text is rejected outright, and
///    captions routinely exceed that, so [synthesize] splits on sentence and
///    word boundaries and returns one clip per part.
///  * **No rate control.** The endpoint ignores `ttsspeed`, so speaking rate is
///    applied at playback by the engine rather than requested here.
class HttpTtsService {
  HttpTtsService({Dio? dio}) : _dio = dio ?? _createDio();

  static const String endpoint =
      'https://translate.google.com/translate_tts';

  /// The endpoint's hard limit, in characters. Verified: 200 succeeds, 201 is
  /// a 400.
  static const int maxCharsPerRequest = 200;

  /// Part of the request the endpoint requires and that never changes. `tw-ob`
  /// is the client id the endpoint accepts for this use.
  static const String _client = 'tw-ob';

  final Dio _dio;

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      // The body is audio, not JSON.
      responseType: ResponseType.bytes,
      validateStatus: (status) => status != null && status < 400,
    ),
  );

  /// Voices offered by the service, best-known first.
  ///
  /// Static rather than fetched: the endpoint has no catalogue route, and
  /// probing it for every language on every open would be a burst of requests
  /// to answer a question with a fixed answer. The list is the languages the
  /// endpoint was verified to speak, which is what the picker needs.
  static const List<NeuralVoice> voices = [
    NeuralVoice(iso: 'en', label: 'English', labelKey: 'voiceLangEnglish'),
    NeuralVoice(iso: 'es', label: 'Spanish', labelKey: 'voiceLangSpanish'),
    NeuralVoice(iso: 'fr', label: 'French', labelKey: 'voiceLangFrench'),
    NeuralVoice(iso: 'de', label: 'German', labelKey: 'voiceLangGerman'),
    NeuralVoice(iso: 'it', label: 'Italian', labelKey: 'voiceLangItalian'),
    NeuralVoice(iso: 'pt', label: 'Portuguese', labelKey: 'voiceLangPortuguese'),
    NeuralVoice(iso: 'ru', label: 'Russian', labelKey: 'voiceLangRussian'),
    NeuralVoice(iso: 'tr', label: 'Turkish', labelKey: 'voiceLangTurkish'),
    NeuralVoice(iso: 'id', label: 'Indonesian', labelKey: 'voiceLangIndonesian'),
    NeuralVoice(iso: 'hi', label: 'Hindi', labelKey: 'voiceLangHindi'),
    NeuralVoice(iso: 'ar', label: 'Arabic', labelKey: 'voiceLangArabic'),
    NeuralVoice(iso: 'ja', label: 'Japanese', labelKey: 'voiceLangJapanese'),
    NeuralVoice(iso: 'ko', label: 'Korean', labelKey: 'voiceLangKorean'),
    NeuralVoice(
      iso: 'zh-CN',
      label: 'Chinese (Mandarin)',
      labelKey: 'voiceLangChineseMandarin',
    ),
  ];

  /// Whether [iso] is a language the service speaks.
  static bool supports(String iso) =>
      voices.any((v) => v.iso == iso || v.languageCode == iso);

  /// Synthesizes [text] into MP3 clips, one per request-sized part.
  ///
  /// Returns the parts in speaking order; a single short line returns one clip.
  /// Throws [TtsException] with a message fit to show the viewer.
  ///
  /// [language] is an ISO-639-1 tag; it falls back to English rather than
  /// failing, because a wrong-language dub is still a dub and the caller may be
  /// guessing the language from a cue.
  Future<List<Uint8List>> synthesize(
    String text, {
    String language = 'en',
  }) async {
    final parts = splitForRequest(text);
    if (parts.isEmpty) {
      throw const TtsException('There is nothing to speak in this line.');
    }
    final tl = supports(language)
        ? (voices.firstWhere((v) => v.iso == language || v.languageCode == language).iso)
        : 'en';
    final out = <Uint8List>[];
    for (final part in parts) {
      out.add(await _fetchPart(part, tl));
    }
    return out;
  }

  Future<Uint8List> _fetchPart(String text, String tl) async {
    try {
      final response = await _dio.get<List<int>>(
        endpoint,
        queryParameters: {
          'ie': 'UTF-8',
          'q': text,
          'tl': tl,
          'client': _client,
        },
        options: Options(responseType: ResponseType.bytes),
      );
      // Status first: a 400 carrying an empty body would otherwise be reported
      // as "no audio", which tells the viewer nothing about what to change.
      final status = response.statusCode;
      if (status != null && status >= 400) {
        throw TtsException(_messageForStatus(status));
      }
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const TtsException('The voice service returned no audio.');
      }
      final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      if (!_looksLikeMp3(data)) {
        // A 200 with an HTML body is how this endpoint reports some rejections;
        // handing that to the player produces silence with no explanation.
        throw const TtsException('The voice service rejected this line.');
      }
      return data;
    } on DioException catch (e) {
      throw TtsException(_messageFor(e));
    }
  }

  static String _messageFor(DioException e) {
    final status = e.response?.statusCode;
    if (status != null) return _messageForStatus(status);
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'The voice service took too long to answer.';
      case DioExceptionType.connectionError:
        return 'No connection to the voice service.';
      default:
        return 'Could not reach the voice service.';
    }
  }

  static String _messageForStatus(int status) {
    if (status == 400) {
      return 'The voice service rejected this line. Try a shorter one.';
    }
    if (status == 429) {
      return 'The voice service is rate-limiting. Try again shortly.';
    }
    if (status >= 500) {
      return 'The voice service is having trouble. Try again later.';
    }
    return 'The voice service refused this line.';
  }

  /// An MPEG frame sync, which every MP3 starts with. The endpoint returns raw
  /// frames (no ID3 tag), so checking the first two bytes is enough to tell
  /// audio from an HTML error page.
  static bool _looksLikeMp3(Uint8List data) {
    if (data.length < 2) return false;
    return data[0] == 0xFF && (data[1] & 0xE0) == 0xE0;
  }

  /// Splits [text] into parts the endpoint will accept.
  ///
  /// Splitting is on the last sentence boundary that fits, then the last word
  /// boundary, and only then mid-word — in that order, because cutting mid-word
  /// is audible while cutting between sentences is not. Empty parts are
  /// dropped, so punctuation-only input yields nothing.
  static List<String> splitForRequest(
    String text, {
    int limit = maxCharsPerRequest,
  }) {
    final trimmed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.length <= limit) return [trimmed];

    final parts = <String>[];
    var rest = trimmed;
    while (rest.length > limit) {
      final window = rest.substring(0, limit);
      var cut = _lastBoundary(window, RegExp(r'[.!?…](?=\s)'));
      cut ??= _lastBoundary(window, RegExp(r'[,;:](?=\s)'));
      cut ??= _lastBoundary(window, RegExp(r'\s'));
      // No boundary at all (a single long token): take the window whole.
      cut ??= limit;
      final part = rest.substring(0, cut).trim();
      if (part.isNotEmpty) parts.add(part);
      rest = rest.substring(cut).trim();
    }
    if (rest.isNotEmpty) parts.add(rest);
    return parts;
  }

  /// End index just past the last match of [pattern] in [window], or null.
  static int? _lastBoundary(String window, RegExp pattern) {
    int? found;
    for (final m in pattern.allMatches(window)) {
      // Keep the delimiter with the part it ends: "Stop." reads better than
      // "Stop" + "." spoken as a separate clip.
      found = m.end;
    }
    return found;
  }
}

/// A speech failure with a message safe to surface in the UI.
class TtsException implements Exception {
  const TtsException(this.message);

  final String message;

  @override
  String toString() => message;
}
