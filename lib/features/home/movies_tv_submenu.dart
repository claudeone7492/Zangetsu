import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/zmode/metadata_repository.dart';
import '../../core/zmode/movie_regions.dart';
import '../home/cubit/home_cubit.dart';

/// The Movies & TV sub-menu: one chip per [MovieRegion].
///
/// Rendered only while the Movie/TV stream kind is active. Picking a chip
/// swaps the whole movie Home for that regional/category dataset — it writes
/// [MovieRegionPrefs], drops the metadata home cache, and reloads [HomeCubit]
/// — so it "wires the full data set" for the region rather than filtering one
/// row. `All` restores TMDB's own curated rows.
class MoviesTvRegionBar extends StatelessWidget {
  const MoviesTvRegionBar({super.key, this.onSelected});

  /// Optional override for the reload. When null the bar performs the default
  /// swap itself (write pref → clear cache → reload Home). Tests pass a spy to
  /// observe the pick without touching DI.
  final void Function(MovieRegion region)? onSelected;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: MovieRegionPrefs.revision,
      builder: (context, _, _) {
        final selected = MovieRegionPrefs.region;
        return SizedBox(
          key: const ValueKey('movies-tv-submenu'),
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: MovieRegion.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final region = MovieRegion.values[i];
              return _RegionChip(
                key: ValueKey('movies-tv-region-${region.name}'),
                label: region.label,
                selected: region == selected,
                onTap: () => _pick(region),
              );
            },
          ),
        );
      },
    );
  }

  void _pick(MovieRegion region) {
    if (region == MovieRegionPrefs.region) return;
    final override = onSelected;
    if (override != null) {
      override(region);
      return;
    }
    applyRegion(region);
  }

  /// The real swap: write the pick, then drop every cached movie Home (both
  /// [MetadataRepository]'s and [HomeCubit]'s parallel per-kind cache) and
  /// reload, because a region change is a different dataset. Exposed as a
  /// static so it can be driven without a widget tree — the Hive write is real
  /// IO, which does not complete inside `testWidgets`' fake-async zone.
  ///
  /// Every lookup is `isRegistered`-guarded: the bar builds in shells and tests
  /// where the registry isn't up, and a missing cache is a better answer there
  /// than throwing the tap away.
  static Future<void> applyRegion(MovieRegion region) async {
    await MovieRegionPrefs.setRegion(region);
    if (sl.isRegistered<MetadataRepository>()) {
      sl<MetadataRepository>().clearHomeCache();
    }
    if (sl.isRegistered<HomeCubit>()) {
      sl<HomeCubit>().clearStreamKindCache();
      await sl<HomeCubit>().load(reset: true);
    }
  }
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTv = sl.isRegistered<AppMode>() && sl<AppMode>().isTv;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.18)
            : AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? AppColors.accent : Colors.white24,
        ),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(
          color: selected ? AppColors.accent : AppColors.textSecondary,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    if (isTv) {
      return TvFocusable(
        onTap: onTap,
        waitForKeyUp: true,
        borderRadius: 20,
        semanticLabel: label,
        builder: (_) => content,
      );
    }
    return GestureDetector(onTap: onTap, child: content);
  }
}
