import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// How one artwork cell in a notification card should be drawn.
enum NotificationArtKind {
  /// A normal 2:3 film/series poster.
  poster,

  /// A live-sports fixture card: league, teams, kickoff or LIVE badge.
  match,
}

/// One poster or fixture card inside a notification's big-picture artwork.
///
/// [title] is also the fallback when [imageUrl] cannot be downloaded, so a
/// notification never loses a card just because one provider image is down.
class NotificationArtItem {
  const NotificationArtItem({
    required this.title,
    this.imageUrl,
    this.subtitle,
    this.badge,
    this.kind = NotificationArtKind.poster,
  });

  final String title;
  final String? imageUrl;
  final String? subtitle;
  final String? badge;
  final NotificationArtKind kind;
}

/// Builds the artwork Android shows when a Zangetsu notification is expanded.
///
/// The notification plugin can only hand Android a bitmap, not a custom view.
/// A composite card gives the same result as the approved design: the banner
/// fills the top, the poster sits over it, and the star sits on the poster
/// itself. The notification's header uses a monochrome star small icon; no
/// large icon is attached, so there is no second star on the card's right.
/// The notification's own title and body render above the image, so this only
/// draws the art and the small brand row.
class NotificationArt {
  NotificationArt._();

  static const int _width = 1080;
  static const int _height = 540;
  static const int _bannerHeight = 372;

  static final Map<String, String> _cards = {};

  /// A 2:1 card for [bannerUrl] + [posterUrl], cached by URL. Returns null when
  /// neither image can be read, in which case the caller should fall back to
  /// the plain notification.
  static Future<String?> card({
    required Dio dio,
    String? bannerUrl,
    String? posterUrl,
    String? eyebrow,
  }) async {
    final key = '${bannerUrl ?? ''}|${posterUrl ?? ''}|${eyebrow ?? ''}';
    final hit = _cards[key];
    if (hit != null && File(hit).existsSync()) return hit;

    final banner = await _decode(dio, bannerUrl);
    final poster = await _decode(dio, posterUrl);
    if (banner == null && poster == null) return null;

    try {
      final path = await _render(
        banner: banner,
        poster: poster,
        eyebrow: eyebrow,
        key: key,
      );
      _cards[key] = path;
      return path;
    } finally {
      banner?.dispose();
      poster?.dispose();
    }
  }

