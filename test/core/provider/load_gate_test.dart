import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/provider/load_gate.dart';

void main() {
  test('never exceeds the slot count', () async {
    final gate = LoadGate(maxConcurrent: 2);
    var active = 0;
    var peak = 0;
    await Future.wait([
      for (var i = 0; i < 6; i++)
        gate.run(() async {
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
        }),
    ]);
    expect(peak, lessThanOrEqualTo(2));
    expect(gate.active, 0);
  });

  test('releases the slot when the task throws', () async {
    final gate = LoadGate(maxConcurrent: 1);
    await expectLater(gate.run(() async => throw StateError('x')), throwsStateError);
    expect(gate.active, 0);
  });
}
