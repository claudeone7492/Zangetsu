/// One caption cue: when it shows, and the text it shows.
class SubtitleCue {
  const SubtitleCue({
    required this.startMillis,
    required this.endMillis,
    required this.text,
  });

  final int startMillis;
  final int endMillis;
  final String text;
}

/// Writes a loaded caption track out as a subtitle file the viewer keeps.
///
/// This is the other half of the file picker. The picker reads a caption in;
/// without this there is no way to get one back out, which matters for the two
/// cases the app creates a caption itself: a transcription and a translation are
/// produced by the app and exist only in memory, so if they cannot be exported
/// they are lost the moment the player closes.
///
/// The output is SubRip. It is the format every other player reads, so an
/// exported caption is useful outside this app — which is the point of exporting
/// it rather than just caching it.
class SubtitleExporter {
  const SubtitleExporter._();

  /// A filesystem-safe name built from [title].
  ///
  /// A title is free text and can carry `/`, `:`, quotes and more, any of which
  /// would either fail the write or create a directory. Everything outside a
  /// conservative set is replaced with an underscore, and the result is capped so
  /// a long title cannot overflow the filename limit.
  static String fileName(String title) {
    final stem = title
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '_')
        .replaceAll(RegExp('_+'), '_')
        .replaceAll(RegExp(r'^[_. ]+|[_. ]+$'), '')
        .trim();
    final capped = stem.length > 60 ? stem.substring(0, 60) : stem;
    return '${capped.isEmpty ? 'subtitles' : capped}.srt';
  }

  /// The SubRip body, one numbered block per cue. Cues are sorted by start time;
  /// a blank line separates blocks, which SRT readers are strict about.
  static String toSrt(List<SubtitleCue> cues) {
    final sorted = [...cues]
      ..sort((a, b) => a.startMillis.compareTo(b.startMillis));
    final sb = StringBuffer();
    for (var i = 0; i < sorted.length; i++) {
      final cue = sorted[i];
      sb
        ..writeln(i + 1)
        ..writeln(
          '${timestamp(cue.startMillis)} --> ${timestamp(cue.endMillis)}',
        )
        ..writeln(cue.text.trim())
        ..writeln();
    }
    return sb.toString();
  }

  /// `HH:MM:SS,mmm`, the SubRip timestamp, which uses a comma where VTT uses a
  /// dot.
  static String timestamp(int millis) {
    final safe = millis < 0 ? 0 : millis;
    final h = safe ~/ 3600000;
    final m = (safe % 3600000) ~/ 60000;
    final s = (safe % 60000) ~/ 1000;
    final ms = safe % 1000;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')},'
        '${ms.toString().padLeft(3, '0')}';
  }

  /// Parses SRT/VTT [content] into cues, stripping styling. Cues with no text
  /// after stripping are dropped, so an image-based track parses to nothing.
  static List<SubtitleCue> parseCues(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final cues = <SubtitleCue>[];
    var i = 0;
    while (i < lines.length) {
      final m = _tsPair.firstMatch(lines[i]);
      if (m == null) {
        i++;
        continue;
      }
      final start = _timestampMillis(m.group(1)!);
      final end = _timestampMillis(m.group(2)!);
      i++;
      final buf = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        buf.add(lines[i]);
        i++;
      }
      final clean = buf
          .join('\n')
          .replaceAll(_assTag, '')
          .replaceAll(_htmlTag, '')
          .trim();
      if (clean.isNotEmpty && start != null && end != null) {
        cues.add(SubtitleCue(startMillis: start, endMillis: end, text: clean));
      }
    }
    return cues;
  }

  static final RegExp _tsPair = RegExp(
    r'(\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}|\d{1,2}:\d{2}[.,]\d{1,3})\s*-->\s*'
    r'(\d{1,2}:\d{2}:\d{2}[.,]\d{1,3}|\d{1,2}:\d{2}[.,]\d{1,3})',
  );
  static final RegExp _htmlTag = RegExp(r'<[^>]*>');
  static final RegExp _assTag = RegExp(r'\{[^}]*\}');

  static int? _timestampMillis(String ts) {
    final t = ts.trim().replaceAll(',', '.');
    final dot = t.indexOf('.');
    final clock = dot < 0 ? t : t.substring(0, dot);
    var ms = dot < 0 ? '0' : t.substring(dot + 1);
    ms = ms.padRight(3, '0').substring(0, 3);
    final parts = clock.split(':').map(int.tryParse).toList();
    if (parts.any((p) => p == null)) return null;
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p!;
    }
    return seconds * 1000 + int.parse(ms);
  }
}
