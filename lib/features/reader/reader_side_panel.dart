import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/models/episode.dart';
import '../../core/reading/chapter_nav.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';

/// The grab handle pinned to the reading edge that slides the [ReaderSidePanel]
/// open. A slim vertical pill so it reads as a pull-tab rather than a button,
/// with the label rotated to run down the edge.
class ReaderPanelTab extends StatelessWidget {
  const ReaderPanelTab({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(14),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(14),
            ),
            border: Border.all(color: AppColors.hairline),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(-2, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(height: 8),
              RotatedBox(
                quarterTurns: 3,
                child: Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Right-edge drawer for the novel reader: the chapter list, quick reading
/// stats and a hands-free (auto-read) toggle, without covering the page with a
/// modal sheet. Wired through the reader's `Scaffold.endDrawer`; the reader
/// opens it with `openEndDrawer()` and this closes it with `Navigator.pop`.
class ReaderSidePanel extends StatefulWidget {
  const ReaderSidePanel({
    super.key,
    required this.showTitle,
    required this.chapters,
    required this.index,
    required this.autoReadOn,
    required this.highlightCount,
    required this.onChapterSelected,
    required this.onAutoReadChanged,
    required this.onOpenTextSize,
    required this.onOpenSettings,
  });

  final String showTitle;
  final List<Episode> chapters;
  final int index;

  /// Live auto-read state. A listenable rather than a bool: auto-read can flip
  /// from outside the panel (touch-pause, end of chapter), and a captured bool
  /// would leave the switch showing the state from when the drawer opened.
  final ValueListenable<bool> autoReadOn;
  final int highlightCount;
  final ValueChanged<int> onChapterSelected;
  final ValueChanged<bool> onAutoReadChanged;
  final VoidCallback onOpenTextSize;
  final VoidCallback onOpenSettings;

  @override
  State<ReaderSidePanel> createState() => _ReaderSidePanelState();
}

class _ReaderSidePanelState extends State<ReaderSidePanel> {
  static const double _rowHeight = 52;
  int _tab = 0;

  late final ScrollController _chapterScroll = ScrollController(
    initialScrollOffset: ((widget.index - 2) * _rowHeight).clamp(
      0,
      double.infinity,
    ),
  );

  @override
  void dispose() {
    _chapterScroll.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Drawer(
      backgroundColor: Colors.transparent,
      elevation: 0,
      width: (width * 0.84).clamp(0, 380),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border(left: BorderSide(color: AppColors.hairline)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              _tabBar(),
              Expanded(
                child: _tab == 0 ? _chapterList() : _stats(),
              ),
              _autoReadRow(),
              _quickActions(),
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.showTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  'Chapter ${chapterNumberLabel(widget.chapters, widget.index)}'
                  ' of ${chapterCountLabel(widget.chapters)}',
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _close,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              0,
              Icons.list_alt_rounded,
              context.l10n.chapters,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _tabButton(1, Icons.insights_rounded, context.l10n.readingStats),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int i, IconData icon, String label) {
    final selected = _tab == i;
    return Material(
      color: selected ? AppColors.accent : AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _tab = i),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: selected ? Colors.white : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chapterList() {
    if (widget.chapters.length < 2) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.noOtherChaptersLoadedYet,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _chapterScroll,
      itemCount: widget.chapters.length,
      itemExtent: _rowHeight,
      itemBuilder: (context, i) {
        final current = i == widget.index;
        final title = widget.chapters[i].title.trim();
        return InkWell(
          onTap: () {
            _close();
            if (i != widget.index) widget.onChapterSelected(i);
          },
          child: Container(
            color: current ? AppColors.accent.withValues(alpha: 0.12) : null,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 46,
                  child: Text(
                    chapterNumberLabel(widget.chapters, i),
                    style: AppText.caption.copyWith(
                      color: current
                          ? AppColors.accent
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title.isNotEmpty
                        ? title
                        : 'Chapter ${chapterNumberLabel(widget.chapters, i)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(
                      color: current ? AppColors.accent : Colors.white,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
                if (current)
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: AppColors.accent,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _stats() {
    final total = widget.chapters.length;
    final done = widget.index + 1;
    final pct = total == 0 ? 0 : ((done / total) * 100).round();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
      children: [
        _statTile(Icons.menu_book_rounded, context.l10n.readingProgress, '$pct%'),
        _statTile(
          Icons.list_alt_rounded,
          context.l10n.chapters,
          '$done / $total',
        ),
        _statTile(
          Icons.bookmark_rounded,
          context.l10n.highlights,
          '${widget.highlightCount}',
        ),
      ],
    );
  }

  Widget _statTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Text(
            value,
            style: AppText.body.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _autoReadRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.autoReadOn,
          builder: (context, on, _) => SwitchListTile.adaptive(
            value: on,
            onChanged: widget.onAutoReadChanged,
            activeThumbColor: AppColors.accent,
            dense: true,
            secondary: const Icon(
              Icons.slow_motion_video_rounded,
              color: Colors.white,
            ),
            title: Text(
              context.l10n.autoRead,
              style: AppText.body.copyWith(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        children: [
          Expanded(
            child: _quickAction(
              Icons.format_size_rounded,
              context.l10n.textSize,
              () {
                _close();
                widget.onOpenTextSize();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _quickAction(
              Icons.tune_rounded,
              context.l10n.readerSettings,
              () {
                _close();
                widget.onOpenSettings();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
