import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/slow_net_tip.dart';

void main() {
  tearDown(SlowNetTip.reset);
  test('only fires once per host while slow', () {
    expect(SlowNetTip.shouldShow('a', slow: true), isTrue);
    expect(SlowNetTip.shouldShow('a', slow: true), isFalse);
    expect(SlowNetTip.shouldShow('a', slow: false), isFalse);
    expect(SlowNetTip.shouldShow('b', slow: true), isTrue);
  });
}
