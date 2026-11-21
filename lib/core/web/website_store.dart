import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'website.dart';

/// The viewer's saved websites, newest first.
///
/// Its own box for the same reason as `TelegramPrefs`: a self-contained
/// surface, and one clear decision in the backup drift guard.
class WebsiteStore extends ChangeNotifier {
  WebsiteStore._(this._box);

  @visibleForTesting
  WebsiteStore.forTesting(Box box) : this._(box);

  final Box _box;

  static const String boxName = 'websites';

  static Future<WebsiteStore> open() async {
    final box = await openBoxSafely<dynamic>(boxName);
    return WebsiteStore._(box);
  }

  List<Website> get sites {
    final raw = _box.get('sites');
    if (raw is! List) return const [];
    final out = <Website>[];
    for (final entry in raw) {
      final site = Website.fromMap(entry);
      if (site != null) out.add(site);
    }
    return out;
  }

  /// Adds [url] if it parses. Returns the saved site, or null.
  Future<Website?> add(String name, String url) async {
    final normalised = Website.normaliseUrl(url);
    if (normalised == null) return null;
    final site = Website.fromUrl(name, normalised);
    final next = [site, ...sites.where((s) => s.id != site.id)];
    await _write(next);
    return site;
  }

  Future<void> remove(String id) async {
    await _write(sites.where((s) => s.id != id).toList());
  }

  Future<void> _write(List<Website> sites) async {
    await _box.put('sites', [for (final s in sites) s.toMap()]);
    notifyListeners();
  }
}
