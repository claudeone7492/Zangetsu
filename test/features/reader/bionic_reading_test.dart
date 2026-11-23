import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:watch_app/features/reader/bionic_reading.dart';

void main() {
  test('bolds the leading part of every word and keeps the rest', () {
    final out = applyBionicReading('<p>Hello world</p>');
    expect(out, contains('<b>He</b>llo'));
    expect(out, contains('<b>wo</b>rld'));
  });

  test('the visible text is unchanged', () {
    const source = '<p>Hello &amp; welcome, reader.</p>';
    final out = applyBionicReading(source);
    expect(
      html_parser.parseFragment(out).text,
      html_parser.parseFragment(source).text,
    );
  });

  test('does not rewrite attribute values that look like words', () {
    final out = applyBionicReading(
      '<p><a href="https://hello.world/read">hello</a></p>',
    );
    expect(out, contains('href="https://hello.world/read"'));
    expect(out, isNot(contains('href="https://<b>')));
  });

  test('already-bold text is left alone', () {
    final out = applyBionicReading('<p><b>hello</b></p>');
    expect(out, contains('<b>hello</b>'));
    expect(out, isNot(contains('<b><b>')));
  });

  test('one-letter words stay one bold letter', () {
    final out = applyBionicReading('<p>a b</p>');
    expect(out, contains('<b>a</b>'));
    expect(out, contains('<b>b</b>'));
  });
}
