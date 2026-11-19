import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../hive/safe_box.dart';
import 'xmltv_parser.dart';

/// What a scheduled entry does when its programme starts.
enum DvrKind {
  /// Pop a notification; nothing is written to disk.
  reminder,

  /// Capture the stream to a file.
  recording,
}

/// A reminder or recording pinned to one airing of one channel.
///
/// Keyed by channel + start rather than by programme title: a show airing
/// nightly is several separate bookings, and re-keying by title would collapse
/// them into one. [id] is that composite, so booking the same airing twice is a
/// no-op instead of a duplicate.
class DvrEntry {
  const DvrEntry({
    required this.channelId,
    required this.channelName,
    required this.title,
    required this.start,
    required this.stop,
    required this.kind,
    this.streamUrl = '',
    this.paddingMinutes = 0,
    this.createdAt,
  });

  final String channelId;
  final String channelName;
  final String title;

  /// UTC airing window, from the EPG.
  final DateTime start;
  final DateTime stop;
  final DvrKind kind;

  /// Resolved playable URL, when the caller had one. A reminder can be booked
  /// from the guide alone; a recording needs the stream, so an entry with no
  /// URL records nothing and says so.
  final String streamUrl;

  /// Minutes of lead-in added before [start] and after [stop]. Live events
  /// overrun, and a recording that cuts the last minute off is worse than one
  /// that carries a minute of padding.
  final int paddingMinutes;

  final DateTime? createdAt;

  /// `channelId@<start epoch ms>` — stable, so a re-booking is idempotent.
  String get id => '$channelId@${start.millisecondsSinceEpoch}';

  DateTime get captureStart =>
      start.subtract(Duration(minutes: paddingMinutes));
  DateTime get captureStop => stop.add(Duration(minutes: paddingMinutes));

  Duration get duration => stop.difference(start);

  bool get hasStream => streamUrl.trim().isNotEmpty;

  /// True once the airing (plus padding) is over — the entry is then history.
  bool get isPast => captureStop.isBefore(DateTime.now().toUtc());

  /// True while the airing should be running.
  bool isLiveAt(DateTime when) {
    final w = when.toUtc();
    return !w.isBefore(captureStart) && w.isBefore(captureStop);
  }

  DvrEntry copyWith({String? streamUrl, int? paddingMinutes}) => DvrEntry(
    channelId: channelId,
    channelName: channelName,
    title: title,
    start: start,
    stop: stop,
    kind: kind,
    streamUrl: streamUrl ?? this.streamUrl,
    paddingMinutes: paddingMinutes ?? this.paddingMinutes,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'channelId': channelId,
    'channelName': channelName,
    'title': title,
    'start': start.toIso8601String(),
    'stop': stop.toIso8601String(),
    'kind': kind.name,
    if (streamUrl.isNotEmpty) 'streamUrl': streamUrl,
    if (paddingMinutes != 0) 'paddingMinutes': paddingMinutes,
    if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
  };

  factory DvrEntry.fromJson(Map<String, dynamic> j) => DvrEntry(
    channelId: (j['channelId'] as String?) ?? '',
    channelName: (j['channelName'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
    start: DateTime.parse(j['start'] as String).toUtc(),
    stop: DateTime.parse(j['stop'] as String).toUtc(),
    kind: DvrKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => DvrKind.reminder,
    ),
    streamUrl: (j['streamUrl'] as String?) ?? '',
    paddingMinutes: (j['paddingMinutes'] as num?)?.toInt() ?? 0,
    createdAt: j['createdAt'] == null
        ? null
        : DateTime.tryParse('${j['createdAt']}')?.toUtc(),
  );

  /// Build from an EPG programme — the normal path, since the guide is where a
  /// viewer decides to record something.
  factory DvrEntry.fromProgramme(
    EpgProgramme programme, {
    required String channelName,
    required DvrKind kind,
    String streamUrl = '',
    int paddingMinutes = 0,
  }) => DvrEntry(
    channelId: programme.channelId,
    channelName: channelName,
    title: programme.title,
    start: programme.start,
    stop: programme.stop,
    kind: kind,
    streamUrl: streamUrl,
    paddingMinutes: paddingMinutes,
    createdAt: DateTime.now().toUtc(),
  );
}

/// The recording/reminder schedule: one Hive box, read synchronously, mutated
/// through idempotent bookings.
///
/// This is the data half of DVR. Capture itself is driven by the platform —
/// [dueForCapture] tells a capture loop what to start and stop, so the
/// scheduling logic stays pure Dart and testable without a mobile host.
class DvrStore extends ChangeNotifier {
  DvrStore();

  static const String boxName = 'dvr_entries';

  final List<DvrEntry> _entries = [];
  var _loaded = false;

  List<DvrEntry> get entries => List.unmodifiable(_entries);

  List<DvrEntry> get reminders => _entries
      .where((e) => e.kind == DvrKind.reminder)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  List<DvrEntry> get recordings => _entries
      .where((e) => e.kind == DvrKind.recording)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  /// Everything still ahead of us, soonest first — what a "Coming up" list
  /// shows.
  List<DvrEntry> get upcoming => _entries.where((e) => !e.isPast).toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  bool get isEmpty => _entries.isEmpty;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final box = await _box();
    final raw = box.get('entries');
    if (raw is List) {
      for (final entry in raw) {
        if (entry is! Map) continue;
        try {
          _entries.add(DvrEntry.fromJson(Map<String, dynamic>.from(entry)));
        } catch (e) {
          debugPrint('[dvr] dropping unreadable entry: $e');
        }
      }
    }
    _entries.sort((a, b) => a.start.compareTo(b.start));
    notifyListeners();
  }

