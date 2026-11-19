/// Reading a subtitle file into timed cues, so the dub can speak at the right
/// moment instead of guessing from the picture.
///
/// Only SRT is parsed here. It is the format nearly every provider hands us,
/// it is plain text, and it needs no native decoder — the other formats the
/// player can display are handled by mpv/libass internally, which gives us no
/// text to speak.
///
/// The parser is deliberately forgiving: real subtitle files carry BOMs, CRLF
/// line endings, missing blank lines between blocks, HTML tags and stray
/// numeric indices. A cue that cannot be understood is dropped, not fatal —
/// one bad block must not silence the whole episode.
library;

/// One subtitle cue: when it appears, when it ends, and what it says.
class DubCue {
  const DubCue({
    required this.start,
    required this.end,
    required this.text,
  });

  final Duration start;
  final Duration end;

  /// The cue's words, with markup removed and lines joined. Empty cues are
  /// filtered out at parse time, so this is never blank.
  final String text;

  Duration get duration => end - start;

  @override
  String toString() => 'DubCue($start–$end: $text)';

  @override
  bool operator ==(Object other) =>
      other is DubCue &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}

abstract final class SrtParser {
  /// `00:01:02,345 --> 00:01:05,678`, tolerating `.` as the decimal separator
  /// (common in files written by tools that treat SRT like VTT) and one or two
  /// digits of milliseconds.
  static final RegExp _timing = RegExp(
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*'
    r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})',
  );

  /// A bare cue index: digits alone on a line.
  static final RegExp _index = RegExp(r'^\d+$');

  static final RegExp _tag = RegExp(r'<[^>]*>');
  static final RegExp _assOverride = RegExp(r'\{[^}]*\}');

  /// Parse [source] into cues ordered by start time.
  ///
  /// Returns an empty list for anything unparseable rather than throwing: the
  /// caller's fallback (no narration) is better than a crash mid-playback.
  static List<DubCue> parse(String source) {
    if (source.trim().isEmpty) return const [];

    // Normalise the three things that most often break a naive split: a BOM,
    // CRLF, and the run-together blocks some encoders emit.
    final text = source
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    final cues = <DubCue>[];
    final lines = text.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final match = _timing.firstMatch(lines[i]);
      if (match == null) continue;

      final start = _toDuration(match, 1);
      final end = _toDuration(match, 5);
      if (start == null || end == null) continue;

      // The body runs to the next block. Three things end it: a blank line
      // (the usual separator), a timing line, or a bare numeric index that the
      // following line times — the last is what catches blocks written with no
      // blank line between them, where the next cue's index would otherwise be
      // read as part of this cue's dialogue.
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length) {
        final line = lines[j];
        if (line.trim().isEmpty || _timing.hasMatch(line)) break;
        final nextIsTiming = j + 1 < lines.length && _timing.hasMatch(lines[j + 1]);
        if (_index.hasMatch(line.trim()) && nextIsTiming) break;
        body.add(line);
        j++;
      }
      i = j - 1;

      final spoken = _clean(body.join(' '));
      // An end at or before the start would make a zero/negative window; the
      // scheduler could never fit speech into it, so drop it here.
      if (spoken.isEmpty || end <= start) continue;

      cues.add(DubCue(start: start, end: end, text: spoken));
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return cues;
  }

  static Duration? _toDuration(RegExpMatch m, int firstGroup) {
    int part(int offset) => int.parse(m.group(firstGroup + offset)!);
    final ms = part(3);
    // 1 digit means tenths, 2 means hundredths, 3 means milliseconds.
    final millis = switch (m.group(firstGroup + 3)!.length) {
      1 => ms * 100,
      2 => ms * 10,
      _ => ms,
    };
    return Duration(
      hours: part(0),
      minutes: part(1),
      seconds: part(2),
      milliseconds: millis,
    );
  }

  /// Strip markup and collapse whitespace, so the engine is not asked to
  /// pronounce `<i>` or a stray `{\an8}`.
  static String _clean(String raw) {
    var out = raw.replaceAll(_assOverride, ' ');
    out = out.replaceAll(_tag, ' ');
    // "&nbsp;" and friends arrive in HTML-derived subtitles.
    out = out
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return out.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
