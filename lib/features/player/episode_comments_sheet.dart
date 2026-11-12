import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/comments/episode_comment.dart';
import '../../core/comments/episode_comments_service.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../l10n/l10n.dart';
import '../auth/auth_cubit.dart';

/// Opens the episode's comment thread as a modal sheet.
///
/// [showId] is the same stable show identifier the download icon uses, so a
/// thread is keyed identically whether it is opened from a stream or a
/// download.
Future<void> showEpisodeCommentsSheet(
  BuildContext context, {
  required String sourceId,
  required String showId,
  required String episodeId,
  String? episodeLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => EpisodeCommentsSheet(
      sourceId: sourceId,
      showId: showId,
      episodeId: episodeId,
      episodeLabel: episodeLabel,
    ),
  );
}

class EpisodeCommentsSheet extends StatefulWidget {
  const EpisodeCommentsSheet({
    super.key,
    required this.sourceId,
    required this.showId,
    required this.episodeId,
    this.episodeLabel,
    this.service,
  });

  final String sourceId;
  final String showId;
  final String episodeId;

  /// Optional "Episode N · title" line under the header.
  final String? episodeLabel;

  /// Overrides the DI-resolved service — used by tests.
  final EpisodeCommentsApi? service;

  @override
  State<EpisodeCommentsSheet> createState() => _EpisodeCommentsSheetState();
}

