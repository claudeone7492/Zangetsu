/// App-wide adult-title filter.
///
/// Hikari's `NsfwGate` filters items, not just sources: a catalogue that mixes
/// adult titles into a normal row must lose those titles when the user has
/// turned NSFW off. Zangetsu previously only blocked whole NSFW sources, so a
/// mixed row still showed them. This gate is driven by the existing
/// `PlaybackPrefs.nsfwSources` switch — no second setting to keep in sync.
class NsfwGate {
  const NsfwGate._();

  static bool _hideAdult = false;

  static bool get hideAdult => _hideAdult;

  static void setHideAdult(bool value) => _hideAdult = value;

  static final RegExp _adult = RegExp(
    r'(?:\b(?:hentai|ecchi|adult|xxx|porn|r18|explicit|nsfw)\b|18\+)',
    caseSensitive: false,
  );

  static bool isAdultTitle(String? title) =>
      title != null && _adult.hasMatch(title);

  static bool isAdult({String? title, bool flagged = false}) =>
      flagged || isAdultTitle(title);

  static List<T> filter<T>(
    Iterable<T> items, {
    required String? Function(T) title,
    bool Function(T)? flagged,
  }) {
    if (!_hideAdult) return items.toList();
    return [
      for (final item in items)
        if (!isAdult(
          title: title(item),
          flagged: flagged?.call(item) ?? false,
        ))
          item,
    ];
  }
}
