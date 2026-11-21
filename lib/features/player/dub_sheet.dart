import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/dub/dub_engine.dart';
import '../../core/dub/dub_narrator.dart';
import '../../core/dub/dub_prefs.dart';
import '../../core/dub/http_tts_service.dart';
import '../../core/parity/parity_native.dart';
import '../../core/playback/subtitle_language.dart';
import '../../l10n/l10n.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';

/// The AI Dub controls: switch it on, pick a voice, and tune how it sounds.
///
/// Kept as its own sheet rather than a section inside the audio panel: the
/// audio panel is already the densest surface in the player, and dub is an
/// occasional feature that should not sit under the viewer's thumb every time
/// they change an audio track.
Future<void> showDubSheet(
  BuildContext context, {
  required bool available,
  DubNarrator? narrator,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DubSheet(narrator: narrator, available: available),
  );
}

class _DubSheet extends StatefulWidget {
  const _DubSheet({required this.available, this.narrator});

  final bool available;

  /// Null when opened from Settings, where there is no playback to follow —
  /// only the preferences are editable there.
  final DubNarrator? narrator;

  @override
  State<_DubSheet> createState() => _DubSheetState();
}

class _DubSheetState extends State<_DubSheet> {
  late final DubPrefs _prefs = GetIt.instance<DubPrefs>();
  List<DubVoice>? _voices;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefs);
    widget.narrator?.addListener(_onPrefs);
    unawaited(_loadVoices());
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    widget.narrator?.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _loadVoices() async {
    final engine = GetIt.instance<DubEngine>();
    final voices = await engine.voices();
    if (!mounted) return;
    setState(() => _voices = voices);
  }

  @override
  Widget build(BuildContext context) {
    final voices = _voices;
    // "Offline only" is a filter, not a second list: the engine still speaks
    // with whatever is picked, it just stops offering voices that need data.
    final shownVoices = voices == null
        ? const <DubVoice>[]
        : _prefs.offlineOnly
        ? voices.where((v) => !v.isNetwork).toList()
        : voices;
    // A device with no TTS is exactly where the hosted voice earns its keep, so
    // the missing-engine notice must not gate the engine choice itself.
    final available = widget.available || _prefs.usesNeuralVoice;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(context.l10n.aiDub, style: AppText.headline),
              const SizedBox(height: 4),
              Text(
                'Reads the current subtitle line aloud. Needs a subtitle track '
                'loaded for this episode.',
                style: AppText.caption.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),

              if (!widget.available)
                _notice(
                  'No speech engine on this device. Install a system '
                  'text-to-speech voice, or pick the neural voice below.',
                ),
              const Divider(color: AppColors.hairline, height: 24),
              _engineSection(context),

              if (available) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _prefs.enabled,
                  title: Text(context.l10n.dubNarrateSubtitles, style: AppText.body),
                  onChanged: (v) => _prefs.setEnabled(v),
                ),

                if (widget.narrator?.error != null) _notice(widget.narrator!.error!),
                if (_prefs.enabled &&
                    widget.narrator != null &&
                    widget.narrator!.cueCount == 0 &&
                    widget.narrator!.error == null)
                  _notice(
                    'No subtitle cues loaded yet. Pick a subtitle track in '
                    'Audio & subtitles first.',
                  ),
                if (widget.narrator?.speaking != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.record_voice_over_rounded,
                          size: 18,
                          color: AppColors.accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.narrator!.speaking!,
                            style: AppText.caption,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                const Divider(color: AppColors.hairline, height: 24),
                _slider(
                  'Rate',
                  _prefs.rate,
                  0.5,
                  2.0,
                  '${_prefs.rate.toStringAsFixed(2)}×',
                  (v) => _prefs.setRate(v),
                ),
                _slider(
                  'Pitch',
                  _prefs.pitch,
                  0.5,
                  2.0,
                  _prefs.pitch.toStringAsFixed(2),
                  (v) => _prefs.setPitch(v),
                ),
                _slider(
                  'Volume',
                  _prefs.volume,
                  0.0,
                  1.0,
                  '${(_prefs.volume * 100).round()}%',
                  (v) => _prefs.setVolume(v),
                ),
                _slider(
                  'Lead',
                  _prefs.leadSeconds,
                  0.0,
                  3.0,
                  '${_prefs.leadSeconds.toStringAsFixed(2)}s',
                  (v) => _prefs.setLeadSeconds(v),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _prefs.skipSoundEffects,
                  title: Text(context.l10n.dubSkipSoundEffects, style: AppText.body),
                  subtitle: Text(
                    'Do not narrate lines like [CROWD CHEERING].',
                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  onChanged: (v) => _prefs.setSkipSoundEffects(v),
                ),

                const Divider(color: AppColors.hairline, height: 24),
                Text(context.l10n.dubNarrateIn, style: AppText.body),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _voiceChip(
                      label: context.l10n.dubAsWritten,
                      selected: _prefs.language == null,
                      onTap: () => _prefs.setLanguage(null),
                    ),
                    for (final lang in kSubtitleLanguages)
                      _voiceChip(
                        label: lang.name,
                        selected: _prefs.language == lang.iso1,
                        onTap: () => _prefs.setLanguage(lang.iso1),
                      ),
                  ],
                ),

                const Divider(color: AppColors.hairline, height: 24),
                const Divider(color: AppColors.hairline, height: 24),
                Text(context.l10n.dubVoice, style: AppText.body),
                const SizedBox(height: 6),
                if (_prefs.usesNeuralVoice)
                  // The hosted voice is picked by language above; listing
                  // device voices here would offer choices that do nothing.
                  Text(
                    context.l10n.voiceEngineNeuralSubtitle,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  )
                else if (voices == null)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (voices.isEmpty)
                  Text(
                    'This device reports no installed voices; the system '
                    'default will be used.',
                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                  )
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _voiceChip(
                        label: context.l10n.defaultLabel,
                        selected: _prefs.voice == null,
                        onTap: () => _prefs.setVoice(null),
                      ),
                      for (final v in shownVoices)
                        _voiceChip(
                          label: _dubVoiceLabel(context.l10n, v),
                          selected: _prefs.voice == v.name,
                          onTap: () => _prefs.setVoice(v.name),
                        ),
                    ],
                  ),
                  if (_prefs.offlineOnly && shownVoices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'No offline voice is installed. Download one in the '
                        'system speech settings, or turn the filter off.',
                        style: AppText.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () => _prefs.setOfflineOnly(
                            !_prefs.offlineOnly,
                          ),
                          icon: Icon(
                            _prefs.offlineOnly
                                ? Icons.cloud_off_rounded
                                : Icons.cloud_queue_rounded,
                            size: 16,
                            color: _prefs.offlineOnly
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          label: Text(
                            'Offline voices only',
                            style: AppText.caption.copyWith(
                              color: _prefs.offlineOnly
                                  ? AppColors.accent
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: ParityNative.openTtsSettings,
                          child: Text(
                            'Download voices',
                            style: AppText.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!_prefs.usesNeuralVoice &&
                    _prefs.voiceScan.speakers.isNotEmpty) ...[
                  const Divider(color: AppColors.hairline, height: 24),
                  Text(context.l10n.voiceCharactersTitle, style: AppText.body),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.voiceCharactersSubtitle,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final speaker in _prefs.voiceScan.speakers)
                    _speakerVoiceRow(context, speaker, voices),
                ],
              ],

              // Speech-to-subtitle lives here rather than in the subtitle
              // section because it is the mirror of dub: one reads a caption
              // aloud, the other writes the caption from the audio.
              const Divider(color: AppColors.hairline, height: 24),
              Text(
                context.l10n.transcribeAudio,
                style: AppText.body,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.transcribeAudioSubtitle,
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _textRow(
                context.l10n.transcriptionEndpoint,
                _prefs.transcriptionEndpoint,
                (v) => _prefs.setTranscriptionEndpoint(v),
                hint: context.l10n.transcriptionEndpointSubtitle,
              ),
              _textRow(
                context.l10n.transcriptionModel,
                _prefs.transcriptionModel,
                (v) => _prefs.setTranscriptionModel(v),
                hint: context.l10n.transcriptionModelSubtitle,
              ),
              _textRow(
                context.l10n.transcriptionKey,
                _prefs.transcriptionKey,
                (v) => _prefs.setTranscriptionKey(v),
                hint: context.l10n.transcriptionKeySubtitle,
                obscure: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One editable line of transcription configuration. A dialog rather than an
  /// inline field: the sheet is scrollable and a keyboard opening inside it
  /// would resize the whole sheet.
  Widget _textRow(
    String label,
    String value,
    ValueChanged<String> onSaved, {
    String? hint,
    bool obscure = false,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(label, style: AppText.body),
    subtitle: Text(
      obscure && value.isNotEmpty
          ? '••••••••'
          : (value.isEmpty ? (hint ?? '') : value),
      style: AppText.caption.copyWith(color: AppColors.textSecondary),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.edit_outlined, size: 18),
    onTap: () => _editText(label, value, onSaved, hint: hint, obscure: obscure),
  );

  Future<void> _editText(
    String label,
    String value,
    ValueChanged<String> onSaved, {
    String? hint,
    bool obscure = false,
  }) async {
    final controller = TextEditingController(text: value);
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    onSaved(saved);
    if (mounted) setState(() {});
  }

  Widget _notice(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      text,
      style: AppText.caption.copyWith(color: AppColors.textSecondary),
    ),
  );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    String display,
    ValueChanged<double> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        SizedBox(width: 64, child: Text(label, style: AppText.body)),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: ((max - min) * 20).round(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 54,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: AppText.caption.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    ),
  );

  /// A selectable engine row. A radio rather than a switch because there are
  /// two named choices, not an on/off.
  /// The engine choice, shown even when the device reports no TTS: a viewer
  /// with no installed voice needs this control to reach the neural one, so it
  /// cannot live behind the availability check.
  Widget _engineSection(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
                Text(context.l10n.voiceEngine, style: AppText.body),
                const SizedBox(height: 4),
                Text(
                  context.l10n.voiceEngineSubtitle,
                  style: AppText.caption.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                _engineOption(
                  title: context.l10n.voiceEngineDevice,
                  subtitle: context.l10n.voiceEngineDeviceSubtitle,
                  selected: !_prefs.usesNeuralVoice,
                  onTap: () => _prefs.setVoiceEngine(kDubEngineDevice),
                ),
                _engineOption(
                  title: context.l10n.voiceEngineNeural,
                  subtitle: context.l10n.voiceEngineNeuralSubtitle,
                  selected: _prefs.usesNeuralVoice,
                  onTap: () => _prefs.setVoiceEngine(kDubEngineNeural),
                ),
                if (_prefs.usesNeuralVoice) ...[
                  const SizedBox(height: 10),
                  Text(
                    context.l10n.neuralVoiceLanguage,
                    style: AppText.body,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _voiceChip(
                        label: context.l10n.followsNarrationLanguage,
                        selected: _prefs.neuralLanguage == null,
                        onTap: () => _prefs.setNeuralLanguage(null),
                      ),
                      for (final v in HttpTtsService.voices)
                        _voiceChip(
                          label: _voiceName(context.l10n, v.labelKey, v.label),
                          selected: _prefs.neuralLanguage == v.iso,
                          onTap: () => _prefs.setNeuralLanguage(v.iso),
                        ),
                    ],
                  ),
                ],

      ],
    );
  }

  Widget _engineOption({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 20,
              color: selected ? AppColors.accent : AppColors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.body),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A language name, translated when the app knows the language.
  ///
  /// [labelKey] is the ARB id; [fallback] is the catalogue's own English name,
  /// used for a key the app has no translation for. Only the display name is
  /// translated — the values persisted by [DubPrefs] are the ISO codes and
  /// voice names passed alongside it, never this label.
  String _voiceName(AppLocalizations l10n, String? labelKey, String fallback) =>
      switch (labelKey) {
        'voiceLangEnglish' => l10n.voiceLangEnglish,
        'voiceLangSpanish' => l10n.voiceLangSpanish,
        'voiceLangFrench' => l10n.voiceLangFrench,
        'voiceLangGerman' => l10n.voiceLangGerman,
        'voiceLangItalian' => l10n.voiceLangItalian,
        'voiceLangPortuguese' => l10n.voiceLangPortuguese,
        'voiceLangRussian' => l10n.voiceLangRussian,
        'voiceLangTurkish' => l10n.voiceLangTurkish,
        'voiceLangIndonesian' => l10n.voiceLangIndonesian,
        'voiceLangHindi' => l10n.voiceLangHindi,
        'voiceLangArabic' => l10n.voiceLangArabic,
        'voiceLangJapanese' => l10n.voiceLangJapanese,
        'voiceLangKorean' => l10n.voiceLangKorean,
        'voiceLangChineseMandarin' => l10n.voiceLangChineseMandarin,
        _ => fallback,
      };

  /// A device or hosted voice as the picker shows it.
  ///
  /// The stored value is [DubVoice.name] alone, so the `(locale)` suffix and
  /// the `· net` marker are display-only. A hosted voice is named by its
  /// language, which the app translates; a device voice keeps the name its own
  /// engine reports, because that is the name the viewer sees in Android's
  /// settings.
  String _dubVoiceLabel(AppLocalizations l10n, DubVoice voice) {
    if (voice.labelKey != null) {
      final name = _voiceName(l10n, voice.labelKey, voice.name);
      return voice.isNetwork ? '$name · net' : name;
    }
    final name = voice.locale.isEmpty ? voice.name : voice.label;
    return voice.isNetwork ? '$name · net' : name;
  }

  /// One detected speaker, showing the voice it will use and opening a picker.
  Widget _speakerVoiceRow(
    BuildContext context,
    String speaker,
    List<DubVoice>? voices,
  ) {
    final chosen = _prefs.voiceForSpeaker(speaker);
    final label = chosen == null
        ? context.l10n.defaultLabel
        : _dubVoiceLabel(
            context.l10n,
            voices?.firstWhere(
                  (v) => v.name == chosen,
                  orElse: () => DubVoice(name: chosen, locale: ''),
                ) ??
                DubVoice(name: chosen, locale: ''),
          );
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(_speakerName(context.l10n, speaker), style: AppText.body),
      subtitle: Text(
        label,
        style: AppText.caption.copyWith(color: AppColors.textSecondary),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: () => _pickSpeakerVoice(context, speaker, voices),
    );
  }

  /// `speaker_0` becomes a localised "Character 1"; a named speaker is shown
  /// as the diarizer reported it.
  String _speakerName(AppLocalizations l10n, String speaker) {
    const prefix = 'speaker_';
    if (speaker.startsWith(prefix)) {
      final n = int.tryParse(speaker.substring(prefix.length));
      if (n != null) return l10n.voiceCharacterLabel(n + 1);
    }
    return speaker;
  }

  Future<void> _pickSpeakerVoice(
    BuildContext context,
    String speaker,
    List<DubVoice>? voices,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_speakerName(context.l10n, speaker)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(context.l10n.defaultLabel),
          ),
          for (final voice in voices ?? const <DubVoice>[])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, voice.name),
              child: Text(_dubVoiceLabel(context.l10n, voice)),
            ),
        ],
      ),
    );
    if (selected == null) return;
    await _prefs.setSpeakerVoice(speaker, selected.isEmpty ? null : selected);
  }

  Widget _voiceChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : AppColors.surface2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: selected ? AppColors.bg : AppColors.textPrimary,
        ),
      ),
    ),
  );
}
