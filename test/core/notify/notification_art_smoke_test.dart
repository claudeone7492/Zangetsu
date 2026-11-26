import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/notify/notification_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the poster row renders a single poster and a three-poster card',
    () async {
      final dir = await Directory.systemTemp.createTemp('zangetsu_art_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path,
          );

      final dio = Dio();
      final one = await NotificationArt.posterRow(
        dio: dio,
        items: const [NotificationArtItem(title: 'One Piece')],
      );
      expect(one, isNotNull);
      expect(File(one!).existsSync(), isTrue);

      final three = await NotificationArt.posterRow(
        dio: dio,
        items: const [
          NotificationArtItem(title: 'One Piece'),
          NotificationArtItem(title: 'Naruto'),
          NotificationArtItem(title: 'Bleach'),
        ],
      );
      expect(three, isNotNull);
      expect(File(three!).existsSync(), isTrue);

      final live = await NotificationArt.posterRow(
        dio: dio,
        items: const [
          NotificationArtItem(
            title: 'Arsenal vs Chelsea',
            subtitle: 'Premier League',
            badge: 'LIVE',
            kind: NotificationArtKind.match,
          ),
        ],
      );
      expect(live, isNotNull);
      expect(File(live!).existsSync(), isTrue);

      await dir.delete(recursive: true);
    },
  );

  test('the collapsed thumb and expanded banner are the spec sizes', () async {
    final dir = await Directory.systemTemp.createTemp('zangetsu_media_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => dir.path,
        );

    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    );
    final url = 'https://example.com/poster.png';
    final dio = Dio()..httpClientAdapter = _BytesAdapter(png);

    final thumb = await NotificationArt.squareThumbnail(dio: dio, url: url);
    final banner = await NotificationArt.wideBanner(dio: dio, url: url);
    expect(thumb, isNotNull);
    expect(banner, isNotNull);

    Future<ui.Image> decode(String path) async {
      final codec = await ui.instantiateImageCodec(
        File(path).readAsBytesSync(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }

    final thumbImage = await decode(thumb!);
    final bannerImage = await decode(banner!);
    expect(thumbImage.width, 256);
    expect(thumbImage.height, 256);
    expect(bannerImage.width, 1024);
    expect(bannerImage.height, 512);
    thumbImage.dispose();
    bannerImage.dispose();

    await dir.delete(recursive: true);
  });
}

class _BytesAdapter implements HttpClientAdapter {
  _BytesAdapter(this.bytes);

  final Uint8List bytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromBytes(
    bytes,
    200,
    headers: {
      Headers.contentTypeHeader: ['image/png'],
    },
  );

  @override
  void close({bool force = false}) {}
}
