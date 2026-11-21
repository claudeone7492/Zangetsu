import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// A small, user-managed allowlist for redirects.
///
/// An entry containing a dot is a host (and its subdomains); a dot-less entry
/// is matched as a substring of the whole URL. The list exists because an ad
/// host list occasionally names a host a provider needs to bounce through; the
/// browser consults this before [AdBlock] decides to block.
class RedirectAllow {
  RedirectAllow._();

  static final RedirectAllow instance = RedirectAllow._();

  static const String boxName = 'redirect_allow';

  Box<dynamic>? _box;

  Future<void> init() async {
    _box ??= await openBoxSafely<dynamic>(boxName);
  }

  Box<dynamic> get _db {
    final box = _box;
    if (box == null) {
      throw StateError('RedirectAllow.init() must run before use');
    }
    return box;
  }

  List<String> get entries => [
    for (final raw in (_db.get('entries') as List? ?? const []))
      if (raw is String && raw.trim().isNotEmpty) raw.trim(),
  ];

  Future<void> set(List<String> list) async {
    final clean = <String>[];
    for (final raw in list) {
      final entry = normalise(raw);
      if (entry.isNotEmpty && !clean.contains(entry)) clean.add(entry);
    }
    await _db.put('entries', clean);
  }

  bool allows(Uri uri) {
    final url = uri.toString().toLowerCase();
    final host = uri.host.toLowerCase();
    for (final raw in entries) {
      final entry = normalise(raw);
      if (entry.isEmpty) continue;
      if (entry.contains('.')) {
        if (host.isNotEmpty &&
            (host == entry || host.endsWith('.$entry'))) {
          return true;
        }
      } else if (url.contains(entry)) {
        return true;
      }
    }
    return false;
  }

  /// `https://Example.com:443/path` → `example.com`; a bare word stays a word.
  static String normalise(String raw) {
    var text = raw.trim().toLowerCase();
    if (text.isEmpty) return '';
    text = text.replaceFirst(RegExp(r'^[a-z][a-z0-9+.-]*://'), '');
    text = text.split('/').first;
    text = text.split('?').first;
    text = text.split(':').first;
    return text.replaceFirst(RegExp(r'^www\.'), '');
  }
}
