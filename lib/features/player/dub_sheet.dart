import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/dub/dub_engine.dart';
import '../../core/dub/dub_narrator.dart';
import '../../core/dub/dub_prefs.dart';
import '../../core/playback/subtitle_language.dart';
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
              Text('AI Dub', style: AppText.headline),
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
                  'text-to-speech voice to use AI Dub.',
                )
              else ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _prefs.enabled,
                  title: Text('Narrate subtitles', style: AppText.body),
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
                  title: Text('Skip sound effects', style: AppText.body),
                  subtitle: Text(
                    'Do not narrate lines like [CROWD CHEERING].',
                    style: AppText.caption.copyWith(color: AppColors.textSecondary),
                  ),
                  onChanged: (v) => _prefs.setSkipSoundEffects(v),
                ),

                const Divider(color: AppColors.hairline, height: 24),
                Text('Narrate in', style: AppText.body),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _voiceChip(
                      label: 'As written',
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
                Text('Voice', style: AppText.body),
                const SizedBox(height: 6),
                if (voices == null)
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
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _voiceChip(
                        label: 'Default',
                        selected: _prefs.voice == null,
                        onTap: () => _prefs.setVoice(null),
                      ),
                      for (final v in voices)
                        _voiceChip(
                          label: v.isNetwork ? '${v.label} · net' : v.label,
                          selected: _prefs.voice == v.name,
                          onTap: () => _prefs.setVoice(v.name),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
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
