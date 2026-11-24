import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import '../app_config.dart';
import '../theme/app_colors.dart';
import 'daily_picks_prefs.dart';
import 'notification_art.dart';
import 'notification_router.dart';

/// Requests the runtime notification permission (Android POST_NOTIFICATIONS,
/// API 33+; the system prompt on iOS).
///
/// This is the app's only notification-permission request, and it lives here
/// with the local-notification owner rather than behind any push transport:
/// alerts are drawn locally, so the prompt must not depend on a remote-push
/// SDK being configured. [isSupported] is injectable so tests can drive the
/// channel without a mobile host.
Future<void> ensureNotificationPermission({
  bool Function()? isSupported,
}) async {
  if (!(isSupported ?? _notificationsSupported)()) return;
  try {
    await Permission.notification.request();
  } catch (_) {}
}

bool _notificationsSupported() =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Thin wrapper over flutter_local_notifications.
///
/// Two different jobs, with two different platform stories:
///
///   • "New episode" alerts stay ANDROID-ONLY. They depend on the app waking
///     itself to check what aired, and iOS background refresh is a suggestion
///     the system is free to ignore — an alert that fires whenever iOS feels
///     like it is worse than none.
///   • [showMessage] draws a general announcement. Android-only, like the
///     other alerts: it exists for foreground events the app itself observes,
///     so there is no iOS counterpart to keep in step.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final Dio _dio = Dio();
  // Native (CS worker) notification taps come over this channel.
  static const MethodChannel _notifChannel = MethodChannel(
    'zangetsu/notifications',
  );

  // A new id, not the old 'daily_picks': Android freezes a channel's importance
  // at creation, so reusing it would keep the old default-importance behaviour.
  static const String _dailyPicksChannelId = 'daily_picks_v2';
  static const String _richChannelId = 'rich_media_v1';
  static const String _smallIcon = 'ic_stat_zangetsu_mono';
  bool _inited = false;

  Future<bool> get canShowAlerts async {
    if (!Platform.isAndroid) return false;
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        false;
  }

  Future<void> init() async {
    if (_inited || !(Platform.isAndroid || Platform.isIOS)) return;
    // Ask for the runtime permission here, before the plugin is set up. This is
    // the app's single notification prompt: alerts are drawn locally, so
    // nothing else needs to own it.
    await ensureNotificationPermission();
    const android = AndroidInitializationSettings(_smallIcon);
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
    );
    // Create the rich-media channel up front so every card lands in the same
    // high-importance channel instead of Android inventing a default one.
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _richChannelId,
            'New releases',
            description:
                'New movies, premieres and watchlist alerts from $kAppName',
            importance: Importance.high,
          ),
        );
    _inited = true;
  }

  /// Route a tap on the card or one of its action buttons. The payload carries
  /// the movie/watchlist URLs; the action id decides which one wins.
  Future<void> handleNotificationResponse(NotificationResponse r) =>
      openShowFromNotification(r.payload, actionId: r.actionId);

  /// Wire notification taps and open the show if the app was launched by one.
  /// Call once the navigator is ready. Handles both notification kinds:
  ///   • Flutter-plugin (JS): init callback for live taps, launch-details here.
  ///   • Native worker (CS): the zangetsu/notifications channel — openShow for
  ///     live taps (onNewIntent), getInitialNotification for cold/back launch.
  Future<void> handleLaunch() async {
    // The native half below is the Android CloudStream worker's channel; there
    // is no iOS equivalent, so iOS has nothing to handle here yet.
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    _notifChannel.setMethodCallHandler((call) async {
      if (call.method == 'openShow') {
        await openShowFromNotification(call.arguments as String?);
      }
    });
    final d = await _plugin.getNotificationAppLaunchDetails();
    if (d?.didNotificationLaunchApp ?? false) {
      final response = d!.notificationResponse;
      await openShowFromNotification(
        response?.payload,
        actionId: response?.actionId,
      );
    }
    try {
      final native = await _notifChannel.invokeMethod<String>(
        'getInitialNotification',
      );
      await openShowFromNotification(native);
    } catch (_) {}
  }

  /// Notify that [title] has a new episode ([episode]). [id] should be stable
  /// per-show so repeated alerts replace rather than stack. [payload] carries
  /// "sourceId|url" for tap handling.
  /// [reading] picks the wording and the channel: manga and novels get their
  /// own so they can be muted without silencing episode alerts, and so the text
  /// doesn't call a chapter an episode.
  Future<void> showNewEpisode({
    required int id,
    required String title,
    required int episode,
    String? payload,
    bool reading = false,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        reading ? 'new_chapters' : 'new_episodes',
        reading ? 'New chapters' : 'New episodes',
        channelDescription: reading
            ? 'Alerts when a subscribed manga or novel has a new chapter'
            : 'Alerts when a subscribed show has a new episode available',
        importance: Importance.high,
        priority: Priority.high,
        color: AppColors.accent,
        icon: _smallIcon,
      ),
    );
    await _plugin.show(
      id,
      title,
      '${reading ? 'Chapter' : 'Episode'} $episode is out',
      details,
      payload: payload,
    );
  }

  /// Stable id for the "source updates available" notification, so a later check
  /// REPLACES the previous one instead of stacking.
  static const int _sourceUpdatesNotifId = 90001;

  /// Notify that [count] installed sources have updates available. A no-op when
  /// [count] is 0. No payload — tapping just opens the app (the badges/Update
  /// buttons live on the Sources screen).
  Future<void> showSourceUpdates({required int count}) async {
    if (!Platform.isAndroid || count <= 0) return;
    if (!_inited) await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'source_updates',
        'Source updates',
        channelDescription:
            'Alerts when installed sources have updates available',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        color: AppColors.accent,
        icon: _smallIcon,
      ),
    );
    await _plugin.show(
      _sourceUpdatesNotifId,
      '$kAppName — $kAppTagline',
      count == 1 ? '1 source has an update' : '$count sources have updates',
      details,
    );
  }

  /// Show a rich media announcement.
  ///
  /// Collapsed: monochrome badge on the left, square [thumbnailUrl] on the
  /// right. Expanded: the square thumbnail disappears and [bannerUrl] fills a
  /// 2:1 card, with the full body and up to two actions. [movieUrl] powers
  /// "Watch Now"; [watchlistUrl] powers "My List". When neither is supplied the
  /// card stays a plain text announcement.
  ///
  Future<void> showMessage({
    required int id,
    required String title,
    required String body,
    String? imageUrl,
    String? posterUrl,
    String? thumbnailUrl,
    String? bannerUrl,
    String? movieUrl,
    String? watchlistUrl,
    String? action1Label,
    String? action2Label,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_inited) await init();

    final banner = (bannerUrl ?? imageUrl)?.trim();
    final thumb = (thumbnailUrl ?? posterUrl ?? banner)?.trim();
    final richPayload = _richPayload(movieUrl, watchlistUrl) ?? payload;
    final thumbBitmap = await _bitmap(thumb, square: true);
    final style = await _mediaStyle(
      title: title,
      body: body,
      bannerUrl: banner,
      thumb: thumbBitmap,
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _richChannelId,
        'New releases',
        channelDescription:
            'New movies, premieres and watchlist alerts from $kAppName',
        importance: Importance.high,
        priority: Priority.high,
        color: AppColors.accent,
        icon: _smallIcon,
        category: AndroidNotificationCategory.recommendation,
        visibility: NotificationVisibility.public,
        largeIcon: thumbBitmap,
        styleInformation: style,
        actions: _actions(movieUrl, watchlistUrl, action1Label, action2Label),
      ),
    );
    await _plugin.show(id, title, body, details, payload: richPayload);
  }

  static List<AndroidNotificationAction> _actions(
    String? movieUrl,
    String? watchlistUrl,
    String? action1Label,
    String? action2Label,
  ) {
    final actions = <AndroidNotificationAction>[];
    if (movieUrl?.trim().isNotEmpty ?? false) {
      actions.add(
        AndroidNotificationAction(
          kWatchNowAction,
          action1Label?.trim().isNotEmpty == true
              ? action1Label!.trim()
              : 'Watch Now',
          icon: const DrawableResourceAndroidBitmap('ic_notif_watch'),
          showsUserInterface: true,
          cancelNotification: true,
        ),
      );
    }
    if (watchlistUrl?.trim().isNotEmpty ?? false) {
      actions.add(
        AndroidNotificationAction(
          kWatchlistAction,
          action2Label?.trim().isNotEmpty == true
              ? action2Label!.trim()
              : 'My List',
          icon: const DrawableResourceAndroidBitmap('ic_notif_add'),
          showsUserInterface: true,
          cancelNotification: true,
        ),
      );
    }
    return actions;
  }

  static String? _richPayload(String? movieUrl, String? watchlistUrl) {
    final data = <String, String>{};
    if (movieUrl?.trim().isNotEmpty ?? false) {
      data['movieUrl'] = movieUrl!.trim();
    }
    if (watchlistUrl?.trim().isNotEmpty ?? false) {
      data['watchlistUrl'] = watchlistUrl!.trim();
    }
    if (data.isEmpty) return null;
    return 'rich:${base64Url.encode(utf8.encode(jsonEncode(data)))}';
  }

  Future<FilePathAndroidBitmap?> _bitmap(
    String? url, {
    required bool square,
  }) async {
    final clean = url?.trim() ?? '';
    if (clean.isEmpty) return null;
    final path = square
        ? await NotificationArt.squareThumbnail(dio: _dio, url: clean)
        : await NotificationArt.wideBanner(dio: _dio, url: clean);
    return path == null ? null : FilePathAndroidBitmap(path);
  }

  Future<StyleInformation?> _mediaStyle({
    required String title,
    required String body,
    required String? bannerUrl,
    required FilePathAndroidBitmap? thumb,
  }) async {
    final banner = await _bitmap(bannerUrl, square: false);
    if (banner == null) return null;
    return BigPictureStyleInformation(
      banner,
      contentTitle: title,
      summaryText: body,
      largeIcon: thumb,
      hideExpandedLargeIcon: true,
    );
  }

  /// Show one of the daily-pick cards, choosing the Android expanded layout by
  /// [style] so the five slots across a day rotate distinct designs:
  ///
  ///   • [DailyPickStyle.bigText]    — title + a long single body.
  ///   • [DailyPickStyle.bigPicture] — title + [imageUrl] as a large image.
  ///   • [DailyPickStyle.inbox]      — title + [lines] as a list.
  ///
  /// Android-only, like the other alerts (iOS draws its own scheduled local
  /// notifications with a fixed layout and no equivalent per-style control).
  Future<void> showDailyPick({
    required int id,
    required String title,
    required String body,
    required DailyPickStyle style,
    String? imageUrl,
    List<NotificationArtItem>? posters,
    List<String>? lines,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    final thumb = await _bitmap(
      _dailyThumbUrl(posters, imageUrl),
      square: true,
    );
    final styleInfo = await _dailyPickStyle(
      style,
      title,
      body,
      imageUrl,
      posters,
      lines,
      thumb,
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _dailyPicksChannelId,
        'Daily picks',
        channelDescription:
            'Five suggestions a day — movies, sports, anime and more',
        importance: Importance.high,
        priority: Priority.high,
        color: AppColors.accent,
        icon: _smallIcon,
        category: AndroidNotificationCategory.recommendation,
        visibility: NotificationVisibility.public,
        largeIcon: thumb,
        styleInformation: styleInfo,
        actions: _dailyActions(payload),
      ),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Schedule a daily-pick card to fire at [when] and repeat at that wall-clock
  /// time each day. Same three designs as [showDailyPick], so the alarm and the
  /// catch-up post are the same card rather than the alarm being a bare
  /// title-less notification.
  ///
  /// [inexactAllowWhileIdle] is deliberate: an exact alarm needs the
  /// exact-alarm permission, which is intrusive for a digest, and Android's
  /// inexact mode still lands close to the requested time.
  Future<void> scheduleDailyPick({
    required int id,
    required String title,
    required String body,
    required DailyPickStyle style,
    required tz.TZDateTime when,
    String? imageUrl,
    List<NotificationArtItem>? posters,
    List<String>? lines,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    final thumb = await _bitmap(
      _dailyThumbUrl(posters, imageUrl),
      square: true,
    );
    final styleInfo = await _dailyPickStyle(
      style,
      title,
      body,
      imageUrl,
      posters,
      lines,
      thumb,
    );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _dailyPicksChannelId,
        'Daily picks',
        channelDescription:
            'Five suggestions a day — movies, sports, anime and more',
        importance: Importance.high,
        priority: Priority.high,
        color: AppColors.accent,
        icon: _smallIcon,
        category: AndroidNotificationCategory.recommendation,
        visibility: NotificationVisibility.public,
        largeIcon: thumb,
        styleInformation: styleInfo,
        actions: _dailyActions(payload),
      ),
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // Re-arms the alarm every day at the same time, so this only has to be
      // scheduled once.
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );
  }

  /// A one-off alert at [when] — a DVR reminder, which must fire exactly once
  /// rather than repeat daily the way [scheduleDailyPick] does.
  ///
  /// Android-only, like every other scheduled alert here. A time already in the
  /// past is dropped: the airing it referred to has started, and a notification
  /// fired immediately would be a lie.
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime when,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    if (!_inited) await init();
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'dvr_reminders',
        'Recordings & reminders',
        channelDescription: 'Reminders for scheduled live programmes',
        importance: Importance.high,
        priority: Priority.high,
        color: AppColors.accent,
        icon: _smallIcon,
      ),
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelScheduled(int id) => _plugin.cancel(id);

  static String? _dailyThumbUrl(
    List<NotificationArtItem>? posters,
    String? fallback,
  ) {
    if (posters != null) {
      for (final poster in posters) {
        final url = poster.imageUrl?.trim() ?? '';
        if (url.isNotEmpty) return url;
      }
    }
    final clean = fallback?.trim() ?? '';
    return clean.isEmpty ? null : clean;
  }

  static List<AndroidNotificationAction>? _dailyActions(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    return [
      const AndroidNotificationAction(
        kWatchNowAction,
        'Watch Now',
        icon: DrawableResourceAndroidBitmap('ic_notif_watch'),
        showsUserInterface: true,
        cancelNotification: true,
      ),
    ];
  }

  Future<StyleInformation?> _dailyPickStyle(
    DailyPickStyle style,
    String title,
    String body,
    String? imageUrl,
    List<NotificationArtItem>? posters,
    List<String>? lines,
    FilePathAndroidBitmap? thumb,
  ) async {
    // Prefer the Netflix-style media card: 2:1 banner expanded, square
    // thumbnail collapsed. The poster-row and text layouts stay as fallbacks
    // for a slot whose artwork cannot be fetched.
    final media = await _mediaStyle(
      title: title,
      body: body,
      bannerUrl: imageUrl,
      thumb: thumb,
    );
    if (media != null) return media;
    final rich = await _richStyle(
      title: title,
      body: body,
      bannerUrl: imageUrl,
      posters: posters,
      eyebrow: 'Daily pick',
    );
    if (rich != null) return rich;
    switch (style) {
      case DailyPickStyle.bigText:
        return BigTextStyleInformation(body, summaryText: title);
      case DailyPickStyle.bigPicture:
        return null;
      case DailyPickStyle.inbox:
        return InboxStyleInformation(
          lines ?? const [],
          contentTitle: title,
          summaryText: body,
        );
    }
  }

  /// Big-picture style using the composite poster row, or the single
  /// banner + poster announcement card. Falls back to the banner alone when
  /// the card cannot be built.
  Future<StyleInformation?> _richStyle({
    required String title,
    required String body,
    String? bannerUrl,
    String? posterUrl,
    List<NotificationArtItem>? posters,
    String? eyebrow,
  }) async {
    try {
      if (posters != null && posters.isNotEmpty) {
        final row = await NotificationArt.posterRow(dio: _dio, items: posters);
        if (row != null) {
          return BigPictureStyleInformation(
            FilePathAndroidBitmap(row),
            contentTitle: title,
            summaryText: body,
          );
        }
      }
      final card = await NotificationArt.card(
        dio: _dio,
        bannerUrl: bannerUrl,
        posterUrl: posterUrl,
        eyebrow: eyebrow,
      );
      if (card != null) {
        return BigPictureStyleInformation(
          FilePathAndroidBitmap(card),
          contentTitle: title,
          summaryText: body,
        );
      }
      if (bannerUrl == null || bannerUrl.isEmpty) return null;
      final picture = await _downloadBitmap(bannerUrl);
      if (picture == null) return null;
      return BigPictureStyleInformation(
        picture,
        contentTitle: title,
        summaryText: body,
      );
    } catch (_) {
      return null;
    }
  }

  /// Download a remote image into a temp file for a big-picture notification.
  /// Returns null on any failure so the notification still shows as text.
  Future<FilePathAndroidBitmap?> _downloadBitmap(String url) async {
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      final file = File(
        '${Directory.systemTemp.path}/notif_${url.hashCode}.img',
      );
      await file.writeAsBytes(bytes);
      return FilePathAndroidBitmap(file.path);
    } catch (_) {
      return null;
    }
  }
}
