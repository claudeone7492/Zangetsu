import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/metadata/title_quality.dart';

void main() {
  test('parses the usual release tags', () {
    expect(TitleQualityParser.parse('Film.2024.2160p.WEB'), TitleQuality.uhd);
    expect(TitleQualityParser.parse('Film 1080p BluRay'), TitleQuality.fhd);
    expect(TitleQualityParser.parse('Film 720p'), TitleQuality.hd);
    expect(TitleQualityParser.parse('Film WEB-DL'), TitleQuality.dvd);
    expect(TitleQualityParser.parse('Film HDCAM'), TitleQuality.cam);
    expect(TitleQualityParser.parse('Film TS'), TitleQuality.ts);
    expect(TitleQualityParser.parse('Film'), TitleQuality.unknown);
  });

  test('renders a short badge', () {
    expect(TitleQualityParser.badge('Film 4K'), '4K');
    expect(TitleQualityParser.badge('Film 1080p'), '1080p');
    expect(TitleQualityParser.badge('Film CAM'), 'CAM');
    expect(TitleQualityParser.badge('Film'), isNull);
  });

  test('ranks better copies higher', () {
    expect(
      TitleQualityParser.rank(TitleQuality.uhd),
      greaterThan(TitleQualityParser.rank(TitleQuality.fhd)),
    );
    expect(
      TitleQualityParser.rank(TitleQuality.hd),
      greaterThan(TitleQualityParser.rank(TitleQuality.cam)),
    );
  });
}
