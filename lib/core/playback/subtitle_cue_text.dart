/// Reading the words out of a cue, and knowing when there are none.
///
/// Captions for the deaf and hard of hearing carry the sound effects as well as
/// the dialogue — `[CROWD CHEERING]`, `♪ music ♪` — and a translator that is
/// handed those translates the stage directions too, which is noise on screen.
/// They are removed before translation, and a cue that was nothing but a sound
/// effect is then blank and is hidden rather than shown empty.
class SubtitleCueText {
  const SubtitleCueText._();

  static final RegExp _bracket = RegExp(r'\[.*?]');
  static final RegExp _music = RegExp(r'[♪♫]+');

  /// The text of [cue], with its hearing-impaired annotations removed when
  /// [stripHearingImpaired].
  static String text(String cue, {required bool stripHearingImpaired}) =>
      stripHearingImpaired ? strip(cue) : cue.trim();

  /// [text] with bracketed sound effects and music glyphs removed.
  static String strip(String text) =>
      text.replaceAll(_bracket, '').replaceAll(_music, '').trim();

  /// Whether [text] carries nothing a translator could work with.
  static bool isUntranslatable(String text) => text.trim().isEmpty;
}
