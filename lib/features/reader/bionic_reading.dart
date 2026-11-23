import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Bolds the first part of every word so the eye has a fixed anchor to track.
///
/// Ported from the bionic-reading option in LNReader's reader, which wraps the
/// same word prefixes in `<b>` before the chapter reaches the WebView. Doing it
/// on the parsed DOM (rather than with a regex over the raw markup) keeps tags,
/// entities, and attribute values intact — a regex that bolds "words" inside
/// `href="..."` corrupts links and images.
String applyBionicReading(String html) {
  final fragment = html_parser.parseFragment(html);
  _boldPrefixes(fragment.nodes);
  return fragment.outerHtml;
}

void _boldPrefixes(List<dom.Node> nodes) {
  for (final node in nodes.toList(growable: false)) {
    if (node is dom.Text) {
      final text = node.text;
      if (text.trim().isEmpty) continue;
      final replacement = _bionicFragment(node, text);
      if (replacement != null) node.replaceWith(replacement);
      continue;
    }
    if (node is dom.Element) {
      final tag = node.localName;
      if (tag == 'script' || tag == 'style' || tag == 'b' || tag == 'strong') {
        continue;
      }
      _boldPrefixes(node.nodes);
    }
  }
}

dom.DocumentFragment? _bionicFragment(dom.Text source, String text) {
  final matches = _word.allMatches(text).toList(growable: false);
  if (matches.isEmpty) return null;

  final fragment = dom.DocumentFragment();
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      fragment.nodes.add(dom.Text(text.substring(cursor, match.start)));
    }
    final word = match.group(0)!;
    final runes = word.runes.toList(growable: false);
    final prefixLength = _prefixLength(runes.length);
    if (prefixLength <= 0) {
      fragment.nodes.add(dom.Text(word));
    } else if (prefixLength >= runes.length) {
      fragment.nodes.add(dom.Element.tag('b')..text = word);
    } else {
      fragment.nodes.add(
        dom.Element.tag('b')
          ..text = String.fromCharCodes(runes.take(prefixLength)),
      );
      fragment.nodes.add(
        dom.Text(String.fromCharCodes(runes.skip(prefixLength))),
      );
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    fragment.nodes.add(dom.Text(text.substring(cursor)));
  }
  return fragment;
}

final RegExp _word = RegExp(r'[\p{L}\p{Nd}]+', unicode: true);

/// One letter for one-letter words, otherwise roughly 40% of the word with a
/// five-character ceiling. That is the range bionic readers settle on: enough
/// contrast to anchor the eye without turning the page into bold text.
int _prefixLength(int length) {
  if (length <= 1) return length;
  final raw = (length * 0.4).ceil();
  return raw < 1 ? 1 : (raw > 5 ? 5 : raw);
}
