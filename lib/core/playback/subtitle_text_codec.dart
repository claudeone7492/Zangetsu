import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/latin.dart';
import 'package:enough_convert/windows.dart';

import 'subtitle_text_normalizer.dart';

/// Reading a subtitle file that came from the internet.
///
/// Caption sites are old and inconsistent: they serve legacy single-byte
/// encodings (Polish and Czech in windows-1250, Russian in windows-1251, Arabic
/// in windows-1256, Greek in windows-1253) usually with no charset in the
/// response. Decoding those as UTF-8 turns every accented letter into a
/// replacement character, so a caption arrives as mojibake.
///
/// The encoding decision follows the evidence in order: a byte-order mark, then
/// valid UTF-8, then the declared charset, then whichever code page decodes to
/// something that looks most like real words. A declared charset is only a nudge,
/// because the sites that omit one are the same sites that get it wrong when they
/// do include it.
class SubtitleTextCodec {
  const SubtitleTextCodec._();

  static const int _replacementChar = 0xFFFD;

  /// Central-European letters that make windows-1250 and iso-8859-2
  /// distinguishable from the rest.
  static const String _centralEuropean =
      'ąćęłńśźżčďěňřšťůžőűăşţáéíóöúüýäôĄĆĘŁŃŚŹŻČĎĚŇŘŠŤŮŽŐŰĂŞŢÁÉÍÓÖÚÜÝÄÔ';

  /// One candidate code page: its label, the letters that appear often in a
  /// language written in it, and the Unicode range its letters decode into.
  static final List<_CodePage> _codePages = [
    _CodePage(
      'windows-1252',
      _chars('àâäçèéêëîïôöùûüßñáíóúãõœæÀÂÄÇÈÉÊËÎÏÔÖÙÛÜÑÁÍÓÚÃÕ'),
      null,
      const Windows1252Codec(allowInvalid: true),
    ),
    _CodePage(
      'windows-1250',
      _chars(_centralEuropean),
      null,
      const Windows1250Codec(allowInvalid: true),
    ),
    _CodePage(
      'windows-1251',
      _chars('оеаинтсрвлкмдп'),
      RegExp(r'[\u0400-\u04FF]'),
      const Windows1251Codec(allowInvalid: true),
    ),
    _CodePage(
      'windows-1256',
      null,
      RegExp(r'[\u0600-\u06FF]'),
      const Windows1256Codec(allowInvalid: true),
    ),
    _CodePage(
      'windows-1253',
      _chars('αεηιονστυρκμπλ'),
      RegExp(r'[\u0370-\u03FF]'),
      const Windows1253Codec(allowInvalid: true),
    ),
    _CodePage(
      'windows-1254',
      _chars('ğışçöüİĞŞÇÖÜ'),
      null,
      const Windows1254Codec(allowInvalid: true),
    ),
    _CodePage(
      'windows-1255',
      null,
      RegExp(r'[\u0590-\u05FF]'),
      const Windows1255Codec(allowInvalid: true),
    ),
    // ISO-8859-2 places several Polish and Czech letters elsewhere than 1250.
    _CodePage(
      'iso-8859-2',
      _chars(_centralEuropean),
      null,
      const Latin2Codec(allowInvalid: true),
    ),
  ];

  static Set<String> _chars(String s) => s.split('').toSet();

  /// The charset named in a `Content-Type` header, or null when it says nothing
  /// useful.
  static String? charsetFromContentType(String? contentType) {
    final m = RegExp(
      '''charset=["']?([\\w.:-]+)''',
      caseSensitive: false,
    ).firstMatch(contentType ?? '');
    return m?.group(1);
  }

