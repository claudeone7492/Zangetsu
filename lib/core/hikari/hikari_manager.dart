import 'package:flutter/foundation.dart';

import 'hikari_provider.dart';

/// Holds the loaded `.hiki` providers — the Hikari twin of `MihonManager`.
///
/// Sources are keyed by their own `hiki:<providerId>` id, so routing is a plain
/// map lookup and an extension's own id decides its identity (two extensions
/// that both call themselves "Anime" stay distinct).
class HikariManager extends ChangeNotifier {
  final Map<String, HikariProviderAdapter> _sources = {};

  /// Every loaded provider.
  List<HikariProviderAdapter> get all => _sources.values.toList();

  /// Every loaded, enabled provider. Enablement is currently all-or-nothing:
  /// an extension is loaded or it isn't.
  List<HikariProviderAdapter> get enabled => all;

  /// Resolves a `hiki:<id>` source id, or null when not installed.
  HikariProviderAdapter? get(String sourceId) => _sources[sourceId];

  /// Registers [provider], replacing any existing entry with the same id.
  void register(HikariProviderAdapter provider) {
    _sources[provider.sourceId] = provider;
    notifyListeners();
  }

  /// Removes providers matching [predicate]; notifies only when one went.
  void removeWhere(bool Function(HikariProviderAdapter provider) predicate) {
    final gone = _sources.entries
        .where((e) => predicate(e.value))
        .map((e) => e.key)
        .toList();
    for (final k in gone) {
      _sources.remove(k);
    }
    if (gone.isNotEmpty) notifyListeners();
  }

  /// Drops everything — used when the installed box is rebuilt from scratch.
  void clear() {
    if (_sources.isEmpty) return;
    _sources.clear();
    notifyListeners();
  }
}
