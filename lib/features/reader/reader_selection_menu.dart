import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/di/injector.dart';
import '../../core/reading/reader_highlights.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';

/// Builds the menu the reader shows over a text selection.
///
/// Plain readers only offer Copy; here the menu also saves the passage as a
/// highlight (the same store the reader paints back onto the chapter) and, once
/// saved, lets you recolour or remove it. Kept as one function so both readers
/// wire the identical menu through [SelectableRegion]'s `contextMenuBuilder`.
///
/// The selected text comes in from the reader's `onSelectionChanged` callback
/// rather than being read off [state] — `SelectableRegionState` exposes no
/// public accessor for it in this Flutter version, and the callback fires
/// before the toolbar is built.
///
/// A no-op selection (the toolbar can be asked to build before a drag has
/// produced any text) falls back to a Copy-only menu rather than an empty one,
/// which would read as a broken toolbar.
Widget buildReaderSelectionMenu({
  required BuildContext context,
  required SelectableRegionState state,
  required String selectedText,
  required String sourceId,
  required String showId,
  required String chapterUrl,
  required String chapterTitle,
  required VoidCallback onChanged,
}) {
  final text = normalizeHighlightText(selectedText);
  final anchors = state.contextMenuAnchors;

  if (text.isEmpty) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: anchors,
      buttonItems: [
        ContextMenuButtonItem(
          onPressed: () => state.hideToolbar(),
          label: MaterialLocalizations.of(context).copyButtonLabel,
        ),
      ],
    );
  }

  return AdaptiveTextSelectionToolbar(
    anchors: anchors,
    children: [
      _SelectionMenuSurface(
        text: text,
        sourceId: sourceId,
        showId: showId,
        chapterUrl: chapterUrl,
        chapterTitle: chapterTitle,
        onChanged: onChanged,
        onDismiss: () => state.hideToolbar(),
      ),
    ],
  );
}

class _SelectionMenuSurface extends StatefulWidget {
  const _SelectionMenuSurface({
    required this.text,
    required this.sourceId,
    required this.showId,
    required this.chapterUrl,
    required this.chapterTitle,
    required this.onChanged,
    required this.onDismiss,
  });

  final String text;
  final String sourceId;
  final String showId;
  final String chapterUrl;
  final String chapterTitle;
  final VoidCallback onChanged;
  final VoidCallback onDismiss;

  @override
  State<_SelectionMenuSurface> createState() => _SelectionMenuSurfaceState();
}

class _SelectionMenuSurfaceState extends State<_SelectionMenuSurface> {
  ReaderHighlightStore get _store => sl<ReaderHighlightStore>();

  String get _id => ReaderHighlightStore.idFor(widget.chapterUrl, widget.text);

  ReaderHighlight? get _saved => _store.byId(_id);

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    widget.onDismiss();
  }

  Future<void> _toggle() async {
    await _store.toggle(
      sourceId: widget.sourceId,
      showId: widget.showId,
      chapterUrl: widget.chapterUrl,
      chapterTitle: widget.chapterTitle,
      text: widget.text,
      colorValue: HighlightColors.all.first,
    );
    widget.onChanged();
    widget.onDismiss();
  }

  Future<void> _remove() async {
    await _store.remove(_id);
    widget.onChanged();
    widget.onDismiss();
  }

  Future<void> _recolor(int color) async {
    await _store.update(_id, colorValue: color);
    widget.onChanged();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved;
    final radius = BorderRadius.circular(18);
    return Material(
      color: AppColors.surface2,
      borderRadius: radius,
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _action(Icons.copy_rounded, context.l10n.copy, _copy),
            if (saved == null)
              _action(
                Icons.brush_rounded,
                context.l10n.highlight,
                _toggle,
              )
            else ...[
              const _MenuDivider(),
              for (final c in HighlightColors.all)
                _swatch(c, saved.colorValue == c),
              const _MenuDivider(),
              _action(Icons.delete_outline_rounded, context.l10n.remove, _remove),
            ],
          ],
        ),
      ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 6),
          Text(label, style: AppText.caption.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _swatch(int color, bool selected) {
    return InkWell(
      onTap: () => _recolor(color),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: AppColors.hairline,
  );
}
