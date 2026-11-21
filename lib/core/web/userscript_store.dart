import 'dart:convert';

import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// One installed userscript, in the `==UserScript==` format Tampermonkey and
/// Greasemonkey use. Only the metadata needed to decide where it runs is
/// parsed; the body is kept verbatim and handed to the WebView.
class Userscript {
  const Userscript({
    required this.id,
    required this.name,
    required this.matches,
    required this.code,
    this.enabled = true,
  });

  final String id;
  final String name;
  final List<String> matches;
  final String code;
  final bool enabled;

  bool matchesUrl(Uri uri) =>
      enabled && matches.any((pattern) => matchesPattern(pattern, uri));

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'matches': matches,
    'code': code,
    'enabled': enabled,
  };

  factory Userscript.fromMap(Map<dynamic, dynamic> map) => Userscript(
    id: (map['id'] ?? '').toString(),
    name: (map['name'] ?? 'Userscript').toString(),
    matches: [
      for (final m in (map['matches'] as List? ?? const []))
        if (m is String && m.trim().isNotEmpty) m.trim(),
    ],
    code: (map['code'] ?? '').toString(),
    enabled: map['enabled'] != false,
  );

  /// `*://*.example.com/*`, `https://example.com/*`, `*://*/*` and `/regex/`.
  static bool matchesPattern(String pattern, Uri uri) {
    final p = pattern.trim();
    if (p.isEmpty) return false;
    if (p.startsWith('/') && p.endsWith('/') && p.length > 2) {
      try {
        return RegExp(p.substring(1, p.length - 1)).hasMatch(uri.toString());
      } catch (_) {
        return false;
      }
    }
    final m = RegExp(
      r'^(\*|https?|file|ftp)://([^/]*)(/.*)?$',
    ).firstMatch(p);
    if (m == null) return false;
    final scheme = m.group(1)!;
    final hostPattern = m.group(2)!;
    final pathPattern = m.group(3) ?? '/*';
    if (scheme != '*' && scheme != uri.scheme) return false;

    final host = uri.host.toLowerCase();
    if (hostPattern != '*') {
      if (hostPattern.startsWith('*.')) {
        final base = hostPattern.substring(2).toLowerCase();
        if (host != base && !host.endsWith('.$base')) return false;
      } else if (host != hostPattern.toLowerCase()) {
        return false;
      }
    }
    if (pathPattern == '/*' || pathPattern == '*' || pathPattern.isEmpty) {
      return true;
    }
    final glob = RegExp.escape(pathPattern).replaceAll(r'\*', '.*');
    final path = uri.path.isEmpty ? '/' : uri.path;
    return RegExp('^$glob\$').hasMatch(path);
  }
}

/// Installed userscripts, stored in one Hive box.
class UserscriptStore {
  UserscriptStore._();

  static final UserscriptStore instance = UserscriptStore._();

  static const String boxName = 'userscripts';

  Box<dynamic>? _box;

  Future<void> init() async {
    _box ??= await openBoxSafely<dynamic>(boxName);
  }

  Box<dynamic> get _db {
    final box = _box;
    if (box == null) {
      throw StateError('UserscriptStore.init() must run before use');
    }
    return box;
  }

  List<Userscript> get all => [
    for (final value in _db.values)
      if (value is Map) Userscript.fromMap(value),
  ];

  Future<Userscript> addText(String text) async {
    final parsed = parse(text);
    if (parsed == null) {
      throw const FormatException('No ==UserScript== metadata found');
    }
    final entry = Userscript(
      id: _newId(),
      name: parsed.name,
      matches: parsed.matches,
      code: text,
    );
    await _db.put(entry.id, entry.toMap());
    return entry;
  }

  Future<Userscript> add({
    required String name,
    required List<String> matches,
    required String code,
  }) async {
    final entry = Userscript(
      id: _newId(),
      name: name.trim().isEmpty ? 'Userscript' : name.trim(),
      matches: matches.isEmpty ? const ['*://*/*'] : matches,
      code: code,
    );
    await _db.put(entry.id, entry.toMap());
    return entry;
  }

  Future<void> remove(String id) => _db.delete(id);

  Future<void> setEnabled(String id, bool enabled) async {
    final raw = _db.get(id);
    if (raw is! Map) return;
    final entry = Userscript.fromMap(raw);
    await _db.put(
      id,
      Userscript(
        id: entry.id,
        name: entry.name,
        matches: entry.matches,
        code: entry.code,
        enabled: enabled,
      ).toMap(),
    );
  }

  List<Userscript> scriptsFor(Uri uri) =>
      [for (final script in all) if (script.matchesUrl(uri)) script];

  /// Reads `@name` and `@match` / `@include` from the metadata block. Returns
  /// null when the text is not a userscript at all, so the caller can show a
  /// parse error instead of installing an inert file.
  static Userscript? parse(String text) {
    final block = RegExp(
      r'==UserScript==([\s\S]*?)==/UserScript==',
    ).firstMatch(text)?.group(1);
    if (block == null) return null;
    String? name;
    final matches = <String>[];
    for (final line in const LineSplitter().convert(block)) {
      final m = RegExp(
        r'@(name|match|include)\s+(.+)$',
      ).firstMatch(line.trim());
      if (m == null) continue;
      final value = m.group(2)!.trim();
      if (value.isEmpty) continue;
      if (m.group(1) == 'name') {
        name ??= value;
      } else {
        matches.add(value);
      }
    }
    if (name == null && matches.isEmpty) return null;
    return Userscript(
      id: '',
      name: name ?? 'Userscript',
      matches: matches.isEmpty ? const ['*://*/*'] : matches,
      code: text,
    );
  }

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
