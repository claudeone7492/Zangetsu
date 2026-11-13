import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'daily_picks_prefs.dart';
import 'notification_router.dart';

/// Thin wrapper over flutter_local_notifications.
///
/// Two different jobs, with two different platform stories:
///
///   • "New episode" alerts stay ANDROID-ONLY. They depend on the app waking
///     itself to check what aired, and iOS background refresh is a suggestion
///     the system is free to ignore — an alert that fires whenever iOS feels
///     like it is worse than none.
///   • Push broadcasts ([showMessage]) work on iOS too: APNs does the waking,
///     so none of the above applies.
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
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // PushService owns the runtime permission request, so local notifications
    // do not request the same Android permission a second time.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(android: android, iOS: darwin);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (r) =>
          openShowFromNotification(r.payload),
    );
    _inited = true;
  }

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
      await openShowFromNotification(d!.notificationResponse?.payload);
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
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'source_updates',
        'Source updates',
        channelDescription:
            'Alerts when installed sources have updates available',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
    );
    await _plugin.show(
      _sourceUpdatesNotifId,
      'Source updates available',
      count == 1 ? '1 source has an update' : '$count sources have updates',
      details,
    );
  }

  /// Show a general announcement / push message. Used for FCM foreground
  /// messages, which Android does not display on its own (backgrounded ones the
  /// system draws itself, image included). [imageUrl], when set and reachable,
  /// renders as a big-picture notification; [payload] is optional tap data.
  Future<void> showMessage({
    required int id,
    required String title,
    required String body,
    String? imageUrl,
    String? payload,
  }) async {
    // iOS draws foreground pushes itself once
    // setForegroundNotificationPresentationOptions is set (see PushService),
    // so redrawing here would show every broadcast twice.
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    StyleInformation? style;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final picture = await _downloadBitmap(imageUrl);
      if (picture != null) {
        style = BigPictureStyleInformation(
          picture,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        );
      }
    }
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'announcements',
        'Announcements',
        channelDescription: 'News and updates from Zangetsu',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: style,
      ),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Show one of the daily-pick cards, choosing the Android expanded layout by
  /// [style] so the three slots across a day are three distinct designs:
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
    List<String>? lines,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    final styleInfo = await _dailyPickStyle(style, title, body, imageUrl, lines);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_picks',
        'Daily picks',
        channelDescription:
            'Three suggestions a day — new episodes and things to watch',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: styleInfo,
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
    List<String>? lines,
    String? payload,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_inited) await init();
    final styleInfo = await _dailyPickStyle(style, title, body, imageUrl, lines);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_picks',
        'Daily picks',
        channelDescription:
            'Three suggestions a day — new episodes and things to watch',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        styleInformation: styleInfo,
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

  Future<StyleInformation?> _dailyPickStyle(
    DailyPickStyle style,
    String title,
    String body,
    String? imageUrl,
    List<String>? lines,
  ) async {
    switch (style) {
      case DailyPickStyle.bigText:
        return BigTextStyleInformation(body, summaryText: title);
      case DailyPickStyle.bigPicture:
        final url = imageUrl;
        if (url == null || url.isEmpty) return null;
        final picture = await _downloadBitmap(url);
        if (picture == null) return null;
        return BigPictureStyleInformation(
          picture,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        );
      case DailyPickStyle.inbox:
        return InboxStyleInformation(
          lines ?? const [],
          contentTitle: title,
          summaryText: body,
        );
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