  /// Decodes [bytes] as text.
  ///
  /// The declared charset is only a hint: it is tried, and its result given a
  /// small bonus, but a better-scoring code page still wins, because a wrong
  /// `charset` is common and a file that decodes to the wrong letters is
  /// unusable either way.
  static String decode(List<int> bytes, {String? declaredCharset}) {
    if (bytes.isEmpty) return '';
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    // A byte-order mark is decisive — it is the one signal that is never wrong.
    if (data.length >= 3 &&
        data[0] == 0xEF &&
        data[1] == 0xBB &&
        data[2] == 0xBF) {
      return _decodeUtf8(data.sublist(3)) ?? '';
    }
    if (data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
      return _decodeUtf16(data.sublist(2), littleEndian: true);
    }
    if (data.length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
      return _decodeUtf16(data.sublist(2), littleEndian: false);
    }

    // Valid UTF-8 is the next most likely and, when it holds, is taken as read.
    final utf8 = _decodeUtf8(data);
    if (utf8 != null) return utf8;

    final declared = declaredCharset?.trim().toLowerCase();
    final candidates = List<_CodePage>.of(_codePages);
    // A charset the app does not already try is tried first, so an unusual but
    // correct one is still considered; the common ones are already in the list.
    if (declared != null &&
        declared.isNotEmpty &&
        !RegExp(r'^utf-?8$').hasMatch(declared) &&
        !candidates.any((c) => c.label == declared)) {
      final extra = _codecFor(declared);
      if (extra != null) {
        candidates.insert(0, _CodePage(declared, null, null, extra));
      }
    }

    String? bestText;
    var bestScore = 0;
    for (final page in candidates) {
      final text = _decodeWith(page.codec, data);
      if (text == null) continue;
      var score = _score(text, page);
      // The declared charset is often right; a small bonus breaks ties toward it
      // without letting a plainly wrong declaration override a clearly better
      // decode.
      if (page.label == declared) score += 4;
      if (bestText == null || score > bestScore) {
        bestText = text;
        bestScore = score;
      }
    }
    return bestText ?? utf8 ?? String.fromCharCodes(data);
  }

