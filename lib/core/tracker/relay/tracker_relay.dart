import '../tracker.dart';
import 'tracker_blob.dart';

/// Packs the phone's connected tracker sessions into a [TrackerBlob] and applies
/// a received blob into local storage. Backend-agnostic and crypto-agnostic —
/// callers encrypt the blob's `encode()` before it leaves the device.
class TrackerRelay {
  TrackerRelay(this._trackers);

  /// Keyed by relay id ('anilist' | 'mal' | 'simkl' | 'trakt' | 'mangabaka').
  final Map<String, Tracker> _trackers;

  TrackerBlob pack({Set<String>? only}) {
    final out = <String, Map<String, dynamic>>{};
    _trackers.forEach((id, tracker) {
      if (only != null && !only.contains(id)) return;
      final session = tracker.exportSession();
      if (session != null) out[id] = session;
    });
    return TrackerBlob(version: TrackerBlob.currentVersion, trackers: out);
  }

  /// Writes every present, known tracker; returns the ids applied.
  Future<List<String>> unpack(TrackerBlob blob) async {
    final applied = <String>[];
    for (final entry in blob.trackers.entries) {
      final tracker = _trackers[entry.key];
      if (tracker == null) continue; // unknown / version drift → skip
      await tracker.importSession(entry.value);
      applied.add(entry.key);
    }
    return applied;
  }
}
