import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitle_exporter.dart';

void main() {
  group('SubtitleExporter.timestamp', () {
    test('formats HH:MM:SS,mmm', () {
      expect(SubtitleExporter.timestamp(0), '00:00:00,000');
      expect(SubtitleExporter.timestamp(3723456), '01:02:03,456');
    });

    test('clamps negatives to zero', () {
      expect(SubtitleExporter.timestamp(-500), '00:00:00,000');
    });
  });

  group('SubtitleExporter.fileName', () {
    test('builds a safe .srt name', () {
      expect(SubtitleExporter.fileName('The Matrix'), 'The Matrix.srt');
    });

    test('replaces path-unsafe characters', () {
      final name = SubtitleExporter.fileName('Show: S1/E1 "Pilot"');
      expect(name.endsWith('.srt'), isTrue);
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
      expect(name, isNot(contains('"')));
    });

    test('falls back to a generic name for an empty title', () {
      expect(SubtitleExporter.fileName('   '), 'subtitles.srt');
    });
  });

  group('SubtitleExporter.parseCues', () {
    test('parses SRT cues with comma timestamps', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,500\nHello\n\n'
          '2\n00:00:03,000 --> 00:00:04,000\nWorld\n';
      final cues = SubtitleExporter.parseCues(srt);
      expect(cues.length, 2);
      expect(cues.first.startMillis, 1000);
      expect(cues.first.endMillis, 2500);
      expect(cues.first.text, 'Hello');
    });

    test('parses VTT cues with dot timestamps and strips tags', () {
      const vtt = 'WEBVTT\n\n00:01.000 --> 00:03.000\n'
          '<v Speaker>Hi there</v>\n';
      final cues = SubtitleExporter.parseCues(vtt);
      expect(cues.length, 1);
      expect(cues.first.startMillis, 1000);
      expect(cues.first.text, 'Hi there');
    });

    test('ignores cues that are empty once styling is removed', () {
      const vtt = 'WEBVTT\n\n00:01.000 --> 00:03.000\n<b></b>\n';
      expect(SubtitleExporter.parseCues(vtt), isEmpty);
    });
  });

  group('SubtitleExporter.toSrt', () {
    test('writes numbered blocks sorted by start time', () {
      final out = SubtitleExporter.toSrt(const [
        SubtitleCue(startMillis: 3000, endMillis: 4000, text: 'Second'),
        SubtitleCue(startMillis: 1000, endMillis: 2000, text: 'First'),
      ]);
      expect(out, startsWith('1\n00:00:01,000 --> 00:00:02,000\nFirst\n'));
      expect(out, contains('2\n00:00:03,000 --> 00:00:04,000\nSecond\n'));
    });

    test('round-trips through parseCues', () {
      const original = [
        SubtitleCue(startMillis: 1000, endMillis: 2000, text: 'One'),
        SubtitleCue(startMillis: 2000, endMillis: 3000, text: 'Two'),
      ];
      final reparsed = SubtitleExporter.parseCues(
        SubtitleExporter.toSrt(original),
      );
      expect(reparsed.length, 2);
      expect(reparsed[0].text, 'One');
      expect(reparsed[1].text, 'Two');
      expect(reparsed[0].startMillis, 1000);
    });
  });
}
