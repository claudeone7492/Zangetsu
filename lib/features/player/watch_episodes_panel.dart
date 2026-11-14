import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/frosted_surface.dart';
import '../../l10n/l10n.dart';
import 'watch_page_info.dart';
import 'watch_page_motion.dart';

/// The left-edge episode drawer for the portrait watch page.
///
/// The list under the video already IS the picker, but on a long title the one
/// episode you want can be a thousand swipes down. This is the shortcut: a
/// frosted panel that slides in from the left with every episode as a compact
/// number grid, so a tap reaches any episode without leaving the page. The
/// playing one is ringed, finished ones are dimmed, and unavailable ones are
/// inert — the same signals the rows carry, in the space a grid allows.
class WatchEpisodesPanel extends StatelessWidget {
  const WatchEpisodesPanel({
    super.key,
    required this.episodes,
    required this.onSelect,
    required this.onClose,
  });

  final List<WatchPageEpisode> episodes;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    // A narrow phone shouldn't lose the video entirely behind the panel, and a
    // tablet shouldn't stretch the grid to a wall of one-per-row tiles.
    final panelW = (w * 0.72).clamp(220.0, 340.0);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FrostedSurface(
        blur: true,
        opacity: 0.9,
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
        child: SizedBox(
          width: panelW,
          height: double.infinity,
          child: SafeArea(
            right: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.episodes,
                          style: AppText.title.copyWith(fontSize: 17),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                        ),
                        tooltip: context.l10n.close,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1,
                        ),
                    itemCount: episodes.length,
                    itemBuilder: (context, i) =>
                        _tile(context, episodes[i]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, WatchPageEpisode ep) {
    final dead = (ep.unavailableReason ?? '').trim().isNotEmpty;
    final label = ep.number != null
        ? '${ep.number!.toInt()}'
        : '${ep.index + 1}';
    final tile = AnimatedContainer(
      duration: watchPageMotionEnabled(context)
          ? const Duration(milliseconds: 180)
          : Duration.zero,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: ep.current
            ? AppColors.accent.withValues(alpha: 0.16)
            : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: ep.current ? Border.all(color: AppColors.accent) : null,
      ),
      alignment: Alignment.center,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          splashColor: AppColors.accentSoft,
          onTap: dead ? null : () => onSelect(ep.index),
          child: Center(
            child: Text(
              label,
              style: AppText.body.copyWith(
                color: dead
                    ? AppColors.textTertiary
                    : ep.current
                    ? AppColors.accent
                    : ep.watched
                    ? AppColors.textSecondary
                    : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
    return dead ? Opacity(opacity: 0.55, child: tile) : tile;
  }
}
