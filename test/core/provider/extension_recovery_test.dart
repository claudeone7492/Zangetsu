import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/provider/extension_recovery.dart';

void main() {
  setUp(ExtensionRecovery.reset);
  tearDown(ExtensionRecovery.reset);

  test('two stalls in a row ask for a runtime drop', () {
    expect(ExtensionRecovery.shouldRecover('src'), isFalse);
    ExtensionRecovery.noteTimeout('src');
    expect(ExtensionRecovery.shouldRecover('src'), isFalse);
    ExtensionRecovery.noteTimeout('src');
    expect(ExtensionRecovery.shouldRecover('src'), isTrue);
  });

  test('an answer clears the count', () {
    ExtensionRecovery.noteTimeout('src');
    ExtensionRecovery.noteTimeout('src');
    ExtensionRecovery.noteSuccess('src');
    expect(ExtensionRecovery.stalls('src'), 0);
    expect(ExtensionRecovery.shouldRecover('src'), isFalse);
  });

  test('a recovery is not repeated inside the cooldown', () {
    ExtensionRecovery.noteTimeout('src');
    ExtensionRecovery.noteTimeout('src');
    final now = DateTime(2026, 11, 21, 12);
    ExtensionRecovery.markRecovered('src', now: now);
    expect(ExtensionRecovery.shouldRecover('src', now: now), isFalse);
    expect(
      ExtensionRecovery.shouldRecover(
        'src',
        now: now.add(ExtensionRecovery.recoverCooldown),
      ),
      isTrue,
    );
  });

  test('guard rethrows the timeout and recovers once', () async {
    var recovered = 0;
    Future<void> recover() async => recovered++;

    Future<void> boom() async => throw TimeoutException('slow');

    await expectLater(
      ExtensionRecovery.guard('src', boom, recover: recover),
      throwsA(isA<TimeoutException>()),
    );
    expect(recovered, 0, reason: 'one stall is not enough');

    await expectLater(
      ExtensionRecovery.guard('src', boom, recover: recover),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(Duration.zero);
    expect(recovered, 1);
  });

  test('guard returns the value and clears the count on success', () async {
    ExtensionRecovery.noteTimeout('src');
    final value = await ExtensionRecovery.guard('src', () async => 42);
    expect(value, 42);
    expect(ExtensionRecovery.stalls('src'), 0);
  });
}
