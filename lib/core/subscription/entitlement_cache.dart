import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../hive/safe_box.dart';
import 'subscription_models.dart';

/// The last server entitlement verdict, kept on the device so a network blip
/// does not turn into either a lockout or a free pass.
///
/// The cache is only a fallback for [deviceEntitled]. A fresh server answer
/// always wins and overwrites it. When the server cannot be reached, the cached
/// verdict is honoured only while its paid period is still running, so an
/// expired plan cannot be extended by going offline.
class CachedEntitlement {
  const CachedEntitlement({required this.identity, required this.checkedAt});

  final DeviceIdentity identity;
  final DateTime checkedAt;
}

class EntitlementCache {
  EntitlementCache._();

  static const String _boxName = 'entitlement_cache';
  static const String _key = 'last';
  static const String _checkedAtKey = 'checked_at';

  /// In-process copy for tests and for platforms where Hive is unavailable.
  /// [save] writes here first, so a test never depends on a plugin channel.
  static CachedEntitlement? _memory;

  @visibleForTesting
  static void debugSet(CachedEntitlement? value) => _memory = value;

  @visibleForTesting
  static CachedEntitlement? get debugValue => _memory;

  static Future<void> save(DeviceIdentity identity, {DateTime? now}) async {
    final checkedAt = (now ?? DateTime.now()).toUtc();
    _memory = CachedEntitlement(identity: identity, checkedAt: checkedAt);

    final box = await _open();
    if (box == null) return;
    await box.put(_key, {
      ...identity.toMap(),
      _checkedAtKey: checkedAt.millisecondsSinceEpoch,
    });
  }

  static Future<CachedEntitlement?> read() async {
    if (_memory != null) return _memory;

    final box = await _open();
    if (box == null) return null;
    final raw = box.get(_key);
    if (raw is! Map) return null;

    final map = raw.cast<String, dynamic>();
    final identity = DeviceIdentity.fromMap(map);
    final checkedAtMs = (map[_checkedAtKey] as num?)?.toInt();
    if (identity == null || checkedAtMs == null) return null;

    return _memory = CachedEntitlement(
      identity: identity,
      checkedAt: DateTime.fromMillisecondsSinceEpoch(checkedAtMs, isUtc: true),
    );
  }

  static Future<void> clear() async {
    _memory = null;
    final box = await _open();
    await box?.delete(_key);
  }

  static Future<Box<dynamic>?> _open() async {
    // `initHiveForApp` records the box directory. Without it (unit tests,
    // unsupported platforms) opening a box throws after the test has finished,
    // so keep the in-memory copy only.
    if (!hiveReady) return null;
    try {
      return await openBoxSafely<dynamic>(_boxName);
    } catch (_) {
      return null;
    }
  }
}
