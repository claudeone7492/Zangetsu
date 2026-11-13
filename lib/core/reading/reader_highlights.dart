import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// One saved highlight: a passage the reader picked, tied to the chapter it
/// came from. Stored as JSON in an untyped Hive box so the schema can grow
/// without a migration — the same approach [ReaderPrefs] uses for its values.
@immutable
class ReaderHighlight {
  const ReaderHighlight({
    required this.id,
    required this.sourceId,
    required this.showId,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.text,
    required this.colorValue,
    required this.createdAt,
  });

  final String id;
  final String sourceId;
  final String showId;
  final String chapterUrl;
  final String chapterTitle;
  final String text;
  final int colorValue;
  final DateTime createdAt;

  ReaderHighlight copyWith({String? text, int? colorValue}) => ReaderHighlight(
    id: id,
    sourceId: sourceId,
    showId: showId,
    chapterUrl: chapterUrl,
    chapterTitle: chapterTitle,
    text: text ?? this.text,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'showId': showId,
    'chapterUrl': chapterUrl,
    'chapterTitle': chapterTitle,
    'text': text,
    'colorValue': colorValue,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  static ReaderHighlight? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final m = raw.cast<Object?, Object?>();
    final text = m['text'];
    if (text is! String || text.isEmpty) return null;
    return ReaderHighlight(
      id: (m['id'] as String?) ?? '',
      sourceId: (m['sourceId'] as String?) ?? '',
      showId: (m['showId'] as String?) ?? '',
      chapterUrl: (m['chapterUrl'] as String?) ?? '',
      chapterTitle: (m['chapterTitle'] as String?) ?? '',
      text: text,
      colorValue: (m['colorValue'] as num?)?.toInt() ?? 0xFFFFD54F,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (m['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// The four marker colours offered in the selection menu. Kept as raw ARGB
/// ints so the store stays free of `dart:ui` and a saved value can't be
/// invalidated by a theme change.
class HighlightColors {
  const HighlightColors._();

  static const List<int> all = [
    0xFFFFD54F, // amber
    0xFF81C784, // green
    0xFF64B5F6, // blue
    0xFFF06292, // pink
  ];

  static int next(int current) {
    final i = all.indexOf(current);
    return all[(i < 0 ? 0 : i + 1) % all.length];
  }
}

/// Persistent store of reader highlights, backed by a Hive box. Read anywhere
/// via `sl<ReaderHighlightStore>()`.
class ReaderHighlightStore {
  static const String boxName = 'reader_highlights';

  /// Opens the box. Call once during app bootstrap, alongside the other
  /// stores, before constructing.
  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) {
      await openBoxSafely(boxName);
    }
  }

  Box get _box => Hive.box(boxName);

  /// Stable per-passage id — a hash of the chapter URL plus the passage text,
  /// so highlighting the same sentence twice overwrites rather than stacking,
  /// while the same text in two chapters stays distinct.
  static String idFor(String chapterUrl, String text) =>
      '${chapterUrl.hashCode.toRadixString(36)}'
      '-${text.hashCode.toRadixString(36)}'
      '-${text.length}';

  /// Newest first.
  List<ReaderHighlight> all() {
    final list = <ReaderHighlight>[];
    for (final v in _box.values) {
      final h = ReaderHighlight.fromJson(v);
      if (h != null) list.add(h);
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// The chapter's highlights, keyed by [idFor] so the reader can look one up
  /// while building its context menu. Newest first.
  List<ReaderHighlight> forChapter(String chapterUrl) =>
      all().where((h) => h.chapterUrl == chapterUrl).toList();

  /// Look up a single highlight by the id [idFor] would produce.
  ReaderHighlight? byId(String id) {
    final h = ReaderHighlight.fromJson(_box.get(id));
    return h;
  }

  Future<void> add(ReaderHighlight highlight) =>
      _box.put(highlight.id, highlight.toJson());

  Future<void> remove(String id) => _box.delete(id);

  Future<void> update(String id, {String? text, int? colorValue}) async {
    final existing = byId(id);
    if (existing == null) return;
    await _box.put(id, existing.copyWith(text: text, colorValue: colorValue).toJson());
  }

  /// Adds or removes a highlight for [text] in [chapterUrl] — a tap toggles,
  /// so the selection menu's "Highlight" entry reads the same both ways.
  /// Returns the highlight that now exists, or null if it was removed.
  Future<ReaderHighlight?> toggle({
    required String sourceId,
    required String showId,
    required String chapterUrl,
    required String chapterTitle,
    required String text,
    required int colorValue,
  }) async {
    final id = idFor(chapterUrl, text);
    if (_box.containsKey(id)) {
      await remove(id);
      return null;
    }
    final h = ReaderHighlight(
      id: id,
      sourceId: sourceId,
      showId: showId,
      chapterUrl: chapterUrl,
      chapterTitle: chapterTitle,
      text: text,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    await add(h);
    return h;
  }
}

/// Wraps every occurrence of a chapter's saved highlights in
/// `<span style="background-color:…">` so the scroll reader (which renders HTML
/// via `HtmlWidget`) shows them. A plain `<span>` rather than `<mark>`: the
/// HTML package gives `<mark>` a default black text colour, which would be
/// invisible on the reader's dark theme, whereas a span simply inherits the
/// surrounding colour. Pure string work so it can be unit-tested without
/// pumping a widget.
String applyHighlightsToHtml(String html, List<ReaderHighlight> highlights) {
  if (highlights.isEmpty) return html;
  var out = html;
  for (final h in highlights) {
    final needle = _escapeHtml(h.text);
    if (needle.isEmpty) continue;
    final color = '#${(h.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    out = out.replaceAllMapped(
      _passagePattern(needle),
      (m) => '<span style="background-color:$color;">${m[0]}</span>',
    );
  }
  return out;
}

/// A regex matching [needle] with any run of whitespace wherever the passage
/// has a single space. A selection is normalised to single spaces (see
/// [normalizeHighlightText]) but the chapter HTML keeps its own newlines and
/// indentation, so a passage that spanned a line break would otherwise never
/// match on the next launch.
RegExp _passagePattern(String needle) => RegExp(
  needle.split(' ').map(RegExp.escape).join(r'\s+'),
);

/// The paged reader builds its pages from [InlineSpan]s rather than HTML, so
/// the same highlights are applied by splitting any span whose text contains a
/// saved passage and giving the matching run a [TextStyle.backgroundColor].
List<InlineSpan> applyHighlightsToSpans(
  List<InlineSpan> spans,
  List<ReaderHighlight> highlights,
) {
  if (highlights.isEmpty) return spans;
  final out = <InlineSpan>[];
  for (final span in spans) {
    if (span is! TextSpan || span.text == null || span.children != null) {
      out.add(span);
      continue;
    }
    out.addAll(_splitSpan(span, highlights));
  }
  return out;
}

List<InlineSpan> _splitSpan(TextSpan span, List<ReaderHighlight> highlights) {
  var text = span.text!;
  // Find the earliest matching highlight, emit the run before it plain, then
  // the run itself coloured, and repeat on the remainder. Matching is
  // whitespace-tolerant for the same reason as the HTML path.
  final result = <InlineSpan>[];
  while (text.isNotEmpty) {
    RegExpMatch? bestMatch;
    ReaderHighlight? best;
    for (final h in highlights) {
      if (h.text.isEmpty) continue;
      final m = _passagePattern(h.text).firstMatch(text);
      if (m != null && (bestMatch == null || m.start < bestMatch.start)) {
        bestMatch = m;
        best = h;
      }
    }
    if (best == null || bestMatch == null) {
      result.add(TextSpan(text: text, style: span.style));
      break;
    }
    if (bestMatch.start > 0) {
      result.add(
        TextSpan(text: text.substring(0, bestMatch.start), style: span.style),
      );
    }
    result.add(
      TextSpan(
        text: bestMatch[0],
        style: (span.style ?? const TextStyle()).copyWith(
          backgroundColor: Color(best.colorValue),
        ),
      ),
    );
    text = text.substring(bestMatch.end);
  }
  return result;
}

const Map<String, String> _kHtmlEscapes = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

/// Escapes the same five characters a browser would, so a highlighted passage
/// that itself contains `<`/`&` still matches the escaped chapter HTML.
String _escapeHtml(String s) {
  if (s.isEmpty) return s;
  final buf = StringBuffer();
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(_kHtmlEscapes[ch] ?? ch);
  }
  return buf.toString();
}

/// Small helper kept here so the store and the menu agree on how a passage is
/// normalised before it is hashed/compared: collapse runs of whitespace and
/// trim. A selection spanning a line break otherwise never matches the saved
/// text on the next launch.
String normalizeHighlightText(String text) =>
    text.replaceAll(RegExp(r'\s+'), ' ').trim();
