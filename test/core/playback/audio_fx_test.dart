import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/audio_fx.dart';

void main() {
  test('none leaves the chain empty', () {
    expect(AudioFxChain.filterFor(AudioFx.none), isNull);
  });
  test('every other preset names lavfi', () {
    for (final fx in AudioFx.values.where((f) => f != AudioFx.none)) {
      expect(AudioFxChain.filterFor(fx), contains('lavfi='));
    }
  });
}
