import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitle_text_normalizer.dart';

void main() {
  group('looksLikeSubtitle', () {
    test('accepts SRT, VTT and ASS', () {
      expect(
        SubtitleTextNormalizer.looksLikeSubtitle(
          '1\n00:00:01,000 --> 00:00:02,000\nHi\n',
        ),
        isTrue,
      );
      expect(
        SubtitleTextNormalizer.looksLikeSubtitle(
          'WEBVTT\n\n00:01.000 --> 00:03.000\nHi\n',
        ),
        isTrue,
      );
      expect(
        SubtitleTextNormalizer.looksLikeSubtitle(
          '[Script Info]\nTitle: x\n[Events]\n'
          'Format: Layer, Start, End, Style, Text\n'
          'Dialogue: 0,0:00:01.00,0:00:02.00,Default,Hi\n',
        ),
        isTrue,
      );
    });

    test('rejects HTML and JSON bodies', () {
      expect(
        SubtitleTextNormalizer.looksLikeSubtitle('<html><body>404</body></html>'),
        isFalse,
      );
      expect(
        SubtitleTextNormalizer.looksLikeSubtitle('{"error":"nope"}'),
        isFalse,
      );
      expect(SubtitleTextNormalizer.looksLikeSubtitle('   '), isFalse);
    });
  });

  group('normalize', () {
    test('wraps an SRT body as VTT with dot timestamps', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,500\nHello\n\n'
          '2\n00:00:03,000 --> 00:00:04,000\nWorld\n';
      final out = SubtitleTextNormalizer.normalize(srt);
      expect(out, isNotNull);
      expect(out, startsWith('WEBVTT\n\n'));
      expect(out, contains('00:00:01.000 --> 00:00:02.500'));
      expect(out, contains('Hello'));
    });

    test('strips leftover ASS override tags from an SRT body', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,000\n'
          r'{\an8}{\i1}Styled{\i0}'
          '\n';
      final out = SubtitleTextNormalizer.normalize(srt);
      expect(out, contains('Styled'));
      expect(out, isNot(contains(r'{\an8}')));
    });

    test('leaves an existing VTT body alone', () {
      const vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n';
      final out = SubtitleTextNormalizer.normalize(vtt);
      expect(out, isNotNull);
      expect(out, contains('00:00:01.000 --> 00:00:02.000'));
      expect(out, isNot(contains('WEBVTT\n\nWEBVTT')));
    });

    test('returns null for an HTML error page', () {
      expect(
        SubtitleTextNormalizer.normalize('<html><body>403</body></html>'),
        isNull,
      );
    });
  });

  group('assToVtt', () {
    const ass = '[Script Info]\n'
        'Title: Sample\n'
        'ScriptType: v4.00+\n'
        '\n'
        '[V4+ Styles]\n'
        'Format: Name, Fontname, Fontsize\n'
        'Style: Default,Arial,20\n'
        '\n'
        '[Events]\n'
        'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, '
        'Effect, Text\n'
        'Dialogue: 0,0:00:01.00,0:00:02.50,Default,,0,0,0,,Hello, there\n'
        'Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,'
        r'{\i1}Italic{\i0}\NSecond line'
        '\n';

    test('detects ASS input', () {
      expect(SubtitleTextNormalizer.isAss(ass), isTrue);
    });

    test('converts timings and text, keeping commas inside the text', () {
      final out = SubtitleTextNormalizer.assToVtt(ass);
      expect(out, startsWith('WEBVTT\n\n'));
      expect(out, contains('00:00:01.000 --> 00:00:02.500'));
      expect(out, contains('Hello, there'));
    });

    test('drops override tags and turns \\N into a line break', () {
      final out = SubtitleTextNormalizer.assToVtt(ass);
      expect(out, contains('Italic'));
      expect(out, isNot(contains(r'{\i1}')));
      expect(out, contains('Italic\nSecond line'));
    });

    test('drops vector-drawing cues', () {
      const drawing = '[Script Info]\n[Events]\n'
          'Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
          'MarginV, Effect, Text\n'
          r'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,{\p1}m 0 0 l 10 0 10 10 0 10{\p0}'
          '\n'
          'Dialogue: 0,0:00:03.00,0:00:04.00,Default,,0,0,0,,Real text\n';
      final out = SubtitleTextNormalizer.assToVtt(drawing);
      expect(out, contains('Real text'));
      expect(out, isNot(contains('m 0 0 l 10 0')));
    });

    test('reads a reordered Format line', () {
      const reordered = '[Script Info]\n[Events]\n'
          'Format: Start, End, Text\n'
          'Dialogue: 0:00:05.00,0:00:06.00,Reordered text\n';
      final out = SubtitleTextNormalizer.assToVtt(reordered);
      expect(out, contains('00:00:05.000 --> 00:00:06.000'));
      expect(out, contains('Reordered text'));
    });
  });
}
