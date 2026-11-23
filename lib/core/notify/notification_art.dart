import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Builds the artwork Android shows when a Zangetsu notification is expanded.
///
/// The notification plugin can only hand Android a bitmap, not a custom view.
/// A composite card gives the same result as the approved design: the banner
/// fills the top, the poster sits over it, and the star control sits top-right.
/// The notification's own title and body render above the image, so this only
/// draws the art and the small brand row.
class NotificationArt {
  NotificationArt._();

  static const int _width = 1080;
  static const int _height = 540;
  static const int _bannerHeight = 372;

  static final Map<String, String> _cards = {};
  static String? _starPath;

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

  /// The star large icon Android uses when the notification is collapsed (and
  /// the expanded large-icon slot). Cached on disk so the plugin can read it
  /// from a stable file path.
  static Future<String> starIcon() async {
    final cached = _starPath;
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = await _notificationDir();
    final file = File('${dir.path}/star.png');
    if (await file.exists()) {
      _starPath = file.path;
      return file.path;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 192, 192));
    canvas.drawCircle(
      const Offset(96, 96),
      96,
      Paint()..color = const Color(0xFFFF4D57),
    );
    canvas.drawPath(
      _starPathAt(const Offset(96, 96), 58, 24),
      Paint()..color = Colors.white,
    );
    final image = await recorder.endRecording().toImage(192, 192);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await file.writeAsBytes(data!.buffer.asUint8List(), flush: true);
    _starPath = file.path;
    return file.path;
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
  }) => TextPainter(
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
    maxLines: 1,
    ellipsis: '…',
  )..layout();

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
