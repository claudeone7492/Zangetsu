import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/web/ad_block.dart';
import 'package:watch_app/core/web/promo_guard.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('promo_guard_test');
    Hive.init(dir.path);
    await AdBlock.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  tearDown(() => AdBlock.instance.setPromosEnabled(true));

  test('blocks donation hosts and their subdomains', () {
    expect(PromoGuard.blocks(Uri.parse('https://ko-fi.com/someone')), isTrue);
    expect(PromoGuard.blocks(Uri.parse('https://www.patreon.com/x')), isTrue);
    expect(PromoGuard.blocks(Uri.parse('https://shop.example.com/x')), isFalse);
  });

  test('blocks donation words in the path and query', () {
    expect(PromoGuard.blocks(Uri.parse('https://example.com/donate')), isTrue);
    expect(PromoGuard.blocks(Uri.parse('https://example.com/support-us')), isTrue);
    expect(
      PromoGuard.blocks(Uri.parse('https://example.com/watch?paypal=1')),
      isTrue,
    );
  });

  test('never blocks a media URL', () {
    expect(
      PromoGuard.blocks(Uri.parse('https://example.com/live.m3u8?donate=1')),
      isFalse,
    );
    expect(
      PromoGuard.blocks(Uri.parse('https://example.com/movie.mp4')),
      isFalse,
    );
  });

  test('respects the stored toggle', () async {
    await AdBlock.instance.setPromosEnabled(false);
    expect(PromoGuard.blocks(Uri.parse('https://ko-fi.com/someone')), isFalse);
  });
}
