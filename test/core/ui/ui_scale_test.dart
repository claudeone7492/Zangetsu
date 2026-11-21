import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/ui/ui_scale.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ui_scale_test');
    Hive.init(dir.path);
    UiScale.resetForTest();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('clamps to the 70..130 % range', () async {
    await UiScale.set(9);
    expect(UiScale.factor, UiScale.max);
    await UiScale.set(0.1);
    expect(UiScale.factor, UiScale.min);
    await UiScale.set(1);
    expect(UiScale.isDefault, isTrue);
  });

  test('persists the factor and reloads it', () async {
    await UiScale.setPercent(120);
    UiScale.resetForTest();
    await UiScale.load();
    expect(UiScale.factor, closeTo(1.2, 1e-9));
    expect(UiScale.percent, 120);
  });

  test('a change bumps the revision so the shell rebuilds', () async {
    final before = UiScale.revision.value;
    await UiScale.set(1.1);
    expect(UiScale.revision.value, before + 1);
  });

  testWidgets('wrap is a no-op at 100 %', (tester) async {
    UiScale.debugSetFactor(1);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => UiScale.wrap(context, const Text('shell')),
        ),
      ),
    );
    expect(find.byType(Transform), findsNothing);
    expect(find.text('shell'), findsOneWidget);
  });

  testWidgets('wrap scales the shell at 120 %', (tester) async {
    UiScale.debugSetFactor(1.2);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => UiScale.wrap(context, const Text('shell')),
        ),
      ),
    );
    final transform = tester.widget<Transform>(find.byType(Transform).first);
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1.2, 1e-6));
    expect(find.text('shell'), findsOneWidget);
  });
}
