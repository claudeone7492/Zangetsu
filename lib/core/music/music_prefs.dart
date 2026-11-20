import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// The stream quality to ask the catalogue for.
///
/// Saavn advertises several encodings per song (12 → 320 kbps). Picking the
/// highest is the best-sounding default, but on a metered connection it is
/// ~26× the data of the lowest, so it has to be the user's call rather than a
/// constant inside the source.
enum MusicQuality {
  dataSaver(96, '96 kbps'),
  balanced(160, '160 kbps'),
  high(320, '320 kbps');

  const MusicQuality(this.kbps, this.label);

  /// The bitrate ceiling this choice allows. A track with no encoding at or
  /// below it still plays — the lowest advertised one is used instead, because
  /// silence is worse than a bigger file.
  final int kbps;

  /// Stable for storage and for the settings row. Not translated: it is a
  /// technical figure, and every locale prints it the same way.
  final String label;
}

/// Which quality music playback should use. Defaults to [MusicQuality.high],
/// matching what the app did when the choice was hardcoded.
class MusicPrefs {
  const MusicPrefs._();

  static const String boxName = 'music_prefs';
  static const String _qualityKey = 'quality';

  /// Bumped on every write so an open player re-resolves at the new quality
  /// instead of finishing the song at the old one.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
  }

  static Box? get _boxOrNull =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : null;

  /// The stored choice, or [MusicQuality.high] when unset or unrecognised —
  /// a value written by a future build must not break playback here.
  static MusicQuality get quality {
    final stored = _boxOrNull?.get(_qualityKey);
    if (stored is! String) return MusicQuality.high;
    for (final q in MusicQuality.values) {
      if (q.name == stored) return q;
    }
    return MusicQuality.high;
  }

  static Future<void> setQuality(MusicQuality q) async {
    final box = _boxOrNull;
    if (box == null) return;
    await box.put(_qualityKey, q.name);
    revision.value++;
  }
}