  static Future<String> _render({
    required ui.Image? banner,
    required ui.Image? poster,
    required String? eyebrow,
    required String key,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
      Paint()..color = const Color(0xFF16161C),
    );

    if (banner != null) {
      _drawCover(
        canvas,
        banner,
        Rect.fromLTWH(0, 0, _width.toDouble(), _bannerHeight.toDouble()),
      );
    } else if (poster != null) {
      _drawCover(
        canvas,
        poster,
        Rect.fromLTWH(0, 0, _width.toDouble(), _bannerHeight.toDouble()),
      );
    }

    canvas.drawRect(
      Rect.fromLTWH(0, 0, _width.toDouble(), _bannerHeight.toDouble()),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 110),
          Offset(0, _bannerHeight.toDouble()),
          const [Color(0x000B0B0F), Color(0xFF16161C)],
          const [0, 1],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, _width.toDouble(), _bannerHeight.toDouble()),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(_width.toDouble(), 0),
          const [Color(0x660B0B0F), Color(0x000B0B0F)],
          const [0, 0.72],
        ),
    );

    final posterRect = Rect.fromLTWH(54, 214, 180, poster == null ? 0 : 270);
    if (poster != null) {
      final rr = RRect.fromRectAndRadius(posterRect, const Radius.circular(18));
      canvas.save();
      canvas.clipRRect(rr);
      _drawCover(canvas, poster, posterRect);
      canvas.restore();
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = const Color(0xFF191A21),
      );
    }

    // The star control from the approved card, top-right.
    const starCenter = Offset(980, 92);
    canvas.drawCircle(starCenter, 52, Paint()..color = const Color(0xCC0B0B0F));
    canvas.drawCircle(
      starCenter,
      52,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x33FFFFFF),
    );
    canvas.drawPath(
      _starPathAt(starCenter, 30, 13),
      Paint()..color = Colors.white,
    );

    if (eyebrow != null && eyebrow.trim().isNotEmpty) {
      final label = eyebrow.trim().toUpperCase();
      final tp = _text(
        label,
        size: 24,
        color: Colors.white,
        weight: FontWeight.w800,
        letterSpacing: 1.8,
      );
      const left = 56.0;
      const top = 54.0;
      final chip = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, tp.width + 34, 46),
        const Radius.circular(23),
      );
      canvas.drawRRect(chip, Paint()..color = const Color(0xFFFF4D57));
      tp.paint(canvas, Offset(left + 17, top + 10));
    }

    // Brand row at the bottom-left, matching the card footer.
    canvas.drawCircle(
      const Offset(72, 492),
      15,
      Paint()..color = const Color(0xFFFF4D57),
    );
    _text(
      'Z',
      size: 20,
      color: Colors.white,
      weight: FontWeight.w900,
    ).paint(canvas, const Offset(64, 480));
    _text(
      'Zangetsu',
      size: 24,
      color: Colors.white,
      weight: FontWeight.w700,
    ).paint(canvas, const Offset(102, 476));
    _text(
      'Tap to watch',
      size: 23,
      color: const Color(0xFFFF4D57),
      weight: FontWeight.w700,
    ).paint(canvas, const Offset(896, 477));

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width, _height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final dir = await _notificationDir();
    final file = File('${dir.path}/card_${key.hashCode}.png');
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    _prune(dir);
    return file.path;
  }

  /// A 2:1 card containing one to three 2:3 poster cells. The first three
  /// [items] are drawn; callers add "+N more" to the body for anything after
  /// that. Returns null only when [items] is empty.
  static Future<String?> posterRow({
    required Dio dio,
    required List<NotificationArtItem> items,
  }) async {
    final cards = items.take(3).toList(growable: false);
    if (cards.isEmpty) return null;

    final key = _rowKey(cards);
    final hit = _cards[key];
    if (hit != null && File(hit).existsSync()) return hit;

    final images = await Future.wait([
      for (final card in cards) _decode(dio, card.imageUrl),
    ]);
    try {
      final path = await _renderRow(items: cards, images: images, key: key);
      _cards[key] = path;
      return path;
    } finally {
      for (final image in images) {
        image?.dispose();
      }
    }
  }

  /// A square 256×256 thumbnail for the collapsed notification's large icon.
  /// Android crops the large icon to a square, so doing it here keeps the
  /// subject centred instead of letterboxed.
  static Future<String?> squareThumbnail({required Dio dio, String? url}) =>
      _crop(dio: dio, url: url, width: 256, height: 256, prefix: 'thumb');

  /// A 2:1 landscape banner (1024×512) for the expanded BigPicture card.
  static Future<String?> wideBanner({required Dio dio, String? url}) =>
      _crop(dio: dio, url: url, width: 1024, height: 512, prefix: 'wide');

  static Future<String?> _crop({
    required Dio dio,
    required String? url,
    required int width,
    required int height,
    required String prefix,
  }) async {
    final clean = url?.trim() ?? '';
    if (clean.isEmpty) return null;
    final key = '$prefix|$width|$height|$clean';
    final hit = _cards[key];
    if (hit != null && File(hit).existsSync()) return hit;

    final image = await _decode(dio, clean);
    if (image == null) return null;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = const Color(0xFF16161C),
      );
      _drawCover(
        canvas,
        image,
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(width, height);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();

      final dir = await _notificationDir();
      final file = File('${dir.path}/${prefix}_${key.hashCode}.png');
      await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
      _prune(dir);
      _cards[key] = file.path;
      return file.path;
    } finally {
      image.dispose();
    }
  }

  static String _rowKey(List<NotificationArtItem> items) {
    final body = items
        .map(
          (i) =>
              '${i.kind.name}|${i.title}|${i.subtitle ?? ''}|'
              '${i.badge ?? ''}|${i.imageUrl ?? ''}',
        )
        .join('||');
    return 'row|$body';
  }

  static Future<String> _renderRow({
    required List<NotificationArtItem> items,
    required List<ui.Image?> images,
    required String key,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, _width.toDouble(), _height.toDouble()),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, _height.toDouble()),
          const [Color(0xFF17171F), Color(0xFF09090C)],
          const [0, 1],
        ),
    );
    canvas.drawCircle(
      const Offset(110, 70),
      240,
      Paint()..color = const Color(0x1AFF4D57),
    );
    canvas.drawCircle(
      const Offset(980, 500),
      260,
      Paint()..color = const Color(0x120B84FF),
    );

    final count = items.length;
    final posterHeight = switch (count) {
      1 => 500.0,
      2 => 480.0,
      _ => 450.0,
    };
    final posterWidth = posterHeight * 2 / 3;
    final gap = count == 3 ? 24.0 : 28.0;
    final totalWidth = posterWidth * count + gap * (count - 1);
    final startX = (_width - totalWidth) / 2;
    final top = (_height - posterHeight) / 2;

    for (var i = 0; i < count; i++) {
      final rect = Rect.fromLTWH(
        startX + i * (posterWidth + gap),
        top,
        posterWidth,
        posterHeight,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(20));
      canvas.save();
      canvas.clipRRect(rr);
      if (items[i].kind == NotificationArtKind.match) {
        _drawMatchCard(canvas, rect, items[i], images[i]);
      } else {
        _drawPosterCard(canvas, rect, items[i], images[i]);
      }
      if (i == 0) _drawStarBadge(canvas, rect);
      canvas.restore();
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0x33FFFFFF),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_width, _height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final dir = await _notificationDir();
    final file = File('${dir.path}/card_${key.hashCode}.png');
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    _prune(dir);
    return file.path;
  }

  static void _drawPosterCard(
    Canvas canvas,
    Rect rect,
    NotificationArtItem item,
    ui.Image? image,
  ) {
    if (image != null) {
      _drawCover(canvas, image, rect);
      if (item.badge != null && item.badge!.trim().isNotEmpty) {
        _drawBadge(canvas, rect, item.badge!);
      }
      return;
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          const [Color(0xFF2A2A38), Color(0xFF121218)],
          const [0, 1],
        ),
    );
    final initials = _initials(item.title);
    final initialsTp = _text(
      initials,
      size: 58,
      color: const Color(0xCCFFFFFF),
      weight: FontWeight.w900,
    );
    initialsTp.paint(
      canvas,
      rect.center - Offset(initialsTp.width / 2, initialsTp.height / 2),
    );
    final titleTp = _text(
      item.title,
      size: 24,
      color: Colors.white,
      weight: FontWeight.w800,
      maxLines: 3,
      maxWidth: rect.width - 28,
    );
    titleTp.paint(
      canvas,
      Offset(rect.left + 14, rect.bottom - 20 - titleTp.height),
    );
    if (item.badge != null && item.badge!.trim().isNotEmpty) {
      _drawBadge(canvas, rect, item.badge!);
    }
  }

  static void _drawMatchCard(
    Canvas canvas,
    Rect rect,
    NotificationArtItem item,
    ui.Image? image,
  ) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          const [Color(0xFF242432), Color(0xFF101014)],
          const [0, 1],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(rect.left, rect.top, rect.width, 5),
      Paint()..color = const Color(0xFFFF4D57),
    );

    final logoSize = rect.width * 0.52;
    final logoRect = Rect.fromLTWH(
      rect.left + (rect.width - logoSize) / 2,
      rect.top + 34,
      logoSize,
      logoSize,
    );
    if (image != null) {
      canvas.drawCircle(
        logoRect.center,
        logoSize / 2 + 7,
        Paint()..color = const Color(0xFF2C2C38),
      );
      canvas.save();
      canvas.clipPath(Path()..addOval(logoRect));
      _drawCover(canvas, image, logoRect);
      canvas.restore();
    } else {
      canvas.drawCircle(
        logoRect.center,
        logoSize / 2,
        Paint()..color = const Color(0xFF2C2C38),
      );
      final initials = _initials(item.title);
      final initialsTp = _text(
        initials,
        size: 50,
        color: const Color(0xCCFFFFFF),
        weight: FontWeight.w900,
      );
      initialsTp.paint(
        canvas,
        logoRect.center - Offset(initialsTp.width / 2, initialsTp.height / 2),
      );
    }

    final overlay = Rect.fromLTWH(
      rect.left,
      rect.bottom - rect.height * 0.48,
      rect.width,
      rect.height * 0.48,
    );
    canvas.drawRect(
      overlay,
      Paint()
        ..shader = ui.Gradient.linear(
          overlay.topCenter,
          overlay.bottomCenter,
          const [Color(0x00000000), Color(0xE6000000)],
          const [0, 1],
        ),
    );

    final subtitle = item.subtitle?.trim();
    final subtitleTp = subtitle != null && subtitle.isNotEmpty
        ? _text(
            subtitle,
            size: 17,
            color: const Color(0xB3FFFFFF),
            weight: FontWeight.w600,
            maxLines: 1,
            maxWidth: rect.width - 28,
          )
        : null;
    final titleTp = _text(
      item.title,
      size: 24,
      color: Colors.white,
      weight: FontWeight.w800,
      maxLines: 2,
      maxWidth: rect.width - 28,
    );

    var bottom = rect.bottom - 20;
    if (subtitleTp != null) {
      bottom -= subtitleTp.height;
      subtitleTp.paint(canvas, Offset(rect.left + 14, bottom));
      bottom -= 6;
    }
    bottom -= titleTp.height;
    titleTp.paint(canvas, Offset(rect.left + 14, bottom));

    if (item.badge != null && item.badge!.trim().isNotEmpty) {
      _drawBadge(canvas, rect, item.badge!);
    }
  }

  static void _drawStarBadge(Canvas canvas, Rect rect) {
    const radius = 25.0;
    final center = Offset(rect.right - 30, rect.top + 30);
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xCC0B0B0F));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x33FFFFFF),
    );
    canvas.drawPath(
      _starPathAt(center, 15, 6.5),
      Paint()..color = Colors.white,
    );
  }

  static void _drawBadge(Canvas canvas, Rect rect, String value) {
    final label = value.trim().toUpperCase();
    if (label.isEmpty) return;
    final tp = _text(
      label,
      size: 17,
      color: Colors.white,
      weight: FontWeight.w800,
      letterSpacing: 0.5,
    );
    final chip = RRect.fromRectAndRadius(
      Rect.fromLTWH(rect.left + 14, rect.top + 14, tp.width + 20, 29),
      const Radius.circular(14.5),
    );
    canvas.drawRRect(chip, Paint()..color = const Color(0xE6FF4D57));
    tp.paint(canvas, Offset(rect.left + 24, rect.top + 20));
  }

  static String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .where(
          (w) => !const {'vs', 'v', '@', '-', 'live'}.contains(w.toLowerCase()),
        )
        .toList();
    if (words.isEmpty) return '?';
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  static Future<ui.Image?> _decode(Dio dio, String? url) async {
    final clean = url?.trim() ?? '';
    if (clean.isEmpty) return null;
    try {
      final res = await dio.get<List<int>>(
        clean,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
        ),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static void _drawCover(Canvas canvas, ui.Image image, Rect dst) {
    final src = _coverRect(
      Size(image.width.toDouble(), image.height.toDouble()),
      dst.size,
    );
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  static Rect _coverRect(Size source, Size target) {
    final sourceRatio = source.width / source.height;
    final targetRatio = target.width / target.height;
    if (sourceRatio > targetRatio) {
      final width = source.height * targetRatio;
      return Rect.fromLTWH((source.width - width) / 2, 0, width, source.height);
    }
    final height = source.width / targetRatio;
    return Rect.fromLTWH(0, (source.height - height) / 2, source.width, height);
  }

  static Path _starPathAt(Offset center, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  static TextPainter _text(
    String value, {
    required double size,
    required Color color,
    required FontWeight weight,
    double letterSpacing = 0,
    int maxLines = 1,
    double? maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    painter.layout(maxWidth: maxWidth ?? double.infinity);
    return painter;
  }

  static Future<Directory> _notificationDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}/notification_cards',
    ).create(recursive: true);
  }

  static void _prune(Directory dir) {
    try {
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.png'))
              .toList()
            ..sort(
              (a, b) => a.statSync().modified.compareTo(b.statSync().modified),
            );
      const keep = 24;
      while (files.length > keep) {
        files.removeAt(0).deleteSync();
      }
    } catch (_) {}
  }
}
