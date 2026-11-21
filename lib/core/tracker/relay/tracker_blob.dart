import 'dart:convert';

/// A relayed bundle of tracker sessions. `trackers` is keyed by the stable ids
/// 'anilist' | 'mal' | 'simkl' | 'trakt' | 'mangabaka'; each value is that
/// service's persisted session
/// map verbatim. Only connected trackers appear.
class TrackerBlob {
  const TrackerBlob({required this.version, required this.trackers});

  static const int currentVersion = 1;

  final int version;
  final Map<String, Map<String, dynamic>> trackers;

  Map<String, dynamic> toJson() => {'v': version, 'trackers': trackers};

  String encode() => jsonEncode(toJson());

  factory TrackerBlob.fromJson(Map<String, dynamic> j) => TrackerBlob(
        version: (j['v'] as num?)?.toInt() ?? 0,
        trackers: ((j['trackers'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
        ),
      );

  factory TrackerBlob.decode(String s) =>
      TrackerBlob.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
