import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/notify/notification_service.dart';

/// Regression guard for the "notification permission never prompts" bug.
///
/// The request used to sit behind a Firebase Messaging call that throws on any
/// build without google-services.json, so on those builds nothing ever asked and
/// every alert was silently dead. Notifications are drawn locally, so the
/// request must reach the permission channel on its own. These tests pin that.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
  late List<MethodCall> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            // Permission.notification is value 17; granted is 1.
            'requestPermissions' => {17: 1},
            _ => null,
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('requests POST_NOTIFICATIONS when the platform supports it', () async {
    await ensureNotificationPermission(isSupported: () => true);

    expect(calls.map((c) => c.method), contains('requestPermissions'));
    final request = calls.firstWhere((c) => c.method == 'requestPermissions');
    expect(request.arguments, contains(17));
  });

  test('does not touch the channel on an unsupported platform', () async {
    await ensureNotificationPermission(isSupported: () => false);

    expect(calls, isEmpty);
  });

  test('a channel failure never throws', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          throw PlatformException(code: 'boom');
        });

    await expectLater(
      ensureNotificationPermission(isSupported: () => true),
      completes,
    );
  });
}
