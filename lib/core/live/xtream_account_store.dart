import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'xtream_api.dart';

/// Credentials live in secure storage, never in Hive: an Xtream password grants
/// the whole subscription, and a Hive box is plaintext on disk.
class XtreamAccountStore extends ChangeNotifier {
  XtreamAccountStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'xtream_accounts';

  final FlutterSecureStorage _storage;
  final List<XtreamAccount> _accounts = [];
  var _loaded = false;

  List<XtreamAccount> get accounts => List.unmodifiable(_accounts);
  bool get isEmpty => _accounts.isEmpty;

  /// Reads the accounts once. Idempotent, so the add flow, the Live TV page and
  /// a test can all await it and share one read.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is! Map) continue;
        try {
          _accounts.add(
            XtreamAccount.fromJson(Map<String, dynamic>.from(entry)),
          );
        } catch (e) {
          debugPrint('[xtream] dropping unreadable account: $e');
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[xtream] account read failed: $e');
    }
  }

  /// Add or replace an account. The id is derived from host+username, so
  /// re-adding the same line updates its password rather than duplicating it.
  Future<XtreamAccount> add({
    required String host,
    required String username,
    required String password,
    String label = '',
  }) async {
    await ensureLoaded();
    final normalized = XtreamAccount.normalizeHost(host);
    if (normalized.isEmpty) {
      throw XtreamException('Enter the panel address');
    }
    if (username.trim().isEmpty) {
      throw XtreamException('Enter the username');
    }
    final account = XtreamAccount(
      id: XtreamAccount.idFor(normalized, username),
      host: normalized,
      username: username.trim(),
      password: password,
      label: label.trim(),
    );
    _accounts.removeWhere((a) => a.id == account.id);
    _accounts.add(account);
    await _persist();
    notifyListeners();
    return account;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    _accounts.removeWhere((a) => a.id == id);
    await _persist();
    notifyListeners();
  }

  XtreamAccount? byId(String id) {
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<void> _persist() async {
    await _storage.write(
      key: _key,
      value: jsonEncode([for (final a in _accounts) a.toJson()]),
    );
  }
}
