import 'dart:math';

import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// What a daily-pick slot is about, and therefore how its card is built.
///
/// The three-a-day digest mirrors the three cards Netflix sends: something
/// everyone is watching, something picked for you, and something just added.
/// Each kind draws from a different part of what the app already knows, so the
/// three cards a user gets in a day are genuinely different suggestions rather
/// than the same list relabelled.
enum DailyPickKind {
  /// What the catalogue's trending rows are pushing right now.
  trending,

  /// Drawn from the user's own subscriptions — a show they already follow.
  recommended,

  /// The newest arrivals in the catalogue.
  newRelease,
}

/// One of the three daily-pick slots and the card design that fills it.
///
/// Each slot has a *window* rather than a fixed clock time: the service picks a
/// random minute inside the window once per day (see [DailyPicksPrefs]), so the
/// three land at different times each day instead of on a metronome. The windows
/// are disjoint and ordered, so the three never collide and never arrive out of
/// order even with the jitter.
enum DailyPickSlot {
  morning(
    hour: 8,
    minute: 30,
    jitterMinutes: 60,
    style: DailyPickStyle.bigPicture,
    kind: DailyPickKind.trending,
    titleKey: 'dailyPicksMorning',
  ),
  afternoon(
    hour: 14,
    minute: 0,
    jitterMinutes: 90,
    style: DailyPickStyle.bigText,
    kind: DailyPickKind.recommended,
    titleKey: 'dailyPicksAfternoon',
  ),
  evening(
    hour: 20,
    minute: 0,
    jitterMinutes: 90,
    style: DailyPickStyle.inbox,
    kind: DailyPickKind.newRelease,
    titleKey: 'dailyPicksEvening',
  );

  const DailyPickSlot({
    required this.hour,
    required this.minute,
    required this.jitterMinutes,
    required this.style,
    required this.kind,
    required this.titleKey,
  });

  /// Base time (the middle of the slot's window) in local time.
  final int hour;
  final int minute;

  /// How far either side of the base time the per-day random offset may fall.
  /// Chosen so the three windows stay disjoint: morning ±60m ends at 09:30,
  /// afternoon ±90m starts at 12:30, afternoon ends at 15:30 and evening starts
  /// at 18:30.
  final int jitterMinutes;

  final DailyPickStyle style;

  /// What this slot is about. Decides the copy and which catalogue rows feed it.
  final DailyPickKind kind;

  /// l10n key for the slot's label, e.g. the Settings row and the notification
  /// sub-title. Kept as a key so this file stays free of a BuildContext.
  final String titleKey;

  /// Base time as minutes past midnight.
  int get baseMinuteOfDay => hour * 60 + minute;
}

/// The three notification-card designs the daily picks rotate through. These
/// map to Android's standard expanded layouts, so each is a recognised system
/// pattern rather than a custom view:
///
///   • [bigPicture] — `BigPictureStyleInformation`; the item's poster as a
///                    large image (Netflix's "New & Hot" artwork card).
///   • [bigText]    — `BigTextStyleInformation`; the compact title + a long
///                    single-item body (the "picked for you" card).
///   • [inbox]      — `InboxStyleInformation`; up to five lines (the "what's
///                    new" digest card).
enum DailyPickStyle { bigPicture, bigText, inbox }

/// Persisted switch + per-slot dedupe state for the daily picks. A plain Hive
/// box, like [IncognitoMode] and [PlaybackPrefs], so a synchronous read is
/// available on the scheduler's hot path.
abstract final class DailyPicksPrefs {
  static const String boxName = 'daily_picks_prefs';
  static const String _enabledKey = 'enabled';

  /// Whether the user turned the daily picks on. Defaults off — the app never
  /// schedules notifications a user did not ask for.
  static bool get enabled {
    if (!Hive.isBoxOpen(boxName)) return false;
    return Hive.box(boxName).get(_enabledKey, defaultValue: false) as bool;
  }

  static Future<void> init() async {
    if (!Hive.isBoxOpen(boxName)) await openBoxSafely(boxName);
  }

  static Future<void> setEnabled(bool value) async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely(boxName);
    await box.put(_enabledKey, value);
  }

  /// The `yyyy-MM-dd` of the last day [slot] was filled, so a re-run on the
  /// same day does not post a second card. Stored per slot.
  static String? lastFilledDay(DailyPickSlot slot) {
    if (!Hive.isBoxOpen(boxName)) return null;
    return Hive.box(boxName).get('filled_${slot.name}') as String?;
  }

  static Future<void> markFilled(DailyPickSlot slot, String day) async {
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely(boxName);
    await box.put('filled_${slot.name}', day);
  }

  /// Whether [slot] still needs a card for [day]. A slot that already fired
  /// today — because the app happened to be open, or because the user hit
  /// "send now" — is skipped, so the three-a-day promise holds even though the
  /// trigger is opportunistic rather than a precise alarm.
  static bool needsFill(DailyPickSlot slot, String day) =>
      lastFilledDay(slot) != day;

  /// The random minute offset chosen for [slot] on [day], or null if none has
  /// been drawn yet.
  static int? jitter(DailyPickSlot slot, String day) {
    if (!Hive.isBoxOpen(boxName)) return null;
    final stored = Hive.box(boxName).get('jitter_${slot.name}');
    if (stored is! Map) return null;
    if (stored['day'] != day) return null;
    final value = stored['minutes'];
    return value is int ? value : null;
  }

  /// The minute-of-day [slot] should fire on [day]: its base time plus a random
  /// offset inside the slot's window. The offset is drawn once and remembered,
  /// so the alarm and the catch-up check agree on the time and re-running the
  /// scheduler on the same day does not keep moving the target.
  static Future<int> resolveMinuteOfDay(DailyPickSlot slot, String day) async {
    final existing = jitter(slot, day);
    if (existing != null) return slot.baseMinuteOfDay + existing;
    final span = slot.jitterMinutes;
    final offset = span == 0 ? 0 : _random.nextInt(span * 2 + 1) - span;
    final box = Hive.isBoxOpen(boxName)
        ? Hive.box(boxName)
        : await openBoxSafely(boxName);
    await box.put('jitter_${slot.name}', {'day': day, 'minutes': offset});
    return slot.baseMinuteOfDay + offset;
  }

  static final _random = Random();
}
