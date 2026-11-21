import 'package:hive/hive.dart';

/// Favourite channels, keyed by channel id.
///
/// Hikari keeps `IptvMark` separately from the playlist so a refresh never
/// loses a star. This is that store: a plain set persisted in its own box.
class IptvMarkStore {
  const IptvMarkStore._();

  static const boxName = 'iptv_marks';
  static Box<dynamic>? _box;
  static final Set<String> _memory = {};

  static Future<void> init() async {
    _box = await Hive.openBox<dynamic>(boxName);
    _memory
      ..clear()
      ..addAll(_box!.keys.whereType<String>());
  }

  static bool isMarked(String channelId) => _memory.contains(channelId);

  static Set<String> get all => Set.unmodifiable(_memory);

  static Future<void> toggle(String channelId) async {
    if (!_memory.remove(channelId)) _memory.add(channelId);
    final box = _box;
    if (box == null) return;
    if (_memory.contains(channelId)) {
      await box.put(channelId, true);
    } else {
      await box.delete(channelId);
    }
  }

  static void reset() => _memory.clear();
}
