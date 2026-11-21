import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'telegram_source.dart';

/// Channels the viewer has added.
///
/// Kept in its own box for the same reason as `DubPrefs`: Telegram is a
/// self-contained surface, and the backup drift guard gets one clear decision
/// instead of a scattering of keys in a box nobody associates with it.
class TelegramPrefs extends ChangeNotifier {
  TelegramPrefs._(this._box);

  @visibleForTesting
  TelegramPrefs.forTesting(Box box) : this._(box);

  final Box _box;

  static const String boxName = 'telegram_prefs';

  static Future<TelegramPrefs> open() async {
    final box = await openBoxSafely<dynamic>(boxName);
    return TelegramPrefs._(box);
  }

  /// Saved channels, newest first, as `@name`.
  List<String> get channels {
    final raw = _box.get('channels');
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is String && entry.trim().isNotEmpty) entry.trim(),
    ];
  }

  /// The defaults first, then anything the viewer added.
  List<String> get allChannels => [
    ...kDefaultTelegramChannels,
    ...channels.where((c) => !kDefaultTelegramChannels.contains(c)),
  ];

  /// The `api_id` and `api_hash` from my.telegram.org, as typed. Empty when
  /// the viewer has not signed in; the native side keeps its own copy so a
  /// restart can resume the session before Dart is up.
  String get apiId => _box.get('apiId', defaultValue: '') as String;

  String get apiHash => _box.get('apiHash', defaultValue: '') as String;

  Future<void> saveCredentials(String apiId, String apiHash) async {
    await _box.put('apiId', apiId.trim());
    await _box.put('apiHash', apiHash.trim());
    notifyListeners();
  }

  /// Adds [raw] if it parses. Returns the normalised `@name`, or null.
  Future<String?> addChannel(String raw) async {
    final target = TelegramTarget.parse(raw);
    if (target == null) return null;
    final key = target.key;
    final next = [
      key,
      ...channels.where((channel) => channel != key),
    ];
    await _box.put('channels', next);
    notifyListeners();
    return key;
  }

  Future<void> removeChannel(String key) async {
    final next = channels.where((channel) => channel != key).toList();
    await _box.put('channels', next);
    notifyListeners();
  }
}