  /// Book [entry]. Idempotent on [DvrEntry.id] — re-booking the same airing
  /// updates it in place (a later pass may have resolved its stream URL).
  Future<DvrEntry> book(DvrEntry entry) async {
    await ensureLoaded();
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.add(entry);
    _entries.sort((a, b) => a.start.compareTo(b.start));
    await _persist();
    notifyListeners();
    return entry;
  }

  /// Attach a resolved stream URL to an already-booked recording, so a booking
  /// made from the guide (which has no URL) becomes recordable.
  Future<void> attachStream(String id, String streamUrl) async {
    await ensureLoaded();
    final i = _entries.indexWhere((e) => e.id == id);
    if (i < 0) return;
    _entries[i] = _entries[i].copyWith(streamUrl: streamUrl);
    await _persist();
    notifyListeners();
  }

  Future<void> cancel(String id) async {
    await ensureLoaded();
    final before = _entries.length;
    _entries.removeWhere((e) => e.id == id);
    if (_entries.length == before) return;
    await _persist();
    notifyListeners();
  }

  DvrEntry? byId(String id) {
    for (final e in _entries) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// True when this airing is already booked (either kind).
  bool isBooked(String channelId, DateTime start) => _entries.any(
    (e) => e.channelId == channelId && e.start == start.toUtc(),
  );

  /// The recordings whose capture window contains [at] and that have a stream.
  /// A capture loop calls this on a timer; an entry with no URL is excluded
  /// because there is nothing to open.
  List<DvrEntry> dueForCapture({DateTime? at}) {
    final when = (at ?? DateTime.now()).toUtc();
    return [
      for (final e in _entries)
        if (e.kind == DvrKind.recording && e.hasStream && e.isLiveAt(when)) e,
    ];
  }

  /// Recordings that should have started but never did, and whose window is
  /// still open — the retry set for a capture loop that was asleep.
  List<DvrEntry> missedCaptures({DateTime? at}) {
    final when = (at ?? DateTime.now()).toUtc();
    return [
      for (final e in _entries)
        if (e.kind == DvrKind.recording &&
            e.hasStream &&
            e.captureStart.isBefore(when) &&
            e.captureStop.isAfter(when))
          e,
    ];
  }

  /// Drop entries that finished more than [keepDays] ago, so the box doesn't
  /// grow forever. Returns how many were removed.
  Future<int> prune({int keepDays = 30, DateTime? at}) async {
    await ensureLoaded();
    final cutoff = (at ?? DateTime.now())
        .toUtc()
        .subtract(Duration(days: keepDays));
    final before = _entries.length;
    _entries.removeWhere((e) => e.captureStop.isBefore(cutoff));
    final removed = before - _entries.length;
    if (removed > 0) {
      await _persist();
      notifyListeners();
    }
    return removed;
  }

  Future<void> clear() async {
    await ensureLoaded();
    _entries.clear();
    await _persist();
    notifyListeners();
  }

  Future<Box> _box() async => Hive.isBoxOpen(boxName)
      ? Hive.box(boxName)
      : await openBoxSafely<dynamic>(boxName);

  Future<void> _persist() async {
    final box = await _box();
    await box.put('entries', [for (final e in _entries) e.toJson()]);
  }
}

/// A reminder notification the platform layer should post.
///
/// Kept as a value object so the store can decide *what* is due without
/// knowing how notifications are drawn — the same split [DvrStore] uses for
/// capture.
class DvrReminder {
  const DvrReminder({required this.entry, required this.fireAt});

  final DvrEntry entry;
  final DateTime fireAt;

  /// Stable notification id derived from the booking, so re-scheduling the
  /// same airing replaces rather than stacks.
  int get notificationId => entry.id.hashCode & 0x7fffffff;

  String get title => entry.channelName.isEmpty
      ? 'Starting now'
      : '${entry.channelName} · starting now';
  String get body => entry.title;
}

/// Reminders that should fire within the next [within] window and haven't yet
/// started. The platform layer posts these and marks them by scheduling id.
List<DvrReminder> dueReminders(
  List<DvrEntry> entries, {
  DateTime? at,
  Duration within = const Duration(minutes: 2),
}) {
  final when = (at ?? DateTime.now()).toUtc();
  return [
    for (final e in entries)
      if (e.kind == DvrKind.reminder &&
          !when.isBefore(e.start.subtract(within)) &&
          when.isBefore(e.start))
        DvrReminder(entry: e, fireAt: e.start),
  ];
}

/// Serialises a schedule for the settings backup: entries as JSON, so a
/// restored device keeps its bookings.
String encodeDvr(List<DvrEntry> entries) =>
    jsonEncode([for (final e in entries) e.toJson()]);

List<DvrEntry> decodeDvr(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final out = <DvrEntry>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      try {
        out.add(DvrEntry.fromJson(Map<String, dynamic>.from(entry)));
      } catch (_) {
        // One bad row must not sink the whole restored schedule.
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  } catch (_) {
    return const [];
  }
}
