import 'package:flutter/material.dart';

import '../../core/music/music_models.dart';
import '../../core/music/music_player_controller.dart';
import '../../core/music/music_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import 'music_screen.dart' show MusicArtwork;

/// Opens the full player. A sheet rather than a pushed route so the song keeps
/// playing behind it and swiping down returns to the list the listener came
/// from, which is where they almost always want to be next.
Future<void> showMusicPlayerSheet(
  BuildContext context,
  MusicPlayerController player,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MusicPlayerSheet(player: player),
  );
}

class MusicPlayerSheet extends StatelessWidget {
  const MusicPlayerSheet({super.key, required this.player});

  final MusicPlayerController player;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final track = player.current;
        if (track == null) return const SizedBox.shrink();
        final l10n = context.l10n;
        final duration = player.duration;
        final position = player.position > duration && duration > Duration.zero
            ? duration
            : player.position;
        // Material, not a coloured Container: the queue below is a list of
        // ListTiles, and those paint their ink on the nearest Material
        // ancestor. A DecoratedBox in between hides every tap ripple.
        return Material(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.88,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        l10n.musicNowPlaying,
                        textAlign: TextAlign.center,
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                    child: Column(
                      children: [
                        MusicArtwork(url: track.artwork, size: 240),
                        const SizedBox(height: 22),
                        Text(
                          track.title,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artistLabel(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.body.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                        if (track.album != null && track.album!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            track.album!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        _Scrubber(
                          position: position,
                          duration: duration,
                          onSeek: player.seek,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _Toggle(
                              icon: Icons.shuffle_rounded,
                              active: player.shuffle,
                              tooltip: player.shuffle
                                  ? l10n.musicShuffleOn
                                  : l10n.musicShuffleOff,
                              onTap: () => player.setShuffle(!player.shuffle),
                            ),
                            IconButton(
                              onPressed: player.previous,
                              iconSize: 38,
                              icon: const Icon(
                                Icons.skip_previous_rounded,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            _PlayButton(player: player),
                            IconButton(
                              onPressed: player.next,
                              iconSize: 38,
                              icon: const Icon(
                                Icons.skip_next_rounded,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            _Toggle(
                              icon: switch (player.repeat) {
                                MusicRepeat.one => Icons.repeat_one_rounded,
                                _ => Icons.repeat_rounded,
                              },
                              active: player.repeat != MusicRepeat.off,
                              tooltip: switch (player.repeat) {
                                MusicRepeat.off => l10n.musicRepeatOff,
                                MusicRepeat.all => l10n.musicRepeatAll,
                                MusicRepeat.one => l10n.musicRepeatOne,
                              },
                              onTap: player.cycleRepeat,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _Queue(player: player),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.player});

  final MusicPlayerController player;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: player.togglePlayPause,
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          color: AppColors.accent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          player.buffering
              ? Icons.hourglass_top_rounded
              : player.playing
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: active ? AppColors.accent : AppColors.textTertiary,
      ),
    );
  }
}

class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    final max = total <= 0 ? 1.0 : total.toDouble();
    final value = position.inMilliseconds.clamp(0, total).toDouble();
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: AppColors.accent,
            inactiveTrackColor: AppColors.surface2,
            thumbColor: AppColors.accent,
          ),
          child: Slider(
            value: value,
            max: max,
            // Seeking a track whose length is not known yet would snap the thumb
            // to the start on release, which reads as a jump backwards.
            onChanged: total <= 0
                ? null
                : (v) => onSeek(Duration(milliseconds: v.round())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _clock(position),
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
              Text(
                _clock(duration),
                style: AppText.caption.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _clock(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final minutes = total ~/ 60;
    final seconds = (total % 60).toString().padLeft(2, '0');
    if (minutes < 60) return '$minutes:$seconds';
    final hours = minutes ~/ 60;
    return '$hours:${(minutes % 60).toString().padLeft(2, '0')}:$seconds';
  }
}

class _Queue extends StatelessWidget {
  const _Queue({required this.player});

  final MusicPlayerController player;

  @override
  Widget build(BuildContext context) {
    final tracks = player.upNext;
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.l10n.musicUpNext, style: AppText.headline),
        const SizedBox(height: 8),
        for (var i = 0; i < tracks.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: () => player.jumpTo(i),
            leading: MusicArtwork(url: tracks[i].artwork, size: 40),
            title: Text(
              tracks[i].title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                color: i == player.queue.position
                    ? AppColors.accent
                    : AppColors.textPrimary,
                fontWeight: i == player.queue.position
                    ? FontWeight.w600
                    : FontWeight.w400,
              ),
            ),
            subtitle: Text(
              tracks[i].artistLabel(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: AppColors.textTertiary),
            ),
          ),
      ],
    );
  }
}
