import 'dart:async';
import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../di/injector.dart';
import '../mode/content_mode.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../zmode/metadata_repository.dart';
import 'daily_picks_prefs.dart';
import 'notification_service.dart';
import 'subscription_store.dart';

/// The three-a-day "daily picks" digest.
///
/// Three notifications a day, each with a different card design, drawn from the
/// same two things the app already knows: subscribed shows and the metadata
/// catalogue's trending rows. The three slots are staggered across the day
/// (morning / afternoon / evening) and each uses a different Android expanded
/// layout ([DailyPickStyle]), so the user sees big-text, big-picture and inbox
/// cards — the three industry-standard designs — rather than one repeated.
///
/// Delivery is intentionally opportunistic. A precise daily alarm needs the
/// exact-alarm permission and, on many OEM ROMs, a background service the
/// system may still kill. Instead the scheduler is poked at app start, on
/// resume, and after a check, and it posts whichever slot is *due* and not yet
/// filled today. Missed slots are caught up on the next open. The result is
/// the same three-a-day cadence for a user who opens the app most days, with
/// no permission prompt and no battery cost.
class DailyPicksService {
  DailyPicksService._();
  static final DailyPicksService instance = DailyPicksService._();

  /// Stable ids per slot so re-firing a slot replaces its card rather than
  /// stacking a fourth.
  static const Map<DailyPickSlot, int> _slotIds = {
    DailyPickSlot.morning: 91001,
    DailyPickSlot.afternoon: 91002,
    DailyPickSlot.evening: 91003,
  };

  bool _tzReady = false;

