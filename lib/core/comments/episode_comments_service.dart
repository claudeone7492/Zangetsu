import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../logging/app_logger.dart';
import '../supabase/supabase_service.dart';
import 'episode_comment.dart';

/// The comments data layer the UI depends on. Split from the concrete
/// [EpisodeCommentsService] so widget tests can substitute an in-memory fake
/// without standing up Supabase.
abstract class EpisodeCommentsApi {
  String? currentUserId();

  Future<List<EpisodeComment>> fetch({
    required String sourceId,
    required String showId,
    required String episodeId,
    int limit,
  });

  Future<EpisodeComment> add({
    required String sourceId,
    required String showId,
    required String episodeId,
    required String body,
    required String displayName,
  });

  Future<EpisodeComment> edit({required String id, required String body});

  Future<void> delete(String id);

  Stream<List<EpisodeComment>> watch({
    required String sourceId,
    required String showId,
    required String episodeId,
  });
}

/// Supabase data layer for episode comments.
///
/// Reads are public (a signed-out viewer still sees the thread); writes are the
/// signed-in user's own rows, enforced by RLS. Live updates ride a Realtime
/// `postgres_changes` subscription filtered by episode id — the callback just
/// refetches, so an insert, edit and delete all reconcile the same way and the
/// client never has to reason about event ordering.
class EpisodeCommentsService implements EpisodeCommentsApi {
  EpisodeCommentsService(this._sb);

  final SupabaseService _sb;

  SupabaseClient get _c => _sb.client;

  static const _table = 'episode_comments';
  static const _pageSize = 100;

  @override
  String? currentUserId() => _sb.currentUserId();

  @override
  Future<List<EpisodeComment>> fetch({
    required String sourceId,
    required String showId,
    required String episodeId,
    int limit = _pageSize,
  }) async {
    final rows = await _c
        .from(_table)
        .select()
        .eq('source_id', sourceId)
        .eq('show_id', showId)
        .eq('episode_id', episodeId)
        .order('created_at', ascending: false)
        .limit(limit);
    return [
      for (final r in (rows as List).cast<Map<String, dynamic>>())
        EpisodeComment.fromRow(r),
    ];
  }

  @override
  Future<EpisodeComment> add({
    required String sourceId,
    required String showId,
    required String episodeId,
    required String body,
    required String displayName,
  }) async {
    final userId = currentUserId();
    if (userId == null) {
      throw StateError('Sign in to comment');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final row = await _c
        .from(_table)
        .insert({
          'user_key': userId,
          'source_id': sourceId,
          'show_id': showId,
          'episode_id': episodeId,
          'display_name': displayName.trim(),
          'body': body.trim(),
          'created_at': now,
          'updated_at': now,
        })
        .select()
        .single();
    return EpisodeComment.fromRow(row);
  }

  @override
  Future<EpisodeComment> edit({
    required String id,
    required String body,
  }) async {
    final row = await _c
        .from(_table)
        .update({
          'body': body.trim(),
          'edited': true,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        })
        .eq('id', id)
        .select()
        .single();
    return EpisodeComment.fromRow(row);
  }

  @override
  Future<void> delete(String id) async {
    await _c.from(_table).delete().eq('id', id);
  }

  /// Emits the episode's thread now and again whenever it changes. The first
  /// event is the current page; every later event is a full refetch triggered
  /// by a Realtime change. Cancelling the subscription closes the channel.
  @override
  Stream<List<EpisodeComment>> watch({
    required String sourceId,
    required String showId,
    required String episodeId,
  }) {
    late StreamController<List<EpisodeComment>> controller;
    RealtimeChannel? channel;
    Timer? debounce;
    var closed = false;

    Future<void> emit() async {
      if (closed) return;
      try {
        final page = await fetch(
          sourceId: sourceId,
          showId: showId,
          episodeId: episodeId,
        );
        if (!closed) controller.add(page);
      } catch (e) {
        if (!closed) controller.addError(e);
      }
    }

    // Coalesce bursts (e.g. several changes landing together) into one fetch.
    void scheduleEmit() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 250), emit);
    }

    controller = StreamController<List<EpisodeComment>>.broadcast(
      onListen: () async {
        unawaited(emit());
        final token = _c.auth.currentSession?.accessToken;
        if (token != null && token.isNotEmpty) {
          unawaited(_c.realtime.setAuth(token));
        }
        channel = _c
            .channel('comments:$episodeId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: _table,
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'episode_id',
                value: episodeId,
              ),
              callback: (_) => scheduleEmit(),
            )
            .subscribe((status, error) {
              if (status == RealtimeSubscribeStatus.channelError) {
                AppLogger.instance.log(
                  'comments: realtime channel error for $episodeId: $error',
                  level: 'W',
                );
              }
            });
      },
      onCancel: () {
        closed = true;
        debounce?.cancel();
        final ch = channel;
        if (ch != null) unawaited(_c.removeChannel(ch));
      },
    );
    return controller.stream;
  }
}
