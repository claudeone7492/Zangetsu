import 'dart:async';
import 'dart:io';

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../announce/announcement.dart';
import '../app_config.dart';
import '../di/injector.dart';
import '../live/sports_feed.dart';
import '../mode/content_mode.dart';
import '../models/media_item.dart';
import '../models/provider_info.dart';
import '../repository/source_repository.dart';
import '../zmode/metadata_repository.dart';
import '../zmode/zmode_ids.dart';
import 'daily_picks_prefs.dart';
import 'notification_service.dart';
import 'subscription_store.dart';

/// The five-a-day "daily picks" digest.
///
/// Five notifications a day, each about a different *kind* of suggestion —
/// trending movies, the next football fixture, trending anime, new TV/film
/// arrivals, and picked for you. Each slot is spread across the day and lands
/// at a random minute inside its window ([DailyPickSlot.jitterMinutes]), so
/// the cadence is five-a-day without arriving on a metronome.
///
/// Delivery is intentionally opportunistic. A precise daily alarm needs the
/// exact-alarm permission and, on many OEM ROMs, a background service the
/// system may still kill. Instead the scheduler is poked at app start, on
/// resume, and after a check, and it posts whichever slot is *due* and not yet
/// filled today. A missed slot is caught up only while it is still fresh, so
/// opening the app at night never dumps five cards at once. The result is the
/// same five-a-day cadence for a user who opens the app most days, with no
/// exact-alarm prompt and no battery cost.
class DailyPicksService {
  DailyPicksService._();
  static final DailyPicksService instance = DailyPicksService._();

  /// How late a missed slot may still be posted on the next app open. Older
  /// slots are marked filled without a notification so a late-night open does
  /// not fire the whole day's digest at once.
  static const Duration _catchUpWindow = Duration(minutes: 90);

  /// Stable ids per slot so re-firing a slot replaces its card rather than
  /// stacking a sixth.
  static const Map<DailyPickSlot, int> _slotIds = {
    DailyPickSlot.morning: 91001,
    DailyPickSlot.midday: 91002,
    DailyPickSlot.afternoon: 91003,
    DailyPickSlot.evening: 91004,
    DailyPickSlot.night: 91005,
  };

  bool _tzReady = false;

  /// Picks resolved during one sync are reused by the alarm scheduler and the
  /// catch-up post instead of fetching the catalogue/sports feed twice.
  final Map<DailyPickKind, ({DateTime at, List<MediaItem> items})> _pickCache =
      {};

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

