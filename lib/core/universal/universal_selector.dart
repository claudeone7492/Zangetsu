import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Tiny selector evaluator for universal scraper rules.
///
/// A rule is `selector` or `selector@attr`:
///  * `".result-item"`     → the element's text, trimmed
///  * `"a@href"`           → the `href` attribute
///  * `"img@data-src"`     → any attribute
///
/// A selector may be a CSS-ish chain (`".card .title"`) or a comma list of
/// fallbacks (`"h1, .title"`), the first hit winning. Kept deliberately small —
/// no full CSS engine — because a scraper config only ever needs a class/id/tag
/// path and an optional attribute.
class UniversalSelector {
  const UniversalSelector._();

  /// Parse an HTML document once per page.
  static dom.Document parse(String body) => html_parser.parse(body);

  /// Split `"a@href"` into selector + attribute. Attribute is null for text.
  static (String, String?) _split(String rule) {
    final at = rule.lastIndexOf('@');
    if (at <= 0) return (rule.trim(), null);
    return (rule.substring(0, at).trim(), rule.substring(at + 1).trim());
  }

  /// The first element matching [rule]'s selector, or null.
  static dom.Element? firstElement(dom.Document doc, String rule) {
    final (sel, _) = _split(rule);
    if (sel.isEmpty) return null;
    for (final part in sel.split(',')) {
      final el = _firstFor(doc, part.trim());
      if (el != null) return el;
    }
    return null;
  }

  /// Every element matching [rule]'s selector, in document order.
  static List<dom.Element> elements(dom.Document doc, String rule) {
    final (sel, _) = _split(rule);
    if (sel.isEmpty) return const [];
    final out = <dom.Element>[];
    for (final part in sel.split(',')) {
      out.addAll(_allFor(doc, part.trim()));
    }
    return out;
  }

  /// Read one field: text, or an attribute when the rule says `@attr`.
  /// Returns null when nothing matches (callers drop empty fields).
  static String? read(dom.Document doc, String rule) {
    final el = firstElement(doc, rule);
    return _value(el, rule);
  }

  /// Read a field from an already-scoped element (a list item).
  static String? readIn(dom.Element scope, String rule) {
    final el = _firstFor(scope, _split(rule).$1.trim());
    return _value(el, rule);
  }

  static String? _value(dom.Element? el, String rule) {
    if (el == null) return null;
    final (_, attr) = _split(rule);
    final raw = attr != null
        ? (attr == 'text' ? el.text : el.attributes[attr])
        : el.text;
    final v = (raw ?? '').trim();
    return v.isEmpty ? null : v;
  }

  /// First descendant-or-self matching a single (non-comma) selector path.
  static dom.Element? _firstFor(dom.Node scope, String selector) {
    final els = _allFor(scope, selector);
    return els.isEmpty ? null : els.first;
  }

  /// All descendants matching a single (non-comma) selector path.
  static List<dom.Element> _allFor(dom.Node scope, String selector) {
    if (selector.isEmpty) return const [];
    final parts = selector.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return const [];

    // Walk the path one simple selector at a time.
    var current = <dom.Element>[
      if (scope is dom.Element) scope else ...scope.children,
    ];
    // If the first part is a descendant of `scope` (typical), start from all
    // elements under scope; if scope itself matches, keep it (readIn case).
    for (var i = 0; i < parts.length; i++) {
      final simple = parts[i];
      final isFirst = i == 0;
      final next = <dom.Element>[];
      final pool = isFirst
          ? _descendantsAndSelf(scope)
          : current.expand(_descendantsAndSelf);
      for (final el in pool) {
        if (_matchesSimple(el, simple)) next.add(el);
      }
      if (isFirst) {
        // For the first part, if scope itself is not the target we still want
        // matches anywhere beneath it, which `pool` already covers.
      }
      current = next;
      if (current.isEmpty) return const [];
    }
    return current;
  }

  static Iterable<dom.Element> _descendantsAndSelf(dom.Node node) sync* {
    if (node is dom.Element) yield node;
    for (final c in node.children) {
      yield* _descendantsAndSelf(c);
    }
  }

  /// Match one simple selector: `tag`, `.class`, `#id`, `[attr]`, `[attr=val]`.
  static bool _matchesSimple(dom.Element el, String simple) {
    var rest = simple;
    // Compound selectors like `a.btn` or `.card.alt` are split by the
    // leading token rules below; handle the common single-form cases plus
    // stacked class/id/attr by peeling them off.
    // Tag name prefix.
    final tagMatch = RegExp(r'^[a-zA-Z][a-zA-Z0-9-]*').firstMatch(rest);
    if (tagMatch != null) {
      if (el.localName?.toLowerCase() != tagMatch.group(0)!.toLowerCase()) {
        return false;
      }
      rest = rest.substring(tagMatch.group(0)!.length);
    }
    // Peel `.class`, `#id`, `[attr]`, `[attr=val]` in any order.
    final token = RegExp(r'(?:\.([\w-]+)|#([\w-]+)|\[([\w-]+)(?:([~|^$*]?)=([^\]]+))?\])');
    var consumed = 0;
    for (final m in token.allMatches(rest)) {
      consumed += m.group(0)!.length;
      if (m.group(1) != null) {
        if (!el.classes.contains(m.group(1))) return false;
      } else if (m.group(2) != null) {
        if (el.id != m.group(2)) return false;
      } else if (m.group(3) != null) {
        final name = m.group(3)!;
        final op = m.group(4) ?? '';
        final want = m.group(5)?.replaceAll(RegExp(r'''^["']|["']$'''), '');
        if (!el.attributes.containsKey(name)) return false;
        if (want != null) {
          final have = el.attributes[name] ?? '';
          final ok = switch (op) {
            '*' => have.contains(want),
            '^' => have.startsWith(want),
            r'$' => have.endsWith(want),
            '~' => have.split(' ').contains(want),
            '|' => have == want || have.startsWith('$want-'),
            _ => have == want,
          };
          if (!ok) return false;
        }
      }
    }
    // Anything left over is unsupported syntax — treat as a non-match so a
    // bad rule drops the field instead of silently matching everything.
    if (consumed < rest.length) return false;
    return true;
  }
}

/// Substitute `{query}`, `{page}`, `{href}`, `{id}`, `{ep}`, `{lang}` in a
/// template and resolve the result against a base URL.
String resolveTemplate(
  String template, {
  String base = '',
  String? query,
  int? page,
  String? href,
  String? id,
  String? ep,
  String? lang,
}) {
  var out = template
      .replaceAll('{query}', Uri.encodeQueryComponent(query ?? ''))
      .replaceAll('{q}', Uri.encodeQueryComponent(query ?? ''))
      .replaceAll('{page}', (page ?? 1).toString())
      .replaceAll('{href}', href ?? '')
      .replaceAll('{id}', id ?? '')
      .replaceAll('{ep}', ep ?? '')
      .replaceAll('{lang}', lang ?? '');
  if (out.startsWith('http://') || out.startsWith('https://')) return out;
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final p = out.startsWith('/') ? out : '/$out';
  return '$b$p';
}
