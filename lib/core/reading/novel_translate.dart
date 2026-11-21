typedef TranslateFn = Future<String> Function(String text);

/// Translates a chapter in paragraph-aligned chunks under the request limit.
class NovelTranslate {
  const NovelTranslate._();

  static const int maxChunk = 4000;

  static List<String> chunks(String text, {int max = maxChunk}) {
    if (text.isEmpty) return const [];
    if (text.length <= max) return [text];
    final out = <String>[];
    final buffer = StringBuffer();
    for (final paragraph in text.split(RegExp(r'\n\s*\n'))) {
      final piece = paragraph.trim();
      if (piece.isEmpty) continue;
      if (buffer.length + piece.length + 2 > max && buffer.isNotEmpty) {
        out.add(buffer.toString().trim());
        buffer.clear();
      }
      if (piece.length > max) {
        for (var i = 0; i < piece.length; i += max) {
          out.add(piece.substring(i, (i + max).clamp(0, piece.length)));
        }
        continue;
      }
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(piece);
    }
    if (buffer.isNotEmpty) out.add(buffer.toString().trim());
    return out;
  }

  /// The readable text of an HTML chapter, ready for [translate].
  ///
  /// Only text is kept: scripts, styles, tags and entities go, while paragraph
  /// and line breaks survive so the translation still reads as prose.
  static String plainText(String html) {
    var text = html
        .replaceAll(
          RegExp(
            r'<(script|style)\b[^>]*>[\s\S]*?</\1>',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(r'</(p|div|h[1-6]|li|blockquote)>', caseSensitive: false),
          '\n\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '');
    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&hellip;': '…',
      '&mdash;': '—',
      '&ndash;': '–',
    };
    entities.forEach((entity, value) => text = text.replaceAll(entity, value));
    return text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static Future<String> translate(String text, TranslateFn translate) async {
    final parts = chunks(text);
    if (parts.isEmpty) return text;
    final out = <String>[];
    for (final part in parts) {
      out.add(await translate(part));
    }
    return out.join('\n\n');
  }
}