  static String? _decodeUtf8(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  static String? _decodeWith(Encoding codec, Uint8List bytes) {
    try {
      return codec.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static Encoding? _codecFor(String label) {
    switch (label) {
      case 'windows-1250':
      case 'cp1250':
        return const Windows1250Codec(allowInvalid: true);
      case 'windows-1251':
      case 'cp1251':
        return const Windows1251Codec(allowInvalid: true);
      case 'windows-1252':
      case 'cp1252':
        return const Windows1252Codec(allowInvalid: true);
      case 'windows-1253':
      case 'cp1253':
        return const Windows1253Codec(allowInvalid: true);
      case 'windows-1254':
      case 'cp1254':
        return const Windows1254Codec(allowInvalid: true);
      case 'windows-1255':
      case 'cp1255':
        return const Windows1255Codec(allowInvalid: true);
      case 'windows-1256':
      case 'cp1256':
        return const Windows1256Codec(allowInvalid: true);
      case 'iso-8859-2':
      case 'latin2':
        return const Latin2Codec(allowInvalid: true);
      case 'iso-8859-1':
      case 'latin1':
        return latin1;
      default:
        return null;
    }
  }

  /// How much [text] looks like real words in [page].
  ///
  /// High-frequency letters score positively, letters of the page's script score
  /// a little, and the signs of a wrong decode — replacement characters, mixed
  /// scripts inside one word, a lower-to-upper switch mid-word, symbols glued
  /// between letters — score against.
  static int _score(String text, _CodePage page) {
    var total = 0;
    for (final rune in text.runes) {
      if (rune == _replacementChar || (rune >= 0x80 && rune <= 0x9F)) {
        total -= 10;
        continue;
      }
      if (rune < 0x80) continue;
      final ch = String.fromCharCode(rune);
      if (page.frequent?.contains(ch) == true) {
        total += 2;
      } else if (page.script?.hasMatch(ch) == true) {
        total += page.frequent != null ? 0 : 1;
      }
    }
    for (final word in _wordRuns(text)) {
      if (word.isEmpty) continue;
      final latin = _latinLetter.hasMatch(word);
      final other = _otherScript.hasMatch(word);
      if (latin && other) total -= 6;
      // A lower-to-upper switch inside a word means the wrong page was chosen.
      total -= _lowerToUpperCount(word) * 3;
    }
    // Symbols glued between letters ("na³ka") are a wrong code page too.
    total -=
        _letterSymbolLetterCount(
          text,
          (c) =>
              (c >= 0xA0 && c <= 0xBF) ||
              c == 0xD7 ||
              c == 0xF7 ||
              (c >= 0x2000 && c <= 0x20FF),
        ) *
        4;
    if (page.label == 'windows-1252') {
      total += _invertedPunctuationCount(text) * 3;
      total -=
          _letterSymbolLetterCount(text, (c) => 'þðÞÐ'.codeUnits.contains(c)) *
          3;
      total -= _oTildeNotFollowedByE(text) * 2;
      total -=
          _letterSymbolLetterCount(text, (c) => c == 0xAA || c == 0xBA) * 3;
    }
    return total;
  }

  /// Runs of letters in [text], which is what the code-page heuristics reason
  /// about.
  static List<String> _wordRuns(String text) {
    final words = <String>[];
    var start = -1;
    final units = text.runes.toList(growable: false);
    for (var i = 0; i < units.length; i++) {
      final isLetter = RegExp(
        r'^\p{L}$',
        unicode: true,
      ).hasMatch(String.fromCharCode(units[i]));
      if (isLetter) {
        if (start < 0) start = i;
      } else if (start >= 0) {
        words.add(String.fromCharCodes(units.sublist(start, i)));
        start = -1;
      }
    }
    if (start >= 0) words.add(String.fromCharCodes(units.sublist(start)));
    return words;
  }

  /// How many times a lowercase letter is directly followed by an uppercase one
  /// inside a word.
  static int _lowerToUpperCount(String word) {
    var count = 0;
    for (var i = 0; i + 1 < word.length; i++) {
      final a = word[i];
      final b = word[i + 1];
      if (_isLower(a) && _isUpper(b)) count++;
    }
    return count;
  }

  static bool _isLower(String c) =>
      c == c.toLowerCase() && c != c.toUpperCase();
  static bool _isUpper(String c) =>
      c == c.toUpperCase() && c != c.toLowerCase();

  /// How many times [symbol] sits directly between two letters.
  static int _letterSymbolLetterCount(String text, bool Function(int) symbol) {
    var count = 0;
    final units = text.runes.toList(growable: false);
    for (var i = 1; i + 1 < units.length; i++) {
      if (_isLetterRune(units[i - 1]) &&
          symbol(units[i]) &&
          _isLetterRune(units[i + 1])) {
        count++;
      }
    }
    return count;
  }

  static bool _isLetterRune(int rune) =>
      RegExp(r'^\p{L}$', unicode: true).hasMatch(String.fromCharCode(rune));

  /// How many inverted question or exclamation marks open a word, which only
  /// Spanish does.
  static int _invertedPunctuationCount(String text) {
    var count = 0;
    final units = text.runes.toList(growable: false);
    for (var i = 0; i < units.length; i++) {
      if (units[i] == 0xBF || units[i] == 0xA1) {
        final before = i == 0 ? null : units[i - 1];
        if (before == null ||
            _isSpaceRune(before) ||
            '"\'(-'.codeUnits.contains(before)) {
          count++;
        }
      }
    }
    return count;
  }

  static bool _isSpaceRune(int rune) =>
      RegExp(r'^\s$', unicode: true).hasMatch(String.fromCharCode(rune));

  /// How many `õ`/`Õ` are not the Portuguese diphthong, which is the sign of a
  /// wrong decode.
  static int _oTildeNotFollowedByE(String text) {
    var count = 0;
    final units = text.runes.toList(growable: false);
    for (var i = 0; i < units.length; i++) {
      if (units[i] == 0xF5 || units[i] == 0xD5) {
        final next = i + 1 < units.length ? units[i + 1] : null;
        if (next == null || (next != 0x65 && next != 0x45)) count++;
      }
    }
    return count;
  }

  static final RegExp _latinLetter = RegExp(r'[A-Za-z\u00C0-\u024F]');
  static final RegExp _otherScript = RegExp(
    r'[\u0370-\u03FF\u0400-\u04FF\u0590-\u05FF\u0600-\u06FF]',
  );
}

/// Decodes caption [bytes] to UTF-8 text, ready to be written for the player.
///
/// A caption site's bytes are decoded with [SubtitleTextCodec] (honouring a
/// [declaredCharset] when the response carried one), then checked with
/// [SubtitleTextNormalizer.looksLikeSubtitle]. Null is returned when the bytes
/// are not a caption at all — an HTML error page or a JSON payload served with a
/// subtitle URL — so the caller can fall back rather than write markup to disk.
Uint8List? prepareSubtitleBytes(List<int> bytes, {String? declaredCharset}) {
  if (bytes.isEmpty) return null;
  final text = SubtitleTextCodec.decode(
    bytes,
    declaredCharset: declaredCharset,
  );
  if (!SubtitleTextNormalizer.looksLikeSubtitle(text)) return null;
  return Uint8List.fromList(utf8.encode(text));
}

/// Decodes caption [bytes] to UTF-8 text, or null when they are not a caption.
String? decodeSubtitleText(List<int> bytes, {String? declaredCharset}) {
  final prepared = prepareSubtitleBytes(
    bytes,
    declaredCharset: declaredCharset,
  );
  return prepared == null ? null : utf8.decode(prepared);
}

class _CodePage {
  const _CodePage(this.label, this.frequent, this.script, this.codec);
  final String label;
  final Set<String>? frequent;
  final RegExp? script;
  final Encoding codec;
}
