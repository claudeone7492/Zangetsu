import 'dart:async';
import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../app_config.dart';
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
/// Three notifications a day, each with a different card design and each about
/// a different *kind* of suggestion — trending, picked for you, and new — the
/// way Netflix's daily cards are one "New & Hot", one "Trending now" and one
/// "Picks for you". The three slots are spread across the day and each lands at
/// a random minute inside its window ([DailyPickSlot.jitterMinutes]), so the
/// cadence is three-a-day without arriving on a metronome.
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
    final today = _dayStamp(DateTime.now());
    for (final slot in DailyPickSlot.values) {
      // Content is resolved now and baked into the alarm. That means the card a
      // user sees at 08:30 is fixed at the last app open rather than built at
      // fire time (a background isolate cannot reach the catalogue), but it is a
      // real card with a real show, not an empty title-less notification.
      final picks = await _picksFor(slot.kind);
      if (picks.isEmpty) continue;
      final lead = picks.first;
      try {
        await NotificationService.instance.scheduleDailyPick(
          id: _slotIds[slot]!,
          title: _titleFor(slot),
          body: _bodyFor(slot, picks),
          style: slot.style,
          when: _nextInstanceOf(slot, await _minuteOfDay(slot, today)),
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

  /// The minute-of-day [slot] fires today. A random offset inside the slot's
  /// window, drawn once per day and remembered, so the three land at different
  /// times each day (and a re-run never moves the target).
  Future<int> _minuteOfDay(DailyPickSlot slot, String day) =>
      DailyPicksPrefs.resolveMinuteOfDay(slot, day);

  /// The next occurrence of [slot]'s chosen time in local time.
  tz.TZDateTime _nextInstanceOf(DailyPickSlot slot, int minuteOfDay) {
    final now = tz.TZDateTime.now(tz.local);
    var when = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
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
    final nowMinute = now.hour * 60 + now.minute;
    final due = <DailyPickSlot>[];
    for (final slot in DailyPickSlot.values) {
      if (!DailyPicksPrefs.needsFill(slot, today)) continue;
      if (!force && nowMinute < await _minuteOfDay(slot, today)) continue;
      due.add(slot);
    }
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
    final picks = await _picksFor(slot.kind);
    if (picks.isEmpty) return false;
    final lead = picks.first;
    await NotificationService.instance.showDailyPick(
      id: _slotIds[slot]!,
      title: _titleFor(slot),
      body: _bodyFor(slot, picks),
      style: slot.style,
      imageUrl: lead.banner ?? lead.cover,
      lines: [for (final p in picks) p.title],
      payload: _payload(slot, lead),
    );
    return true;
  }

  /// The headline for a slot's card. Each slot is a different *kind* of
  /// suggestion, so each gets its own headline the way Netflix labels its
  /// "New arrivals", "Trending now" and "Picks for you" cards.
  String _titleFor(DailyPickSlot slot) => switch (slot.kind) {
    DailyPickKind.trending => 'Trending on $kAppName',
    DailyPickKind.recommended => 'Picked for you',
    DailyPickKind.newRelease => 'New on $kAppName',
  };

  /// The body text for a slot's card. Big-text wants the long story form; the
  /// other two carry the detail in the image / line list, so they get a short
  /// one-liner. The lead title is always in the body, so the show being
  /// suggested reads clearly under the kind headline.
  String _bodyFor(DailyPickSlot slot, List<MediaItem> picks) =>
      slot.style == DailyPickStyle.bigText
      ? _bigTextBody(picks)
      : _shortBody(picks);

  /// `"daily:<slot>:<sourceId>|<url>"` — the router strips the slot and opens
  /// the lead item's Detail screen. Falls back to a bare `"daily:<slot>"` when
  /// the lead has no openable url, so a tap is a harmless no-op rather than a
  /// crash.
  String _payload(DailyPickSlot slot, MediaItem lead) {
    if (lead.url.isEmpty || lead.sourceId.isEmpty) return 'daily:${slot.name}';
    return 'daily:${slot.name}:${lead.sourceId}|${lead.url}';
  }

  String _bigTextBody(List<MediaItem> picks) {
    final lead = picks.first;
    final rest = picks.skip(1).map((p) => p.title).toList();
    final tagline = lead.genres.isNotEmpty
        ? lead.genres.take(2).join(' · ')
        : (lead.quality ?? '');
    final buffer = StringBuffer();
    if (tagline.isNotEmpty) buffer.write('$tagline · ');
    buffer.write(lead.title);
    if (rest.isNotEmpty) buffer.write(' — plus ${rest.length} more');
    return buffer.toString();
  }

  String _shortBody(List<MediaItem> picks) {
    final lead = picks.first;
    if (picks.length > 1) return '${lead.title} + ${picks.length - 1} more';
    return lead.title.isEmpty ? 'A pick for you' : lead.title;
  }

  /// The items behind one kind of pick. Each kind draws from a different source
  /// so the three cards a day are different suggestions:
  ///
  ///   • [DailyPickKind.trending]    — the catalogue's trending home rows.
  ///   • [DailyPickKind.recommended] — the user's own subscriptions.
  ///   • [DailyPickKind.newRelease]  — the catalogue's newest rows.
  ///
  /// Every kind falls back to the trending rows, so a user with no
  /// subscriptions (or a catalogue that only returns one row) still gets three
  /// cards rather than silence.
  Future<List<MediaItem>> _picksFor(DailyPickKind kind) async {
    final trending = await _cataloguePicks();
    final out = <MediaItem>[];
    final seen = <String>{};
    void add(MediaItem m) {
      final key = '${m.sourceId}:${m.id}';
      if (seen.add(key)) out.add(m);
    }

    if (kind == DailyPickKind.recommended) {
      for (final m in _subscriptionPicks()) {
        add(m);
      }
    }
    if (kind == DailyPickKind.newRelease) {
      for (final m in _newestPicks(trending)) {
        add(m);
      }
    }
    for (final m in trending) {
      add(m);
    }
    return out.take(5).toList();
  }

  /// The user's subscribed shows, newest first — a new chapter or episode is the
  /// most useful nudge the app can give.
  List<MediaItem> _subscriptionPicks() {
    final out = <MediaItem>[];
    try {
      if (sl.isRegistered<SubscriptionStore>()) {
        for (final s in sl<SubscriptionStore>().all()) {
          out.add(
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
    return out;
  }

  /// Items from the catalogue's home rows, flattened in row order. Row order is
  /// the provider's own: the first rows are its trending / "now" rows.
  Future<List<MediaItem>> _cataloguePicks() async {
    if (!sl.isRegistered<MetadataRepository>()) return const [];
    try {
      final rows = await sl<MetadataRepository>().home();
      return [for (final row in rows) ...row.items];
    } catch (_) {
      return const [];
    }
  }

  /// The tail of the trending list — the rows a trending card leads with are
  /// the most popular, so the last items read as "just added" rather than
  /// repeating the top of the chart. Falls back to the list itself when it is
  /// too short to split.
  List<MediaItem> _newestPicks(List<MediaItem> trending) {
    if (trending.length <= 2) return trending;
    return trending.sublist(trending.length ~/ 2);
  }

  static String _dayStamp(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}
