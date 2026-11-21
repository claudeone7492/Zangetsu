import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// Host-list ad blocking for the in-app browser.
///
/// The list is the same StevenBlack hosts file Hikari uses. Parsing keeps only
/// the hostnames (the `0.0.0.0` / `127.0.0.1` prefix is dropped) and the match
/// is exact, because a hosts file blocks a named host, not its whole subtree.
/// The parsed set is cached in memory; the raw list is persisted so blocking
/// survives a restart without a download.
class AdBlock {
  AdBlock._();

  static final AdBlock instance = AdBlock._();

  static const String boxName = 'ad_block';
  static const String listUrl =
      'https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts';

  Box<dynamic>? _box;
  Set<String>? _hosts;

  Future<void> init() async {
    _box ??= await openBoxSafely<dynamic>(boxName);
  }

  Box<dynamic> get _db {
    final box = _box;
    if (box == null) throw StateError('AdBlock.init() must run before use');
    return box;
  }

  bool get enabled => _db.get('enabled', defaultValue: false) == true;

  bool get promosEnabled => _db.get('promos', defaultValue: true) == true;

  int get hostCount => (_db.get('hosts') as List?)?.length ?? 0;

  DateTime? get updatedAt {
    final ms = _db.get('updatedAt');
    return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  Future<void> setEnabled(bool value) async {
    await _db.put('enabled', value);
    if (value && hostCount == 0) unawaited(refresh());
  }

  Future<void> setPromosEnabled(bool value) => _db.put('promos', value);

  Set<String> get _set => _hosts ??= {
    for (final host in (_db.get('hosts') as List? ?? const []))
      if (host is String) host,
  };

  /// Downloads and replaces the list. Returns the number of hosts stored.
  Future<int> refresh([Dio? dio]) async {
    final client = dio ?? Dio();
    final res = await client.get<String>(
      listUrl,
      options: Options(
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    final hosts = parseHosts(res.data ?? '');
    await _db.put('hosts', hosts.toList());
    await _db.put('updatedAt', DateTime.now().millisecondsSinceEpoch);
    _hosts = hosts;
    return hosts.length;
  }

  bool blocks(Uri uri) {
    if (!enabled) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host.isNotEmpty && _set.contains(host);
  }

  /// Parses a hosts file (or an ad-block list in the same shape) into the set
  /// of blocked hostnames. Comments, blank lines, the loopback prefix and
  /// single-label names (`localhost`, `broadcasthost`) are ignored.
  static Set<String> parseHosts(String text) {
    final out = <String>{};
    for (final raw in const LineSplitter().convert(text)) {
      var line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final comment = line.indexOf('#');
      if (comment >= 0) line = line.substring(0, comment).trim();
      if (line.isEmpty) continue;
      final parts = line.split(RegExp(r'\s+'));
      final String host;
      if (parts.length >= 2 &&
          (parts[0] == '0.0.0.0' ||
              parts[0] == '127.0.0.1' ||
              parts[0] == '::1' ||
              parts[0] == '255.255.255.255')) {
        host = parts[1];
      } else if (parts.length == 1) {
        host = parts[0];
      } else {
        continue;
      }
      final clean = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
      if (clean.isEmpty ||
          !clean.contains('.') ||
          RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(clean) ||
          clean == 'localhost' ||
          clean == 'localhost.localdomain' ||
          clean == 'broadcasthost' ||
          clean.startsWith('ip6-')) {
        continue;
      }
      out.add(clean);
    }
    return out;
  }
}
