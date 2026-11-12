import 'package:equatable/equatable.dart';

/// One comment in an episode's discussion thread.
///
/// Keyed by the episode triple the player already uses ([sourceId], [showId],
/// [episodeId]) plus the row's own [id]. [displayName] is the author's name as
/// copied at insert time (see the migration) — not a live join.
class EpisodeComment extends Equatable {
  const EpisodeComment({
    required this.id,
    required this.userKey,
    required this.sourceId,
    required this.showId,
    required this.episodeId,
    required this.body,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.edited = false,
  });

  final String id;
  final String userKey;
  final String sourceId;
  final String showId;
  final String episodeId;
  final String body;
  final String displayName;
  final bool edited;

  /// Epoch milliseconds.
  final int createdAt;
  final int updatedAt;

  factory EpisodeComment.fromRow(Map<String, dynamic> row) => EpisodeComment(
    id: '${row['id']}',
    userKey: '${row['user_key'] ?? ''}',
    sourceId: '${row['source_id'] ?? ''}',
    showId: '${row['show_id'] ?? ''}',
    episodeId: '${row['episode_id'] ?? ''}',
    body: '${row['body'] ?? ''}',
    displayName: '${row['display_name'] ?? ''}',
    edited: row['edited'] == true,
    createdAt: (row['created_at'] as num?)?.toInt() ?? 0,
    updatedAt: (row['updated_at'] as num?)?.toInt() ?? 0,
  );

  EpisodeComment copyWith({String? body, bool? edited, int? updatedAt}) =>
      EpisodeComment(
        id: id,
        userKey: userKey,
        sourceId: sourceId,
        showId: showId,
        episodeId: episodeId,
        body: body ?? this.body,
        displayName: displayName,
        edited: edited ?? this.edited,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// The name to show for the author — a blank display name (an account with
  /// neither name nor email) falls back to a neutral placeholder rather than
  /// an empty line.
  String get authorLabel => displayName.trim().isEmpty ? 'Viewer' : displayName;

  @override
  List<Object?> get props => [
    id,
    userKey,
    sourceId,
    showId,
    episodeId,
    body,
    displayName,
    edited,
    createdAt,
    updatedAt,
  ];
}
