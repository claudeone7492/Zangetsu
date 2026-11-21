import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/i18n/tag_translator.dart';

void main() {
  test('translates a known genre into the UI language', () {
    expect(TagTranslator.translate('Action', 'es'), 'Acción');
    expect(TagTranslator.translate('Drama', 'ja'), 'ドラマ');
    expect(TagTranslator.translate('romance', 'fr'), 'Romance');
  });

  test('normalises the science-fiction aliases', () {
    expect(TagTranslator.translate('Sci-Fi', 'ja'), 'SF');
    expect(TagTranslator.translate('science fiction', 'zh'), '科幻');
  });

  test('leaves an unknown tag and an unknown locale alone', () {
    expect(TagTranslator.translate('Isekai', 'de'), 'Isekai');
    expect(TagTranslator.translate('Action', 'xx'), 'Action');
  });
}
