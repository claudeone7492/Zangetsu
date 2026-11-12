/// Turning whatever a caption site sent into WebVTT.
///
/// Two problems are solved here. The first is ASS/SSA, which several catalogues
/// serve as often as SubRip and which is not parseable as either SRT or VTT — its
/// timing lives in `Dialogue:` lines under `[Events]`. Its styling, positioning,
/// karaoke and vector-drawing commands cannot be shown by a plain cue renderer,
/// so only the timing and the text survive the conversion.
///
/// The second is SRT's comma decimal separator and its leftover ASS override tags
/// (`{\an8}`, `{\i1}`), which a WebVTT parser would print literally. Both are
/// fixed up so one parser downstream can read every file the same way.
class SubtitleTextNormalizer {
  const SubtitleTextNormalizer._();

  /// A timing line, in either SRT's comma form or VTT's dot form, with optional
  /// hours.
  static final RegExp _cueTiming = RegExp(
    r'(?:\d{2,}:)?\d{2}:\d{2}[.,]\d{1,3}\s+-->\s+(?:\d{2,}:)?\d{2}:\d{2}[.,]\d{1,3}',
  );

  /// The opening of an HTML error page or a JSON payload, which is never a
  /// caption.
  static final RegExp _notASubtitle = RegExp(
    r'^(?:<!doctype|<html|[{])',
    caseSensitive: false,
  );

  /// A `[Section]` header in an ASS file.
  static final RegExp _sectionHeader = RegExp(r'^\[.+]$');

  /// The `Format:` line that names an ASS event's fields.
  static final RegExp _formatLine = RegExp(r'^format:', caseSensitive: false);

  static final RegExp _scriptInfo = RegExp(
    r'^\s*\[Script Info]',
    caseSensitive: false,
  );
  static final RegExp _eventsSection = RegExp(
    r'^\[Events]',
    caseSensitive: false,
    multiLine: true,
  );
  static final RegExp _dialogue = RegExp(r'^Dialogue:', caseSensitive: false);
  static final RegExp _eventsOnly = RegExp(
    r'^\[events]$',
    caseSensitive: false,
  );
  static final RegExp _vttHeader = RegExp(r'^WEBVTT(?:\s|$)');
  static final RegExp _srtComma = RegExp(r'(\d{2}:\d{2}:\d{2}),(\d{3})');
  static final RegExp _drawingStart = RegExp(r'\\p[1-9]');
  static final RegExp _overrideTag = RegExp(r'[{]\\[^}]*[}]');

  /// Whether [text] is an ASS/SSA file rather than SRT or VTT.
  static bool isAss(String text) =>
      _scriptInfo.hasMatch(text) ||
      (_eventsSection.hasMatch(text) && _dialogue.hasMatch(text));

  /// Whether [text] could be a subtitle at all.
  ///
  /// Used to reject an HTML error page or a JSON payload served with a subtitle
  /// URL before it is written out and handed to the player, where it would
  /// either fail silently or render as markup. This is deliberately permissive
  /// about format: ASS, SRT and VTT are all accepted, because the player reads
  /// each natively and only the *decode* needs fixing.
  static bool looksLikeSubtitle(String text) {
    final body = text.startsWith('\uFEFF') ? text.substring(1) : text;
    if (body.trim().isEmpty) return false;
    if (_notASubtitle.hasMatch(body.trim())) return false;
    if (_vttHeader.hasMatch(body)) return true;
    if (isAss(body)) return true;
    return _cueTiming.hasMatch(body);
  }

  /// Normalises [raw] to WebVTT, or returns null when it is not a subtitle at
  /// all.
  ///
  /// Null is the honest answer for an HTML error page or a JSON payload served
  /// with a subtitle URL — the caller reports a bad file rather than showing the
  /// markup as a caption.
  static String? normalize(String raw) {
    final withoutBom = raw.startsWith('\uFEFF') ? raw.substring(1) : raw;
    if (isAss(withoutBom)) {
      final converted = assToVtt(withoutBom);
      return _cueTiming.hasMatch(converted) ? converted : null;
    }

    final text = withoutBom
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    // Reject an error page or an API response before it is handed to a parser.
    if (!_cueTiming.hasMatch(text) || _notASubtitle.hasMatch(text)) {
      return null;
    }
    if (_vttHeader.hasMatch(text)) return '$text\n';

    // SRT: swap the comma for a dot and drop the ASS override tags WebVTT would
    // print verbatim.
    final body = text
        .replaceAllMapped(_srtComma, (m) => '${m.group(1)}.${m.group(2)}')
        .replaceAll(_overrideTag, '');
    return 'WEBVTT\n\n$body\n';
  }

