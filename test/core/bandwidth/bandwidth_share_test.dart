import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/bandwidth/bandwidth_share.dart';

/// Exercises the real [BandwidthShare] controller against a stubbed native
/// bridge. Only the Android platform gate and the two method-channel replies
/// are faked — the accept/disable logic under test is the shipping code.
class _TestableShare extends BandwidthShare {
  @override
  bool get supported => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel('zangetsu/bandwidth_share');
  const events = EventChannel('zangetsu/bandwidth_share/status');

  late List<String> calls;

  void stubMethod(Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, (call) async {
          calls.add(call.method);
          return handler(call);
        });
  }

  setUp(() {
    calls = [];
    // The controller subscribes to a status stream in its constructor; with no
    // native side the stream simply delivers nothing.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          events,
          MockStreamHandler.inline(onListen: (_, _) {}),
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(events, null);
  });

  test('accept records the opt-in and applies a successful start', () async {
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => {
          'started': true,
          'enabled': true,
          'running': true,
          'status': 'connected',
        },
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept();

    expect(share.answeredConsent, isTrue);
    expect(share.enabled, isTrue);
    expect(share.running, isTrue);
    expect(share.isActive, isTrue);
    expect(share.status, BandwidthShareStatus.connected);
    expect(calls, contains('enable'));
  });

  test('a failed start keeps the opt-in and surfaces an error', () async {
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => {'started': false, 'enabled': true, 'status': 'error'},
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept();

    // The answer and opt-in are final; the status line says the connection
    // failed, and the next resume retries without showing the card again.
    expect(share.answeredConsent, isTrue);
    expect(share.enabled, isTrue);
    expect(share.running, isFalse);
    expect(share.isActive, isFalse);
    expect(share.status, BandwidthShareStatus.error);
  });

  test('a bridge that throws keeps the opt-in and surfaces an error', () async {
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => throw PlatformException(code: 'boom'),
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept();

    expect(share.answeredConsent, isTrue);
    expect(share.enabled, isTrue);
    expect(share.running, isFalse);
    expect(share.isActive, isFalse);
    expect(share.status, BandwidthShareStatus.error);
  });

  test('a stale snapshot cannot clear an answered consent', () async {
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => {
          'started': true,
          'enabled': true,
          'running': true,
          'status': 'connected',
        },
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept();
    await share.refresh();

    expect(share.answeredConsent, isTrue);
  });

  test('the first-run card can close before the relay settles', () async {
    final enableResult = Completer<Map<String, Object?>>();
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => enableResult.future,
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept(waitForStart: false);

    expect(share.answeredConsent, isTrue);
    expect(share.enabled, isTrue);
    expect(share.status, BandwidthShareStatus.connecting);
    expect(enableResult.isCompleted, isFalse);

    enableResult.complete({
      'started': true,
      'enabled': true,
      'running': true,
      'status': 'connected',
    });
    await Future<void>.delayed(Duration.zero);
    expect(share.status, BandwidthShareStatus.connected);
  });

  test('decline remembers the answer and stops sharing', () async {
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => {
          'started': true,
          'enabled': true,
          'running': true,
          'status': 'connected',
        },
        'disable' => {'enabled': false, 'status': 'stopped'},
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept();
    await share.decline();

    expect(share.answeredConsent, isTrue);
    expect(share.enabled, isFalse);
    expect(share.running, isFalse);
    expect(share.isActive, isFalse);
    expect(share.status, BandwidthShareStatus.stopped);
    expect(calls, contains('disable'));
  });

  test('disable clears the flag and stops sharing', () async {
    stubMethod(
      (call) async => switch (call.method) {
        'enable' => {
          'started': true,
          'enabled': true,
          'running': true,
          'status': 'connected',
        },
        'disable' => {'enabled': false, 'status': 'stopped'},
        'snapshot' => {
          'enabled': false,
          'answeredConsent': false,
          'running': false,
          'status': 'stopped',
        },
        _ => null,
      },
    );

    final share = _TestableShare();
    addTearDown(share.dispose);
    await Future<void>.delayed(Duration.zero);

    await share.accept();
    expect(share.enabled, isTrue);

    await share.disable();

    expect(share.enabled, isFalse);
    expect(share.running, isFalse);
    expect(share.isActive, isFalse);
    expect(share.status, BandwidthShareStatus.stopped);
    expect(calls, contains('disable'));
  });
}
