import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../hive/safe_box.dart';

/// Music quality options, ported from Hikari's `music/VxQuality.kt`.
///
/// Same tier ids as VxMusic so behaviour matches:
///  27 = 24-bit/192 kHz FLAC, 7 = 24/96 FLAC, 6 = 16/44.1 FLAC,
///  5 = 320k MP3, -1 = YouTube (Opus/AAC).
class VxQuality {
  const VxQuality._();

  static const int maxHiRes = 27;
  static const int hiRes96 = 7;
  static const int cdLossless = 6;
  static const int mp3_320 = 5;
  static const int youtube = -1;

  static const String boxName = 'music_quality';
  static const String _preferKey = 'preferLossless';
  static const String _streamKey = 'losslessQuality';
  static const String _downloadKey = 'downloadQuality';
  static const String _bitPerfectKey = 'bitPerfect';
  static const String _clarityKey = 'studioClarity';

  static const List<int> streamOptions = [
    maxHiRes,
    hiRes96,
    cdLossless,
    mp3_320,
    youtube,
  ];
  static const List<int> downloadOptions = streamOptions;

  /// Bumped when a quality preference changes, so the picker and the player
  /// read the new value without a restart.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool _prefer = true;
  static int _stream = maxHiRes;
  static int _download = maxHiRes;
  static bool _bitPerfect = false;
  static bool _clarity = true;

  static bool get preferLossless => _prefer;
  static int get streamQuality => _stream;
  static int get downloadQuality => _download;
  static bool get bitPerfect => _bitPerfect;
  static bool get studioClarity => _clarity;

  static String labelFor(int q) => switch (q) {
    maxHiRes => 'FLAC 24-bit/192kHz',
    hiRes96 => 'FLAC 24-bit/96kHz',
    cdLossless => 'FLAC 16-bit/44.1kHz',
    mp3_320 => 'MP3 320kbps',
    _ => 'YouTube (Opus/AAC)',
  };

  static String shortLabelFor(int q) => switch (q) {
    maxHiRes => '24/192',
    hiRes96 => '24/96',
    cdLossless => '16/44.1',
    mp3_320 => '320k',
    _ => 'YT',
  };

  static Future<void> load() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    final box = Hive.box<dynamic>(boxName);
    _prefer = box.get(_preferKey, defaultValue: true) as bool? ?? true;
    _stream = _valid(box.get(_streamKey), streamOptions);
    _download = _valid(box.get(_downloadKey), downloadOptions);
    _bitPerfect = box.get(_bitPerfectKey, defaultValue: false) as bool? ?? false;
    _clarity = box.get(_clarityKey, defaultValue: true) as bool? ?? true;
  }

  static int _valid(dynamic raw, List<int> options) {
    final value = raw is num ? raw.toInt() : maxHiRes;
    return options.contains(value) ? value : maxHiRes;
  }

  static Future<void> _write(String key, Object value) async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely<dynamic>(boxName);
    await Hive.box<dynamic>(boxName).put(key, value);
    revision.value++;
  }

  static Future<void> setPreferLossless(bool value) async {
    _prefer = value;
    await _write(_preferKey, value);
  }

  static Future<void> setStreamQuality(int quality) async {
    _stream = streamOptions.contains(quality) ? quality : maxHiRes;
    await _write(_streamKey, _stream);
  }

  static Future<void> setDownloadQuality(int quality) async {
    _download = downloadOptions.contains(quality) ? quality : maxHiRes;
    await _write(_downloadKey, _download);
  }

  static Future<void> setBitPerfect(bool value) async {
    _bitPerfect = value;
    await _write(_bitPerfectKey, value);
  }

  static Future<void> setStudioClarity(bool value) async {
    _clarity = value;
    await _write(_clarityKey, value);
  }

  /// Same fallback order as VxMusic: preferred, then above it, then below it,
  /// then YouTube.
  static List<int> attemptOrder(int preferred) {
    if (preferred == youtube) return const [];
    const tiers = [mp3_320, cdLossless, hiRes96, maxHiRes];
    final i = tiers.indexOf(preferred);
    if (i == -1) return const [maxHiRes, hiRes96, cdLossless, mp3_320];
    final above = tiers.sublist(i + 1);
    final below = tiers.sublist(0, i).reversed;
    return <int>{tiers[i], ...above, ...below}.toList();
  }
}
