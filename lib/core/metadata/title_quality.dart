/// Quality inferred from a release name.
///
/// A source often ships `Movie.2024.1080p.WEB-DL.x264` as the title and no
/// `quality` field, so the poster shows no badge. Hikari's `TitleQuality`
/// parses the name and keeps the best label seen for a title; this is the
/// stateless parser half, used where a badge is rendered.
enum TitleQuality { unknown, cam, ts, dvd, hd, fhd, uhd }

class TitleQualityParser {
  const TitleQualityParser._();

  static final RegExp _uhd = RegExp(r'\b(2160p|4k|uhd)\b', caseSensitive: false);
  static final RegExp _fhd = RegExp(r'\b(1080p|fhd)\b', caseSensitive: false);
  static final RegExp _hd = RegExp(r'\b(720p)\b', caseSensitive: false);
  static final RegExp _dvd = RegExp(
    r'\b(dvdrip|dvd|webrip|web-dl|webdl|bluray|blu-ray|hdtv|brrip)\b',
    caseSensitive: false,
  );
  static final RegExp _ts = RegExp(
    r'\b(telesync|hdts|ts)\b',
    caseSensitive: false,
  );
  static final RegExp _cam = RegExp(
    r'\b(camrip|cam|hdcam|telecine|tc|screener|scr)\b',
    caseSensitive: false,
  );

  static TitleQuality parse(String? title) {
    final text = title ?? '';
    if (text.isEmpty) return TitleQuality.unknown;
    if (_uhd.hasMatch(text)) return TitleQuality.uhd;
    if (_fhd.hasMatch(text)) return TitleQuality.fhd;
    if (_hd.hasMatch(text)) return TitleQuality.hd;
    if (_dvd.hasMatch(text)) return TitleQuality.dvd;
    if (_ts.hasMatch(text)) return TitleQuality.ts;
    if (_cam.hasMatch(text)) return TitleQuality.cam;
    return TitleQuality.unknown;
  }

  static String? badge(String? title) => switch (parse(title)) {
    TitleQuality.uhd => '4K',
    TitleQuality.fhd => '1080p',
    TitleQuality.hd => 'HD',
    TitleQuality.dvd => 'DVD',
    TitleQuality.ts => 'TS',
    TitleQuality.cam => 'CAM',
    TitleQuality.unknown => null,
  };

  /// Ascending quality, for "keep the better copy" decisions.
  static int rank(TitleQuality quality) => quality.index;
}
