import 'package:hive/hive.dart';

import '../hive/safe_box.dart';

/// One of the three daily-pick slots and the card design that fills it.
///
/// The three slots are the industry-standard local-notification cadences a
/// "digest" app uses: a morning heads-up, an afternoon nudge and an evening
/// round-up. Each slot keeps a different [style] so a user who gets all three
/// sees three distinct notification-card designs across the day rather than
/// the same template three times — the three Android layouts are big-text
/// (title + body), big-picture (poster art) and inbox (a list of lines).
enum DailyPickSlot {
  morning(
    hour: 8,
    minute: 30,
    style: DailyPickStyle.bigText,
    titleKey: 'dailyPicksMorning',
  ),
  afternoon(
    hour: 14,
    minute: 0,
    style: DailyPickStyle.bigPicture,
    titleKey: 'dailyPicksAfternoon',
  ),
  evening(
    hour: 20,
    minute: 0,
    style: DailyPickStyle.inbox,
    titleKey: 'dailyPicksEvening',
  );

  const DailyPickSlot({
    required this.hour,
    required this.minute,
    required this.style,
    required this.titleKey,
  });

  final int hour;
  final int minute;
  final DailyPickStyle style;

  /// l10n key for the slot's label, e.g. the Settings row and the notification
  /// sub-title. Kept as a key so this file stays free of a BuildContext.
  final String titleKey;
}

/// The three notification-card designs the daily picks rotate through. These
/// map to Android's standard expanded layouts, so each is a recognised system
/// pattern rather than a custom view:
///
///   • [bigText]    — `BigTextStyleInformation`; the compact title + a long
///                    single item body (the classic "story" card).
///   • [bigPicture] — `BigPictureStyleInformation`; the item's poster as a
///                    large image (the "media" card).
///   • [inbox]      — `InboxStyleInformation`; up to five lines (the "digest"
///                    card).
enum DailyPickStyle { bigText, bigPicture, inbox }

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
}
