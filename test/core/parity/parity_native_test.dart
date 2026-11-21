import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/parity/parity_native.dart';

/// The `zangetsu/parity` seam. The foreground service is reference counted
/// because a second job must not stop the keeper the first one still needs.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('zangetsu/parity');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'captureWindow' => 'Pictures/Zangetsu/frame.png',
            'voicePacks' => <String>[],
            _ => null,
          };
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('captureWindow returns the saved path', () async {
    final path = await ParityNative.captureWindow(name: 'frame');
    expect(path, 'Pictures/Zangetsu/frame.png');
    expect(calls.single.arguments, {'name': 'frame'});
  });

  test('captureWindow reports failure as null instead of throwing', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'capture_failed');
        });
    expect(await ParityNative.captureWindow(), isNull);
  });

  test('work is started once and stopped once across nested jobs', () async {
    await ParityNative.beginWork('Muxing');
    await ParityNative.beginWork('Muxing');
    expect(calls.where((c) => c.method == 'startWork').length, 1);
    expect(ParityNative.workLabel, 'Muxing');

    await ParityNative.endWork();
    expect(calls.where((c) => c.method == 'stopWork'), isEmpty);

    await ParityNative.endWork();
    expect(calls.where((c) => c.method == 'stopWork').length, 1);
    expect(ParityNative.workLabel, isEmpty);
  });

  test('endWork without a matching start does nothing', () async {
    await ParityNative.endWork();
    expect(calls, isEmpty);
  });

  test('voicePacks is empty when the platform has none', () async {
    expect(await ParityNative.voicePacks(), isEmpty);
  });

  test('voicePacks returns the installed offline voices', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'voicePacks'
              ? <String>['en-gb-x-gbb-local', 'en-us-x-iom-local']
              : null;
        });
    expect(await ParityNative.voicePacks(), [
      'en-gb-x-gbb-local',
      'en-us-x-iom-local',
    ]);
  });

  test('openTtsSettings asks the platform and stays quiet off Android', () async {
    await ParityNative.openTtsSettings();
    expect(calls.single.method, 'ttsSettings');

    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await ParityNative.openTtsSettings();
    expect(calls, isEmpty);
  });

  test('tdlibAvailable reports what the build linked', () async {
    expect(await ParityNative.tdlibAvailable(), isFalse);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'tdlib' ? true : null;
        });
    expect(await ParityNative.tdlibAvailable(), isTrue);
  });

  test('desktop skips the channel entirely', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(await ParityNative.captureWindow(), isNull);
    await ParityNative.beginWork('x');
    await ParityNative.endWork();
    expect(calls, isEmpty);
  });
}
