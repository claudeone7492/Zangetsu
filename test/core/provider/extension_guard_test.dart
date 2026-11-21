import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/provider/extension_guard.dart';

void main() {
  test('only http and https pass', () {
    expect(ExtensionGuard.isSafeUrl('https://a.b/c'), isTrue);
    expect(ExtensionGuard.isSafeUrl('http://a.b'), isTrue);
    expect(ExtensionGuard.isSafeUrl('javascript:alert(1)'), isFalse);
    expect(ExtensionGuard.isSafeUrl('file:///etc/passwd'), isFalse);
    expect(ExtensionGuard.isSafeUrl('not a url'), isFalse);
  });

  test('turns a throw into null', () async {
    final result = await ExtensionGuard.guard<int>('t', () async => throw StateError('x'));
    expect(result, isNull);
  });

  test('checks a manifest', () {
    expect(ExtensionGuard.checkManifest(name: 'a', version: '1', baseUrl: 'https://x.y'), isNull);
    expect(ExtensionGuard.checkManifest(name: '', version: '1', baseUrl: 'https://x.y'), isNotNull);
    expect(ExtensionGuard.checkManifest(name: 'a', version: '1', baseUrl: 'ftp://x'), isNotNull);
  });
}
