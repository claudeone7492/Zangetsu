import 'dart:convert';
import 'dart:typed_data';

/// Reads a panel's list (a JSON array of objects, or an object whose values
/// are objects) a piece at a time and hands over each object's simple fields
/// as strings. Ported verbatim from Hikari's `iptv/FlatJsonScanner.kt`.
///
/// Big catalogues (100,000+ titles) used to be held whole in memory three
/// times over — the bytes, the text and the parsed tree — and ran phones out
/// of memory. This keeps only the object being read.
///
/// Feed it bytes with [feed] as they arrive, then call [finish].
class FlatJsonScanner {
  FlatJsonScanner(this.onObject);

  /// Called once per completed item, in file order.
  final void Function(Map<String, String> fields) onObject;

  int _depth = 0;
  bool _started = false;
  bool _inString = false;
  bool _escape = false;
  int _unicodeLeft = 0;
  int _unicodeValue = 0;
  final StringBuffer _text = StringBuffer();
  bool _inLiteral = false;
  final StringBuffer _literal = StringBuffer();

  Map<String, String>? _fields;
  bool _expectKey = false;
  String? _key;

  /// Depth of the item object being read, or 0 when none is open. An item can
  /// sit directly in a bare array (depth 2) or inside a wrapper object
  /// (`{"channels": [{…}]}`, depth 3), so the field depth is tracked rather
  /// than assumed.
  int _itemDepth = 0;

  /// UTF-8 bytes from the end of the last chunk that did not make a whole
  /// character yet.
  Uint8List _carry = Uint8List(0);

  /// Objects handed over so far.
  int count = 0;

  void feed(List<int> bytes, [int? length]) {
    final len = length ?? bytes.length;
    final all = Uint8List.fromList([
      if (_carry.isNotEmpty) ..._carry,
      ...bytes.sublist(0, len),
    ]);
    final total = all.length;
    final end = _completeUtf8End(all, total);
    _carry = end < total ? Uint8List.fromList(all.sublist(end, total)) : Uint8List(0);
    if (end > 0) feedText(utf8.decode(all.sublist(0, end), allowMalformed: true));
  }

  void feedText(String chunk) {
    for (final unit in chunk.codeUnits) {
      _step(String.fromCharCode(unit));
    }
  }

  /// Throws if the list was cut off part-way (what the old whole-text parse
  /// also did).
  void finish() {
    if (_carry.isNotEmpty) feedText(utf8.decode(_carry, allowMalformed: true));
    _carry = Uint8List(0);
    if (_inLiteral) _endLiteral();
    if (_started && _depth != 0) {
      throw StateError("The provider's list ended part-way (after $count items)");
    }
  }

  void _step(String c) {
    if (_inString) {
      _stringChar(c);
      return;
    }
    if (_inLiteral) {
      if (c == ',' || c == '}' || c == ']' || c.trim().isEmpty) {
        _endLiteral();
      } else {
        _literal.write(c);
        return;
      }
    }
    switch (c) {
      case '"':
        _inString = true;
        _text.clear();
      case '{' || '[':
        if (_depth == 0) _started = true;
        if (c == '{' && _itemDepth == 0 && _depth >= 1) {
          _itemDepth = _depth + 1;
          _fields = <String, String>{};
          _expectKey = true;
          _key = null;
        }
        _depth++;
      case '}' || ']':
        _depth--;
        if (c == '}' && _itemDepth != 0 && _depth + 1 == _itemDepth) {
          final fields = _fields;
          _itemDepth = 0;
          if (fields != null) {
            count++;
            onObject(fields);
          }
          _fields = null;
        }
        if (_depth < 0) _depth = 0;
      case ':':
        if (_depth == _itemDepth) _expectKey = false;
      case ',':
        if (_depth == _itemDepth) {
          _expectKey = true;
          _key = null;
        }
      default:
        if (c.trim().isNotEmpty && _depth == _itemDepth && !_expectKey) {
          _inLiteral = true;
          _literal.clear();
          _literal.write(c);
        }
    }
  }

  void _stringChar(String c) {
    if (_unicodeLeft > 0) {
      final d = int.tryParse(c, radix: 16) ?? 0;
      _unicodeValue = _unicodeValue * 16 + d;
      if (--_unicodeLeft == 0) _appendChar(String.fromCharCode(_unicodeValue));
      return;
    }
    if (_escape) {
      _escape = false;
      switch (c) {
        case 'n':
          _appendChar('\n');
        case 't':
          _appendChar('\t');
        case 'r':
          _appendChar('\r');
        case 'b':
          _appendChar('\b');
        case 'f':
          _appendChar('\u000C');
        case 'u':
          _unicodeLeft = 4;
          _unicodeValue = 0;
        default:
          _appendChar(c); // \" \\ \/ and anything a lenient panel sends
      }
      return;
    }
    switch (c) {
      case r'\':
        _escape = true;
      case '"':
        _inString = false;
        _endString();
      default:
        _appendChar(c);
    }
  }

  void _appendChar(String c) {
    // Only strings that are a field of the item being read matter.
    if (_itemDepth != 0 && _depth == _itemDepth) _text.write(c);
  }

  void _endString() {
    if (_itemDepth == 0 || _depth != _itemDepth) return;
    final value = _text.toString();
    if (_expectKey) {
      _key = value;
    } else {
      final key = _key;
      if (key != null) _fields?[key] = value;
    }
  }

  void _endLiteral() {
    _inLiteral = false;
    if (_itemDepth == 0 || _depth != _itemDepth || _expectKey) return;
    final value = _literal.toString();
    if (value != 'null') {
      final key = _key;
      if (key != null) _fields?[key] = value;
    }
  }

  /// How many leading bytes of [b] (of [length]) end on a whole UTF-8
  /// character.
  static int _completeUtf8End(Uint8List b, int length) {
    var i = length - 1;
    var back = 0;
    while (i >= 0 && back < 4) {
      final x = b[i] & 0xFF;
      if (x & 0xC0 != 0x80) {
        final need = x < 0x80
            ? 1
            : x >= 0xF0
            ? 4
            : x >= 0xE0
            ? 3
            : x >= 0xC0
            ? 2
            : 1;
        return back + 1 >= need ? length : i;
      }
      i--;
      back++;
    }
    return length;
  }
}
