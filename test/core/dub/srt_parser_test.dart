import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/dub/srt_parser.dart';

void main() {
  group('SrtParser', () {
    test('parses a plain block with its index and timing', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:03,500\n'
        'Hello there.\n',
      );
      expect(cues, hasLength(1));
      expect(cues.single.start, const Duration(seconds: 1));
      expect(cues.single.end, const Duration(milliseconds: 3500));
      expect(cues.single.text, 'Hello there.');
    });

    test('joins a multi-line cue into one line', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:03,000\n'
        'First line\n'
        'second line\n',
      );
      expect(cues.single.text, 'First line second line');
    });

    test('parses several cues and sorts them by start', () {
      final cues = SrtParser.parse(
        '2\n'
        '00:00:05,000 --> 00:00:06,000\n'
        'Second\n'
        '\n'
        '1\n'
        '00:00:01,000 --> 00:00:02,000\n'
        'First\n',
      );
      expect(cues.map((c) => c.text), ['First', 'Second']);
    });

    test('tolerates CRLF and a BOM', () {
      final cues = SrtParser.parse(
        '\uFEFF1\r\n'
        '00:00:01,000 --> 00:00:02,000\r\n'
        'Windows file\r\n',
      );
      expect(cues.single.text, 'Windows file');
    });

    test('accepts a dot as the decimal separator', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01.250 --> 00:00:02.750\n'
        'Dot decimal\n',
      );
      expect(cues.single.start, const Duration(milliseconds: 1250));
      expect(cues.single.end, const Duration(milliseconds: 2750));
    });

    test('reads 1, 2 and 3 digit milliseconds at the right scale', () {
      final one = SrtParser.parse('00:00:00,5 --> 00:00:09,0\nx');
      expect(one.single.start, const Duration(milliseconds: 500));
      expect(one.single.end, const Duration(seconds: 9));

      final two = SrtParser.parse('00:00:00,25 --> 00:00:09,75\nx');
      expect(two.single.start, const Duration(milliseconds: 250));
      expect(two.single.end, const Duration(milliseconds: 9750));
    });

    test('strips HTML tags, ASS overrides and entities', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:02,000\n'
        '{\\an8}<i>Hello</i> &amp; <b>bye</b>\n',
      );
      expect(cues.single.text, 'Hello & bye');
    });

    test('drops a cue whose text is only markup', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:02,000\n'
        '<i></i>\n',
      );
      expect(cues, isEmpty);
    });

    test('drops a cue that ends before it starts', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:05,000 --> 00:00:02,000\n'
        'Backwards\n',
      );
      expect(cues, isEmpty);
    });

    test('a block with no blank line before the next still parses', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:02,000\n'
        'First\n'
        '2\n'
        '00:00:03,000 --> 00:00:04,000\n'
        'Second\n',
      );
      expect(cues.map((c) => c.text), ['First', 'Second']);
    });

    test('ignores a stray index line inside the body', () {
      final cues = SrtParser.parse(
        '1\n'
        '00:00:01,000 --> 00:00:02,000\n'
        'Hello\n'
        '99\n',
      );
      expect(cues.single.text, 'Hello 99');
    });

    test('empty and whitespace-only sources yield nothing', () {
      expect(SrtParser.parse(''), isEmpty);
      expect(SrtParser.parse('   \n\n  '), isEmpty);
    });

    test('a garbage file yields nothing instead of throwing', () {
      expect(SrtParser.parse('not a subtitle file at all'), isEmpty);
    });
  });
}