  /// Local timezone database. The scheduled fallback and the "is this slot due"
  /// comparison both need a real zone, so this is set once from the platform.
  Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // A platform that cannot name its zone falls back to the database's
      // default (UTC). The due-slot check still works; only the wall-clock
      // alignment of the scheduled fallback is off, and that fallback is
      // itself a best-effort backstop.
    }
    _tzReady = true;
  }

  /// Ensure the three slots exist as scheduled alarms for today/tomorrow, then
  /// immediately fill whichever slots are already due and unfilled. Safe to
  /// call repeatedly (start, resume, after a check) — the day-stamp in
  /// [DailyPicksPrefs] makes it idempotent within a day.
  Future<void> sync({bool force = false}) async {
    if (!Platform.isAndroid) return;
    if (!DailyPicksPrefs.enabled && !force) return;
    try {
      await NotificationService.instance.init();
      await _ensureTimezone();
      await _scheduleAlarms();
      await _fillDueSlots(force: force);
    } catch (_) {
      // Never let the digest affect startup or playback.
    }
  }

  /// Ask the platform to fire each slot at its wall-clock time. These are the
  /// alarms that make the cadence exact on a device that is awake; [_fillDueSlots]
  /// is the catch-up for the times the device was not.
  Future<void> _scheduleAlarms() async {
    // Content is resolved now and baked into the alarm. That means the card a
    // user sees at 08:30 is fixed at the last app open rather than built at
    // fire time (a background isolate cannot reach the catalogue), but it is a
    // real card with a real show, not an empty title-less notification.
    final picks = await _picks();
    if (picks.isEmpty) return;
    for (final slot in DailyPickSlot.values) {
      final lead = picks.first;
      try {
        await NotificationService.instance.scheduleDailyPick(
          id: _slotIds[slot]!,
          title: lead.title,
          body: _bodyFor(slot.style, picks),
          style: slot.style,
          when: _nextInstanceOf(slot),
          imageUrl: lead.banner ?? lead.cover,
          lines: [for (final p in picks) p.title],
          payload: _payload(slot, lead),
        );
      } catch (_) {
        // A denied notification permission or an OEM that refuses alarms must
        // not stop the other slots from being scheduled.
      }
    }
  }

  /// The next occurrence of [slot]'s hour/minute in local time.
  tz.TZDateTime _nextInstanceOf(DailyPickSlot slot) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      slot.hour,
      slot.minute,
    );
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  /// Post a card for every slot whose time has passed today and that has not
  /// already been filled. [force] (the "send now" button) ignores the clock and
  /// fills the next unfilled slot regardless.
  Future<void> _fillDueSlots({bool force = false}) async {
    final now = DateTime.now();
    final today = _dayStamp(now);
    final due = DailyPickSlot.values.where((s) {
      if (!DailyPicksPrefs.needsFill(s, today)) return false;
      if (force) return true;
      return now.hour > s.hour || (now.hour == s.hour && now.minute >= s.minute);
    }).toList();
    if (due.isEmpty) return;
    // Force fills one slot; the normal path may catch up several missed ones.
    final toFill = force ? [due.first] : due;
    for (final slot in toFill) {
      final ok = await _post(slot);
      if (ok) await DailyPicksPrefs.markFilled(slot, today);
    }
  }

  /// Build and show the card for [slot]. Returns false when there is nothing
  /// worth saying, so the slot is left unfilled and retried later.
  Future<bool> _post(DailyPickSlot slot) async {
    final picks = await _picks();
    if (picks.isEmpty) return false;
    final lead = picks.first;
    await NotificationService.instance.showDailyPick(
      id: _slotIds[slot]!,
      title: lead.title,
      body: _bodyFor(slot.style, picks),
      style: slot.style,
      imageUrl: lead.banner ?? lead.cover,
      lines: [for (final p in picks) p.title],
      payload: _payload(slot, lead),
    );
    return true;
  }

  /// The body text for a slot's card. Big-text wants the long story form; the
  /// other two carry the detail in the image / line list, so they get a short
  /// one-liner.
  String _bodyFor(DailyPickStyle style, List<MediaItem> picks) =>
      style == DailyPickStyle.bigText ? _bigTextBody(picks) : _shortBody(picks);

  /// `"daily:<slot>:<sourceId>|<url>"` — the router strips the slot and opens
  /// the lead item's Detail screen. Falls back to a bare `"daily:<slot>"` when
  /// the lead has no openable url, so a tap is a harmless no-op rather than a
  /// crash.
  String _payload(DailyPickSlot slot, MediaItem lead) {
    if (lead.url.isEmpty || lead.sourceId.isEmpty) return 'daily:${slot.name}';
    return 'daily:${slot.name}:${lead.sourceId}|${lead.url}';
  }

  String _bigTextBody(List<MediaItem> picks) {
    final rest = picks.skip(1).map((p) => p.title).toList();
    final lead = picks.first;
    final tagline = lead.genres.isNotEmpty
        ? lead.genres.take(2).join(' · ')
        : (lead.quality ?? '');
    final buffer = StringBuffer();
    if (tagline.isNotEmpty) buffer.write('$tagline — ');
    buffer.write('plus ${rest.length} more to watch');
    return buffer.toString();
  }

  String _shortBody(List<MediaItem> picks) =>
      picks.length > 1 ? 'plus ${picks.length - 1} more to watch' : 'A pick for you';

  /// The items behind today's picks: the user's subscribed shows first (a new
  /// chapter/episode is the most useful nudge), topped up with a trending row
  /// so a user with no subscriptions still gets suggestions.
  Future<List<MediaItem>> _picks() async {
    final out = <MediaItem>[];
    final seen = <String>{};
    void add(MediaItem m) {
      final key = '${m.sourceId}:${m.id}';
      if (seen.add(key)) out.add(m);
    }

    // Subscribed shows, newest first.
    try {
      if (sl.isRegistered<SubscriptionStore>()) {
        for (final s in sl<SubscriptionStore>().all()) {
          add(
            MediaItem(
              id: s.url,
              title: s.title,
              url: s.url,
              // The subscription knows what it is; a manga/novel sub must not
              // open as a video show (mirrors notification_router).
              type: switch (s.mode) {
                ContentMode.manga => ProviderType.manga,
                ContentMode.novel => ProviderType.novel,
                _ => ProviderType.anime,
              },
              sourceId: s.sourceId,
              cover: s.cover,
              coverHeaders: s.coverHeaders,
            ),
          );
        }
      }
    } catch (_) {}

    // Trending top-up from the metadata catalogue.
    if (out.length < 5 && sl.isRegistered<MetadataRepository>()) {
      try {
        final rows = await sl<MetadataRepository>().home();
        for (final row in rows) {
          for (final item in row.items) {
            add(item);
            if (out.length >= 5) break;
          }
          if (out.length >= 5) break;
        }
      } catch (_) {}
    }
    return out;
  }

  static String _dayStamp(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
