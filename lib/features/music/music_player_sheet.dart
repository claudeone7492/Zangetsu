import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/music/music_download.dart';
import '../../core/music/music_models.dart';
import '../../core/music/music_player_controller.dart';
import '../../core/music/music_queue.dart';
import '../../core/music/music_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
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
  const MusicPlayerSheet({super.key, required this.player, this.tv});

  final MusicPlayerController player;

  /// Null means "ask [AppMode]" — explicit only so a test can force either
  /// layout without registering the mode.
  final bool? tv;

  @override
  Widget build(BuildContext context) {
    final leanback = tv ?? (sl.isRegistered<AppMode>() && sl<AppMode>().isTv);
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
                    if (leanback)
                      // A bottom sheet on leanback needs a reachable way out:
                      // Back also closes it, but a remote user should not have
                      // to know that to dismiss the player.
                      TvFocusable(
                        onTap: () => Navigator.of(context).maybePop(),
                        variant: TvFocusVariant.pill,
                        borderRadius: 20,
                        semanticLabel: 'Close player',
                        builder: (_) => const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textPrimary,
                        ),
                      )
                    else
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
                              tv: leanback,
                            ),
                            if (leanback)
                              TvFocusable(
                                onTap: player.previous,
                                variant: TvFocusVariant.pill,
                                borderRadius: 24,
                                semanticLabel: 'Previous',
                                builder: (_) => const Icon(
                                  Icons.skip_previous_rounded,
                                  size: 38,
                                  color: AppColors.textPrimary,
                                ),
                              )
                            else
                              IconButton(
                                onPressed: player.previous,
                                iconSize: 38,
                                icon: const Icon(
                                  Icons.skip_previous_rounded,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            _PlayButton(player: player, tv: leanback),
                            if (leanback)
                              TvFocusable(
                                onTap: player.next,
                                variant: TvFocusVariant.pill,
                                borderRadius: 24,
                                semanticLabel: 'Next',
                                builder: (_) => const Icon(
                                  Icons.skip_next_rounded,
                                  size: 38,
                                  color: AppColors.textPrimary,
                                ),
                              )
                            else
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
                              tv: leanback,
                            ),
                            _Toggle(
                              icon: Icons.download_rounded,
                              active: false,
                              tooltip: l10n.download,
                              onTap: () => _downloadTrack(context, track),
                              tv: leanback,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _Queue(player: player, tv: leanback),
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
  const _PlayButton({required this.player, this.tv = false});

  final MusicPlayerController player;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    final button = Container(
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
    );
    if (tv) {
      // Autofocus the primary action so opening the sheet from the remote
      // lands somewhere useful instead of on a non-focusable backdrop.
      return TvFocusable(
        onTap: player.togglePlayPause,
        autofocus: true,
        variant: TvFocusVariant.float,
        borderRadius: 33,
        semanticLabel: player.playing ? 'Pause' : 'Play',
        child: button,
      );
    }
    return GestureDetector(onTap: player.togglePlayPause, child: button);
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
    this.tv = false,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;
  final bool tv;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(
      icon,
      color: active ? AppColors.accent : AppColors.textTertiary,
    );
    if (tv) {
      return TvFocusable(
        onTap: onTap,
        variant: TvFocusVariant.pill,
        borderRadius: 20,
        semanticLabel: tooltip,
        builder: (_) => glyph,
      );
    }
    return IconButton(onPressed: onTap, tooltip: tooltip, icon: glyph);
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
  const _Queue({required this.player, this.tv = false});

  final MusicPlayerController player;
  final bool tv;

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
          _queueRow(context, i, tracks[i]),
      ],
    );
  }

  Widget _queueRow(BuildContext context, int i, MusicTrack track) {
    final tile = ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: tv ? null : () => player.jumpTo(i),
      leading: MusicArtwork(url: track.artwork, size: 40),
      title: Text(
        track.title,
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
        track.artistLabel(context),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.caption.copyWith(color: AppColors.textTertiary),
      ),
    );
    return tv
        ? TvFocusable(
            onTap: () => player.jumpTo(i),
            variant: TvFocusVariant.row,
            scale: 1.0,
            borderRadius: 10,
            semanticLabel: track.title,
            child: tile,
          )
        : tile;
  }
}

/// Saves the playing track to the app's music folder.
///
/// The source's URL is resolved fresh rather than reused from playback: signed
/// links expire, and a download that starts minutes into a song needs one that
/// has not.
Future<void> _downloadTrack(BuildContext context, MusicTrack track) async {
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.l10n.musicCantPlayBody;
  final done = context.l10n.downloaded;
  try {
    final url = await sl<MusicService>().streamFor(track);
    if (url == null || url.isEmpty) throw StateError('no stream');
    final docs = await getApplicationDocumentsDirectory();
    await MusicDownload(
      sl<Dio>(),
      directory: Directory('${docs.path}/music'),
    ).save(track, url);
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
  }
}
