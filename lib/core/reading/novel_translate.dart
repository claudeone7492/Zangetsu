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
