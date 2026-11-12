import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitle_cue_text.dart';

void main() {
  group('SubtitleCueText.text', () {
    test('keeps the cue as-is when stripping is off', () {
      expect(
        SubtitleCueText.text('[CROWD CHEERING] Hello', stripHearingImpaired: false),
        '[CROWD CHEERING] Hello',
      );
    });

    test('removes bracketed sound effects when stripping is on', () {
      expect(
        SubtitleCueText.text('[CROWD CHEERING] Hello', stripHearingImpaired: true),
        'Hello',
      );
    });
  });

  group('SubtitleCueText.strip', () {
    test('removes bracketed effects and music glyphs', () {
      expect(SubtitleCueText.strip('♪ Music playing ♪'), 'Music playing');
      expect(SubtitleCueText.strip('[door slams] Wait!'), 'Wait!');
    });

    test('leaves ordinary dialogue untouched', () {
      expect(SubtitleCueText.strip('Hello there.'), 'Hello there.');
    });

    test('collapses a cue that was only an effect to empty', () {
      expect(SubtitleCueText.strip('[CROWD CHEERING]'), '');
      expect(SubtitleCueText.strip('♪ ♪'), '');
    });
  });

  group('SubtitleCueText.isUntranslatable', () {
    test('is true for empty or whitespace-only text', () {
      expect(SubtitleCueText.isUntranslatable(''), isTrue);
      expect(SubtitleCueText.isUntranslatable('   '), isTrue);
    });

    test('is false for real dialogue', () {
      expect(SubtitleCueText.isUntranslatable('Hello'), isFalse);
    });
  });
}
