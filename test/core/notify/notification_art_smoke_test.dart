import 'dart:io';

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
}
