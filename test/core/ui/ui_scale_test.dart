import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/ui/ui_scale.dart';

void main() {
  tearDown(() => UiScale.set(1));
  test('clamps the factor', () {
    UiScale.set(9);
    expect(UiScale.factor, UiScale.max);
    UiScale.set(0.1);
    expect(UiScale.factor, UiScale.min);
  });
}
