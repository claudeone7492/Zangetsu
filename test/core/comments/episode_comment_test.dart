import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/comments/episode_comment.dart';

void main() {
  test('fromRow maps every column and tolerates missing ones', () {
    final c = EpisodeComment.fromRow({
      'id': 'abc',
      'user_key': 'u1',
      'source_id': 's',
      'show_id': 'sh',
      'episode_id': 'e1',
      'body': 'hello',
      'display_name': 'Krishna',
      'edited': true,
      'created_at': 100,
      'updated_at': 200,
    });
    expect(c.id, 'abc');
    expect(c.userKey, 'u1');
    expect(c.sourceId, 's');
    expect(c.showId, 'sh');
    expect(c.episodeId, 'e1');
    expect(c.body, 'hello');
    expect(c.displayName, 'Krishna');
    expect(c.edited, isTrue);
    expect(c.createdAt, 100);
    expect(c.updatedAt, 200);
  });

  test('fromRow defaults a sparse row without throwing', () {
    final c = EpisodeComment.fromRow({'id': 7});
    expect(c.id, '7');
    expect(c.body, '');
    expect(c.edited, isFalse);
    expect(c.createdAt, 0);
  });

  test('authorLabel falls back to a placeholder for a blank name', () {
    final blank = EpisodeComment.fromRow({'id': '1', 'display_name': '   '});
    expect(blank.authorLabel, 'Viewer');
    final named = EpisodeComment.fromRow({'id': '1', 'display_name': 'Ana'});
    expect(named.authorLabel, 'Ana');
  });

  test('copyWith edits only the mutable fields', () {
    final c = EpisodeComment.fromRow({
      'id': '1',
      'user_key': 'u',
      'body': 'old',
      'created_at': 5,
    });
    final edited = c.copyWith(body: 'new', edited: true, updatedAt: 9);
    expect(edited.body, 'new');
    expect(edited.edited, isTrue);
    expect(edited.updatedAt, 9);
    expect(edited.createdAt, 5);
    expect(edited.userKey, 'u');
  });
}
