import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/subtitle_text_codec.dart';

void main() {
  group('SubtitleTextCodec.decode', () {
    test('passes valid UTF-8 through unchanged', () {
      const text = '1\n00:00:01,000 --> 00:00:02,000\nDzień dobry, świecie\n';
      expect(SubtitleTextCodec.decode(utf8.encode(text)), text);
    });

    test('strips a UTF-8 byte-order mark', () {
      final bytes = [...utf8.encode('\uFEFF'), ...utf8.encode('Héllo')];
      expect(SubtitleTextCodec.decode(bytes), 'Héllo');
    });

    test('decodes UTF-16 little-endian from its mark', () {
      final units = 'Héllo'.codeUnits;
      final bytes = [0xFF, 0xFE, for (final u in units) ...[u & 0xFF, u >> 8]];
      expect(SubtitleTextCodec.decode(bytes), 'Héllo');
    });

    test('recovers windows-1252 accents that are not valid UTF-8', () {
      // "café" in windows-1252 — 0xE9 is a lone byte, so UTF-8 decoding fails.
      final bytes = utf8.encode('caf') + [0xE9];
      expect(SubtitleTextCodec.decode(bytes), 'café');
    });

    test('recovers windows-1251 Cyrillic', () {
      // "Привет" in windows-1251.
      final bytes = [0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2];
      expect(SubtitleTextCodec.decode(bytes), 'Привет');
    });

    test('a declared charset is honoured when it is a plausible one', () {
      final bytes = utf8.encode('caf') + [0xE9];
      expect(
        SubtitleTextCodec.decode(bytes, declaredCharset: 'windows-1252'),
        'café',
      );
    });

    test('an unknown declared charset does not break decoding', () {
      final bytes = utf8.encode('caf') + [0xE9];
      expect(
        SubtitleTextCodec.decode(bytes, declaredCharset: 'klingon-9'),
        'café',
      );
    });

    test('empty input decodes to empty', () {
      expect(SubtitleTextCodec.decode(const []), '');
    });
  });

  group('charsetFromContentType', () {
    test('reads a charset out of a Content-Type header', () {
      expect(
        SubtitleTextCodec.charsetFromContentType(
          'text/plain; charset=windows-1251',
        ),
        'windows-1251',
      );
    });

    test('reads a quoted charset', () {
      expect(
        SubtitleTextCodec.charsetFromContentType(
          'text/vtt; charset="iso-8859-2"',
        ),
        'iso-8859-2',
      );
    });

    test('is null when the header says nothing useful', () {
      expect(SubtitleTextCodec.charsetFromContentType('text/plain'), isNull);
      expect(SubtitleTextCodec.charsetFromContentType(null), isNull);
    });
  });

  group('prepareSubtitleBytes', () {
    test('re-encodes a caption as UTF-8', () {
      final bytes = utf8.encode(
        '1\n00:00:01,000 --> 00:00:02,000\ncaf',
      ) +
          [0xE9] +
          utf8.encode('\n');
      final out = prepareSubtitleBytes(bytes);
      expect(out, isNotNull);
      expect(utf8.decode(out!), contains('café'));
    });

    test('rejects an HTML error page served with a subtitle URL', () {
      final bytes = utf8.encode('<!DOCTYPE html><html><body>404</body></html>');
      expect(prepareSubtitleBytes(bytes), isNull);
    });

    test('rejects a JSON payload', () {
      expect(prepareSubtitleBytes(utf8.encode('{"error":"not found"}')), isNull);
    });

    test('rejects empty input', () {
      expect(prepareSubtitleBytes(const []), isNull);
    });
  });

  group('decodeSubtitleText', () {
    test('returns the decoded text for a caption', () {
      const srt = '1\n00:00:01,000 --> 00:00:02,000\nHi\n';
      expect(decodeSubtitleText(utf8.encode(srt)), contains('Hi'));
    });

    test('returns null for a non-caption body', () {
      expect(decodeSubtitleText(utf8.encode('<html></html>')), isNull);
    });
  });
}