class _EpisodeCommentsSheetState extends State<EpisodeCommentsSheet> {
  late final EpisodeCommentsApi _service =
      widget.service ?? sl<EpisodeCommentsService>();
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  StreamSubscription<List<EpisodeComment>>? _sub;
  List<EpisodeComment> _comments = const [];
  bool _loading = true;
  Object? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _sub = _service
        .watch(
          sourceId: widget.sourceId,
          showId: widget.showId,
          episodeId: widget.episodeId,
        )
        .listen(
          (page) {
            if (!mounted) return;
            setState(() {
              _comments = _merge(page, _comments);
              _loading = false;
              _error = null;
            });
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              // Keep whatever we already showed; only surface the error when
              // there is nothing to display yet.
              if (_comments.isEmpty) _error = e;
              _loading = false;
            });
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Newest-first, de-duplicated by id. A locally-posted comment that the
  /// server page also carries collapses to one row; a locally-deleted one
  /// (absent from the page) is dropped so the optimistic removal sticks.
  List<EpisodeComment> _merge(
    List<EpisodeComment> incoming,
    List<EpisodeComment> local,
  ) {
    final byId = {for (final c in incoming) c.id: c};
    // Only carry local rows that the server page does not know about yet
    // (a just-posted insert racing the realtime event).
    for (final c in local) {
      byId.putIfAbsent(c.id, () => c);
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return merged;
  }

  bool get _signedIn => _service.currentUserId() != null;

  Future<void> _post() async {
    final body = _composer.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final name = sl.isRegistered<AuthCubit>()
          ? sl<AuthCubit>().state.displayName
          : '';
      final created = await _service.add(
        sourceId: widget.sourceId,
        showId: widget.showId,
        episodeId: widget.episodeId,
        body: body,
        displayName: name,
      );
      if (!mounted) return;
      setState(() {
        _comments = _merge(_comments, [created]);
        _composer.clear();
      });
      _scrollToTop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.commentsPostFailed)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _edit(EpisodeComment c) async {
    final controller = TextEditingController(text: c.body);
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(ctx.l10n.watchComments, style: AppText.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 2,
          maxLength: 1000,
          style: AppText.body,
          decoration: InputDecoration(hintText: ctx.l10n.commentsPlaceholder),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(ctx.l10n.save),
          ),
        ],
      ),
    );
    controller.dispose();
    if (edited == null || edited.isEmpty || edited == c.body) return;
    try {
      final updated = await _service.edit(id: c.id, body: edited);
      if (!mounted) return;
      setState(() {
        _comments = [
          for (final e in _comments) if (e.id == c.id) updated else e,
        ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.commentsPostFailed)));
      }
    }
  }

  Future<void> _delete(EpisodeComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        content: Text(ctx.l10n.commentsDeleteConfirm, style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.commentsDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _comments = [
      for (final e in _comments)
        if (e.id != c.id) e,
    ]);
    try {
      await _service.delete(c.id);
    } catch (_) {
      // The stream will re-add it on the next page if the delete failed.
    }
  }

  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _grabber(),
                _header(l10n),
                const Divider(color: AppColors.hairline, height: 1),
                Flexible(child: _body(l10n)),
                const Divider(color: AppColors.hairline, height: 1),
                _composerBar(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _grabber() => Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 4),
    child: Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(2),
        ),
        child: const SizedBox(width: 36, height: 4),
      ),
    ),
  );

  Widget _header(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 8, 10),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.watchComments, style: AppText.headline),
              if ((widget.episodeLabel ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    widget.episodeLabel!,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  Widget _body(AppLocalizations l10n) {
    if (_loading && _comments.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null && _comments.isEmpty) {
      return _emptyState(
        l10n.commentsLoadFailed,
        action: TextButton(
          onPressed: () => setState(() {
            _loading = true;
            _error = null;
            _sub?.cancel();
            _sub = _service
                .watch(
                  sourceId: widget.sourceId,
                  showId: widget.showId,
                  episodeId: widget.episodeId,
                )
                .listen((page) {
                  if (!mounted) return;
                  setState(() {
                    _comments = _merge(page, _comments);
                    _loading = false;
                  });
                }, onError: (Object e) {
                  if (!mounted) return;
                  setState(() {
                    if (_comments.isEmpty) _error = e;
                    _loading = false;
                  });
                });
          }),
          child: Text(l10n.retry),
        ),
      );
    }
    if (_comments.isEmpty) {
      return _emptyState(l10n.commentsEmpty);
    }
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _comments.length,
      itemBuilder: (_, i) {
        final c = _comments[i];
        return _CommentTile(
          comment: c,
          mine: c.userKey == _service.currentUserId(),
          onEdit: () => _edit(c),
          onDelete: () => _delete(c),
        );
      },
    );
  }

  Widget _emptyState(String message, {Widget? action}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.chat_bubble_outline_rounded,
          color: AppColors.textTertiary,
          size: 30,
        ),
        const SizedBox(height: 12),
        Text(
          message,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        if (action != null) ...[const SizedBox(height: 4), action],
      ],
    ),
  );

  Widget _composerBar(AppLocalizations l10n) {
    if (!_signedIn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.commentsSignInToComment,
                style: AppText.body.copyWith(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _composer,
              style: AppText.body,
              minLines: 1,
              maxLines: 4,
              maxLength: 1000,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _post(),
              decoration: InputDecoration(
                counterText: '',
                hintText: l10n.commentsPlaceholder,
                hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.send_rounded, color: AppColors.accent),
                  onPressed: _post,
                ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.mine,
    required this.onEdit,
    required this.onDelete,
  });

  final EpisodeComment comment;
  final bool mine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final initial = comment.authorLabel.characters.first.toUpperCase();
    return InkWell(
      onTap: mine ? onEdit : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.accentSoft,
              child: Text(
                initial,
                style: AppText.body.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          mine ? l10n.commentsYou : comment.authorLabel,
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _relativeTime(context, comment.createdAt),
                        style: AppText.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      if (comment.edited) ...[
                        const SizedBox(width: 6),
                        Text(
                          '· ${l10n.commentsEdited}',
                          style: AppText.caption.copyWith(
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(comment.body, style: AppText.body),
                ],
              ),
            ),
            if (mine)
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                splashRadius: 18,
                tooltip: l10n.commentsDelete,
                onPressed: onDelete,
              )
            else
              const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  static String _relativeTime(BuildContext context, int epochMs) {
    final l10n = context.l10n;
    final then = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = DateTime.now().difference(then);
    if (diff.inMinutes < 1) return l10n.commentsJustNow;
    if (diff.inMinutes < 60) return l10n.commentsMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.commentsHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.commentsDaysAgo(diff.inDays);
    return MaterialLocalizations.of(
      context,
    ).formatMediumDate(then);
  }
}
