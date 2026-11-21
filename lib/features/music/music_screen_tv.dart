import 'package:flutter/material.dart';

import '../../core/music/music_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';

/// Leanback music home: one D-pad-navigable rail per section.
///
/// Body-only on purpose — `MusicScreen` owns the header, the search field and
/// the mini player, so this replaces just the scrolling rows on TV. Every track
/// card is a [TvFocusable]: a bare `GestureDetector` cannot take remote focus,
/// which is what made the phone rows unusable from a D-pad.
class MusicScreenTv extends StatelessWidget {
  const MusicScreenTv({
    super.key,
    required this.sections,
    required this.onPlay,
    this.onOpenTrack,
  });

  final List<MusicSection> sections;
  final void Function(MusicTrack track, List<MusicTrack> queue) onPlay;
  final void Function(MusicTrack track)? onOpenTrack;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: sections.length,
      itemBuilder: (context, index) {
        final section = sections[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Text(section.title, style: AppText.title),
            ),
            SizedBox(
              height: 216,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: section.tracks.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (context, i) {
                  final track = section.tracks[i];
                  return _TvTrackTile(
                    track: track,
                    onSelect: () => onPlay(track, section.tracks),
                    onLongSelect: onOpenTrack == null
                        ? null
                        : () => onOpenTrack!(track),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TvTrackTile extends StatelessWidget {
  const _TvTrackTile({
    required this.track,
    required this.onSelect,
    this.onLongSelect,
  });

  final MusicTrack track;
  final VoidCallback onSelect;
  final VoidCallback? onLongSelect;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      variant: TvFocusVariant.float,
      borderRadius: 12,
      onTap: onSelect,
      onLongPress: onLongSelect,
      semanticLabel: track.title,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: track.artwork == null
                    ? ColoredBox(color: AppColors.surface)
                    : Image.network(
                        track.artwork!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body,
            ),
            Text(
              track.artist ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}