  /// Converts an ASS/SSA file to WebVTT, keeping timing and text and discarding
  /// the rest.
  ///
  /// The `Format:` line is read rather than assumed: the field order is not
  /// fixed, and the text field is always last and may itself contain commas, so
  /// the earlier fields are split on the first N-1 commas and everything left
  /// over is the text.
  static String assToVtt(String input) {
    final withoutBom = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final lines = withoutBom
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    var inEvents = false;
    var format = const [
      'layer',
      'start',
      'end',
      'style',
      'name',
      'marginl',
      'marginr',
      'marginv',
      'effect',
      'text',
    ];
    final cues = <_AssCue>[];

    for (final raw in lines) {
      final line = raw.trim();
      if (_sectionHeader.hasMatch(line)) {
        inEvents = _eventsOnly.hasMatch(line);
        continue;
      }
      if (!inEvents) continue;
      if (_formatLine.hasMatch(line)) {
        format = line
            .substring(line.indexOf(':') + 1)
            .split(',')
            .map((f) => f.trim().toLowerCase())
            .toList();
        continue;
      }
      if (!_dialogue.hasMatch(line)) continue;

      final body = line
          .substring(line.indexOf(':') + 1)
          .replaceFirst(RegExp(r'^ '), '');
      final fields = <String>[];
      var rest = body;
      for (var i = 0; i < format.length - 1; i++) {
        final comma = rest.indexOf(',');
        if (comma < 0) break;
        fields.add(rest.substring(0, comma));
        rest = rest.substring(comma + 1);
      }
      fields.add(rest);

      final startIndex = format.indexOf('start');
      final endIndex = format.indexOf('end');
      final textIndex = format.indexOf('text');
      final start = startIndex >= 0 && startIndex < fields.length
          ? _assTime(fields[startIndex])
          : null;
      final end = endIndex >= 0 && endIndex < fields.length
          ? _assTime(fields[endIndex])
          : null;
      if (start == null || end == null || end <= start) continue;

      var text = textIndex >= 0 && textIndex < fields.length
          ? fields[textIndex]
          : '';
      // Vector drawings ({\p1}…) are shapes, not words, and would render as
      // gibberish.
      if (_hasDrawingCommand(text)) continue;
      text = _removeOverrideTags(text)
          .replaceAll(r'\N', '\n')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\h', ' ')
          .trim();
      if (text.isEmpty) continue;
      cues.add(_AssCue(start, end, text));
    }

    cues.sort(
      (a, b) => a.start != b.start
          ? a.start.compareTo(b.start)
          : a.end.compareTo(b.end),
    );
    final sb = StringBuffer('WEBVTT\n\n');
    for (var i = 0; i < cues.length; i++) {
      if (i > 0) sb.write('\n\n');
      final c = cues[i];
      sb
        ..write(_vttTime(c.start))
        ..write(' --> ')
        ..write(_vttTime(c.end))
        ..write('\n')
        ..write(_escapeCueText(c.text));
    }
    sb.write('\n');
    return sb.toString();
  }

  /// Whether the text carries an ASS vector-drawing command (`{\p1}`).
  ///
  /// A drawing is a shape, not words: its payload is a list of coordinates that
  /// would render as gibberish. The whole cue is dropped rather than shown.
  static bool _hasDrawingCommand(String text) {
    var index = 0;
    while (true) {
      final open = text.indexOf('{', index);
      if (open < 0) return false;
      final close = text.indexOf('}', open);
      if (close < 0) return false;
      final body = text.substring(open + 1, close);
      // `\p1`..`\p9` starts a drawing; `\p0` ends one.
      if (_drawingStart.hasMatch(body)) return true;
      index = close + 1;
    }
  }

  /// [text] with every `{...}` override block removed.
  static String _removeOverrideTags(String text) {
    final sb = StringBuffer();
    var index = 0;
    while (index < text.length) {
      if (text[index] == '{') {
        final close = text.indexOf('}', index);
        index = close < 0 ? text.length : close + 1;
      } else {
        sb.write(text[index]);
        index++;
      }
    }
    return sb.toString();
  }

  /// Parses an ASS timestamp (`h:mm:ss.cc`) to seconds, or null when it is not
  /// one.
  static double? _assTime(String value) {
    final m = RegExp(
      r'^(\d+):(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$',
    ).firstMatch(value.trim());
    if (m == null) return null;
    final frac = (m.group(4) ?? '').padRight(3, '0');
    final millis = frac.isEmpty ? 0 : int.parse(frac.substring(0, 3));
    return int.parse(m.group(1)!) * 3600.0 +
        int.parse(m.group(2)!) * 60.0 +
        int.parse(m.group(3)!) +
        millis / 1000.0;
  }

  static String _vttTime(double seconds) {
    final total = (seconds * 1000).round().clamp(0, 1 << 62);
    final h = total ~/ 3600000;
    final m = (total % 3600000) ~/ 60000;
    final s = (total % 60000) ~/ 1000;
    final ms = total % 1000;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${ms.toString().padLeft(3, '0')}';
  }

  static String _escapeCueText(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

class _AssCue {
  const _AssCue(this.start, this.end, this.text);
  final double start;
  final double end;
  final String text;
}
