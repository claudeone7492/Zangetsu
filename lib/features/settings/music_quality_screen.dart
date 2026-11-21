import 'package:flutter/material.dart';

import '../../core/music/vx_audio_fx.dart';
import '../../core/music/vx_quality.dart';
import '../../l10n/l10n.dart';

/// Music quality and equaliser, the settings half of Hikari's
/// `music/VxQualityUi.kt` + `VxAudioFx.kt`.
class MusicQualityScreen extends StatefulWidget {
  const MusicQualityScreen({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const MusicQualityScreen());

  @override
  State<MusicQualityScreen> createState() => _MusicQualityScreenState();
}

class _MusicQualityScreenState extends State<MusicQualityScreen> {
  late List<double> _gains = VxAudioFx.gains.toList();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.streamingQuality)),
      body: ValueListenableBuilder<int>(
        valueListenable: VxQuality.revision,
        builder: (context, _, _) => ValueListenableBuilder<int>(
          valueListenable: VxAudioFx.revision,
          builder: (context, _, _) {
            _gains = VxAudioFx.gains.toList();
            return ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                SwitchListTile(
                  title: Text(l10n.preferLossless),
                  subtitle: Text(l10n.quality),
                  value: VxQuality.preferLossless,
                  onChanged: VxQuality.setPreferLossless,
                ),
                ListTile(
                  title: Text(l10n.streamingQuality),
                  trailing: DropdownButton<int>(
                    value: VxQuality.streamQuality,
                    onChanged: (value) {
                      if (value != null) VxQuality.setStreamQuality(value);
                    },
                    items: [
                      for (final tier in VxQuality.streamOptions)
                        DropdownMenuItem(
                          value: tier,
                          child: Text(VxQuality.labelFor(tier)),
                        ),
                    ],
                  ),
                ),
                ListTile(
                  title: Text(l10n.downloadQuality),
                  trailing: DropdownButton<int>(
                    value: VxQuality.downloadQuality,
                    onChanged: (value) {
                      if (value != null) VxQuality.setDownloadQuality(value);
                    },
                    items: [
                      for (final tier in VxQuality.downloadOptions)
                        DropdownMenuItem(
                          value: tier,
                          child: Text(VxQuality.labelFor(tier)),
                        ),
                    ],
                  ),
                ),
                SwitchListTile(
                  title: Text(l10n.bitPerfect),
                  subtitle: Text(l10n.equalizer),
                  value: VxQuality.bitPerfect,
                  onChanged: VxQuality.setBitPerfect,
                ),
                SwitchListTile(
                  title: Text(l10n.studioClarity),
                  value: VxQuality.studioClarity,
                  onChanged: VxQuality.setStudioClarity,
                ),
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.equalizer,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Switch(
                        value: VxAudioFx.eqEnabled,
                        onChanged: VxAudioFx.setEnabled,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Flat'),
                        onPressed: () => _preset(
                          List<double>.filled(VxAudioFx.eqFreqs.length, 0),
                        ),
                      ),
                      ActionChip(
                        label: const Text('Studio master'),
                        onPressed: () => _preset(VxAudioFx.studioMaster),
                      ),
                      ActionChip(
                        label: Text(l10n.reset),
                        onPressed: () => _preset(
                          List<double>.filled(VxAudioFx.eqFreqs.length, 0),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < VxAudioFx.eqFreqs.length; i++)
                  _band(i),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${l10n.streamingQuality}: '
                    '${VxQuality.shortLabelFor(VxQuality.streamQuality)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _band(int i) {
    final hz = VxAudioFx.eqFreqs[i];
    final value = _gains.length > i ? _gains[i] : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              VxAudioFx.eqLabel(hz),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(-VxAudioFx.maxGain, VxAudioFx.maxGain),
              min: -VxAudioFx.maxGain,
              max: VxAudioFx.maxGain,
              divisions: 32,
              label: '${value.toStringAsFixed(1)} dB',
              onChanged: (next) {
                setState(() => _gains[i] = next);
                VxAudioFx.setGains(_gains);
              },
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  void _preset(List<double> curve) {
    setState(() => _gains = curve.toList());
    VxAudioFx.setPreset(curve);
  }
}
