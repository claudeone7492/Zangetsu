import 'dart:convert';

import '../../features/detail/detail_screen.dart';
import '../di/injector.dart';
import '../models/media_item.dart';
import '../mode/content_mode.dart';
import '../models/provider_info.dart';
import '../ui/global_messenger.dart';
import 'subscription_store.dart';

/// Open the Detail screen for the show a new-episode/chapter alert points to.
/// [payload] is "sourceId|url" (split on the FIRST '|' — a url may contain one).
/// The full cover / headers / title come from the stored subscription so Detail
/// renders immediately; it then re-fetches by sourceId+url anyway.
///
/// A daily-pick card carries `"daily:<slot>:<base64url-json>"` instead, so
/// tapping one opens the exact movie/series it led with, with its title and
/// poster already in hand, rather than doing nothing.
Future<void> openShowFromNotification(String? payload) async {
  if (payload == null) return;
  var p = payload;
  if (p.startsWith('daily:')) {
    final sep = p.indexOf(':', 'daily:'.length);
    if (sep < 0) return;
    final rest = p.substring(sep + 1);
    final direct = _dailyItem(rest);
    if (direct != null) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      await nav.push(DetailScreen.route(direct));
      return;
    }
    // Older cards carried "sourceId|url" here instead of the JSON blob.
    p = rest;
  }
  final i = p.indexOf('|');
  if (i < 0) return;
  final sourceId = p.substring(0, i);
  final url = p.substring(i + 1);
  if (sourceId.isEmpty || url.isEmpty) return;

  Subscription? sub;
  if (sl.isRegistered<SubscriptionStore>()) {
    for (final s in sl<SubscriptionStore>().all()) {
      if (s.sourceId == sourceId && s.url == url) {
        sub = s;
        break;
      }
    }
  }

  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  await nav.push(
    DetailScreen.route(
      MediaItem(
        id: url,
        title: sub?.title ?? '',
        url: url,
        // Was hardcoded to anime, which opened a subscribed manga as a video
        // show. The subscription knows what it is.
        type: switch (sub?.mode) {
          ContentMode.manga => ProviderType.manga,
          ContentMode.novel => ProviderType.novel,
          _ => ProviderType.anime,
        },
        sourceId: sourceId,
        cover: sub?.cover,
        coverHeaders: sub?.coverHeaders,
      ),
    ),
  );
}

/// Decode the base64url JSON a daily-pick card carries. Returns null for the
/// older "sourceId|url" form, which the caller handles below.
MediaItem? _dailyItem(String encoded) {
  try {
    final raw = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
    final json = jsonDecode(raw);
    if (json is! Map) return null;
    final sourceId = (json['s'] ?? '').toString();
    final url = (json['u'] ?? '').toString();
    if (sourceId.isEmpty || url.isEmpty) return null;
    final typeName = (json['y'] ?? '').toString();
    final type = ProviderType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => ProviderType.anime,
    );
    final headers = json['h'];
    return MediaItem(
      id: url,
      title: (json['t'] ?? '').toString(),
      url: url,
      type: type,
      sourceId: sourceId,
      cover: _stringOrNull(json['c']),
      banner: _stringOrNull(json['b']),
      coverHeaders: headers is Map
          ? {
              for (final entry in headers.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : null,
    );
  } catch (_) {
    return null;
  }
}

String? _stringOrNull(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