  /// Ensure the five slots exist as scheduled alarms for today/tomorrow, then
  /// immediately fill whichever slots are already due and unfilled. Safe to
  /// call repeatedly (start, resume, after a check) — the day-stamp in
  /// [DailyPicksPrefs] makes it idempotent within a day.
  Future<void> sync({bool force = false}) async {
    if (!Platform.isAndroid) return;
    if (!DailyPicksPrefs.enabled && !force) return;
    try {
      _pickCache.clear();
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
      final title = _titleFor(slot);
      final body = _bodyFor(slot, picks);
      await _rememberInApp(slot, title, body, lead, today);
      try {
        await NotificationService.instance.scheduleDailyPick(
          id: _slotIds[slot]!,
          title: title,
          body: body,
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
  /// window, drawn once per day and remembered, so the five land at different
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
  ///
  /// A slot missed by more than [_catchUpWindow] is marked filled without a
  /// notification. That keeps a late-night app open from firing the whole day's
  /// digest at once; the alarm already covers the days the app stays closed.
  Future<void> _fillDueSlots({bool force = false}) async {
    final now = DateTime.now();
    final today = _dayStamp(now);
    final nowMinute = now.hour * 60 + now.minute;
    final due = <DailyPickSlot>[];
    for (final slot in DailyPickSlot.values) {
      if (!DailyPicksPrefs.needsFill(slot, today)) continue;
      final minute = await _minuteOfDay(slot, today);
      if (!force && nowMinute < minute) continue;
      if (!force && nowMinute - minute > _catchUpWindow.inMinutes) {
        await DailyPicksPrefs.markFilled(slot, today);
        continue;
      }
      due.add(slot);
    }
    if (due.isEmpty) return;
    // Force fills one slot; the normal path may catch up several fresh ones.
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
    final title = _titleFor(slot);
    final body = _bodyFor(slot, picks);
    await _rememberInApp(slot, title, body, lead, _dayStamp(DateTime.now()));
    await NotificationService.instance.showDailyPick(
      id: _slotIds[slot]!,
      title: title,
      body: body,
      style: slot.style,
      imageUrl: lead.banner ?? lead.cover,
      lines: [for (final p in picks) p.title],
      payload: _payload(slot, lead),
    );
    return true;
  }

  /// Put the card in the in-app Notifications list as well as the tray, so the
  /// bell badge and history agree with what the user was sent. Keyed by slot
  /// and day, so a re-sync replaces nothing and tomorrow adds five new rows.
  Future<void> _rememberInApp(
    DailyPickSlot slot,
    String title,
    String body,
    MediaItem lead,
    String day,
  ) async {
    if (!sl.isRegistered<AnnouncementStore>()) return;
    try {
      final store = sl<AnnouncementStore>();
      final id = 'daily_${slot.name}_$day';
      if (store.has(id)) return;
      await store.saveNew(
        Announcement(
          id: id,
          title: title,
          body: body,
          type: 'update',
          date: day,
          imageUrl: lead.banner ?? lead.cover,
        ),
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // The in-app history is a bonus; never let it block the tray card.
    }
  }

  /// The headline for a slot's card. Each slot is a different *kind* of
  /// suggestion, so each gets its own headline the way a streaming service
  /// labels its "Trending", "Football", "New arrivals" and "Picks for you"
  /// cards.
  String _titleFor(DailyPickSlot slot) => switch (slot.kind) {
    DailyPickKind.trendingMovies => 'Trending movies on $kAppName',
    DailyPickKind.football => 'Football on $kAppName',
    DailyPickKind.trendingAnime => 'Trending anime on $kAppName',
    DailyPickKind.newRelease => 'New TV series & movies',
    DailyPickKind.recommended => 'Picked for you',
  };

  /// The body text for a slot's card. Football carries the kickoff time; the
  /// big-text layout wants the long story form; the other layouts carry the
  /// detail in the image / line list, so they get a short one-liner. The lead
  /// title is always in the body, so the show being suggested reads clearly
  /// under the kind headline.
  String _bodyFor(DailyPickSlot slot, List<MediaItem> picks) {
    if (slot.kind == DailyPickKind.football) return _footballBody(picks);
    return slot.style == DailyPickStyle.bigText
        ? _bigTextBody(picks)
        : _shortBody(picks);
  }

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

  String _footballBody(List<MediaItem> picks) {
    final lead = picks.first;
    final league = lead.genres.isNotEmpty
        ? lead.genres.first
        : (lead.liveInfo ?? '');
    final when = SportsFeed.isLive(lead)
        ? 'LIVE now'
        : lead.liveStartMs != null
        ? 'starts ${_kickoffLabel(lead.liveStartMs!)}'
        : 'kickoff TBC';
    return [lead.title, if (league.trim().isNotEmpty) league, when].join(' · ');
  }

  /// "today at 20:00" / "tomorrow at 18:30" / "29/11 at 15:00".
  String _kickoffLabel(int startMs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(startMs).toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final prefix = day == today
        ? 'today'
        : day == today.add(const Duration(days: 1))
        ? 'tomorrow'
        : '${dt.day.toString().padLeft(2, '0')}/'
              '${dt.month.toString().padLeft(2, '0')}';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$prefix at $hh:$mm';
  }

  /// The items behind one kind of pick. Each kind draws from a different source
  /// so the five cards a day are different suggestions:
  ///
  ///   • [DailyPickKind.trendingMovies] — the movie/TV home rows.
  ///   • [DailyPickKind.football]       — the next soccer fixture.
  ///   • [DailyPickKind.trendingAnime]  — the anime home rows.
  ///   • [DailyPickKind.newRelease]     — the newest TV/film arrivals.
  ///   • [DailyPickKind.recommended]    — the user's own subscriptions.
  ///
  /// Every title kind falls back to the merged catalogue rows, so a user with
  /// no subscriptions (or a catalogue that only returns one row) still gets
  /// five cards rather than silence.
  Future<List<MediaItem>> _picksFor(DailyPickKind kind) async {
    final hit = _pickCache[kind];
    if (hit != null &&
        DateTime.now().difference(hit.at) < const Duration(minutes: 5)) {
      return hit.items;
    }
    final items = await _buildPicksFor(kind);
    _pickCache[kind] = (at: DateTime.now(), items: items);
    return items;
  }

  Future<List<MediaItem>> _buildPicksFor(DailyPickKind kind) async {
    if (kind == DailyPickKind.football) return _footballPicks();
    final anime = await _cataloguePicks(ZKind.anime);
    final video = await _cataloguePicks(ZKind.movie);
    final trending = _take([...video, ...anime], 60);
    switch (kind) {
      case DailyPickKind.trendingMovies:
        final movies = trending
            .where((m) => m.type == ProviderType.movie && !m.tmdbIsTv)
            .toList();
        return _take(movies.isNotEmpty ? movies : trending, 5);
      case DailyPickKind.trendingAnime:
        final animeOnly = trending
            .where(
              (m) =>
                  m.type == ProviderType.anime ||
                  m.malId != null ||
                  m.anilistId != null,
            )
            .toList();
        return _take(animeOnly.isNotEmpty ? animeOnly : trending, 5);
      case DailyPickKind.newRelease:
        return _take(_newestPicks(trending), 5);
      case DailyPickKind.recommended:
        return _take([..._subscriptionPicks(), ...trending], 5);
      case DailyPickKind.football:
        return _footballPicks();
    }
  }

  /// The next playable football fixtures, live first. The Sports feed already
  /// merges all six sources and drops text-only/linear-channel rows.
  Future<List<MediaItem>> _footballPicks() async {
    if (!sl.isRegistered<SourceRepository>()) return const [];
    try {
      final fixtures = await SportsFeed.fetch(
        sl<SourceRepository>(),
      ).timeout(const Duration(seconds: 25));
      final playable = fixtures.where((m) => !SportsFeed.isFinished(m));
      return _take(playable, 3);
    } catch (_) {
      return const [];
    }
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

  /// Items from a catalogue's home rows, flattened in row order. Asking by kind
  /// (rather than the current content mode) is what lets the movie card and the
  /// anime card coexist even when the app is open in one of those modes.
  Future<List<MediaItem>> _cataloguePicks(ZKind kind) async {
    if (!sl.isRegistered<MetadataRepository>()) return const [];
    final repo = sl<MetadataRepository>();
    try {
      final rows = await repo
          .ensureHomeCached(kind)
          .timeout(const Duration(seconds: 15));
      return _take([for (final row in rows) ...row.items], 200);
    } catch (_) {
      try {
        final rows = await repo.home().timeout(const Duration(seconds: 15));
        return _take([for (final row in rows) ...row.items], 200);
      } catch (_) {
        return const [];
      }
    }
  }

  /// De-duplicated, capped copy of [items], preserving order.
  List<MediaItem> _take(Iterable<MediaItem> items, int limit) {
    final out = <MediaItem>[];
    final seen = <String>{};
    for (final m in items) {
      if (!seen.add('${m.sourceId}:${m.id}')) continue;
      out.add(m);
      if (out.length >= limit) break;
    }
    return out;
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
