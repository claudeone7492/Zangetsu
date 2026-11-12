import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/comments/episode_comment.dart';
import 'package:watch_app/core/comments/episode_comments_service.dart';
import 'package:watch_app/features/player/episode_comments_sheet.dart';

/// In-memory [EpisodeCommentsApi]: the real service's observable contract
/// (public read, newest-first, own-row writes) without Supabase. A broadcast
/// controller lets a test push a fresh page to simulate a realtime refetch.
class _FakeComments implements EpisodeCommentsApi {
  _FakeComments({this.userId = 'me'});

  final String? userId;
  final List<EpisodeComment> store = [];
  final _pages = StreamController<List<EpisodeComment>>.broadcast();
  bool deleted = false;
  bool added = false;

  int _seq = 0;

  List<EpisodeComment> get _sorted =>
      [...store]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  void push() => _pages.add(_sorted);

  @override
  String? currentUserId() => userId;

  @override
  Future<List<EpisodeComment>> fetch({
    required String sourceId,
    required String showId,
    required String episodeId,
    int limit = 100,
  }) async => _sorted;

  @override
  Future<EpisodeComment> add({
    required String sourceId,
    required String showId,
    required String episodeId,
    required String body,
    required String displayName,
  }) async {
    added = true;
    final c = EpisodeComment(
      id: 'local-${_seq++}',
      userKey: userId ?? '',
      sourceId: sourceId,
      showId: showId,
      episodeId: episodeId,
      body: body,
      displayName: displayName,
      createdAt: 1000 + _seq,
      updatedAt: 1000 + _seq,
    );
    store.add(c);
    return c;
  }

  @override
  Future<EpisodeComment> edit({required String id, required String body}) async {
    final i = store.indexWhere((c) => c.id == id);
    final updated = store[i].copyWith(body: body, edited: true, updatedAt: 9999);
    store[i] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleted = true;
    store.removeWhere((c) => c.id == id);
  }

  @override
  Stream<List<EpisodeComment>> watch({
    required String sourceId,
    required String showId,
    required String episodeId,
  }) {
    // Emit the current page once, then follow later pushes.
    scheduleMicrotask(push);
    return _pages.stream;
  }
}

EpisodeComment _c(String id, String body, {String user = 'other', int at = 1}) =>
    EpisodeComment(
      id: id,
      userKey: user,
      sourceId: 's',
      showId: 'sh',
      episodeId: 'e1',
      body: body,
      displayName: user == 'me' ? 'Me' : 'Ana',
      createdAt: at,
      updatedAt: at,
    );

Future<void> _pump(WidgetTester tester, _FakeComments fake) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: EpisodeCommentsSheet(
          sourceId: 's',
          showId: 'sh',
          episodeId: 'e1',
          episodeLabel: 'Episode 3',
          service: fake,
        ),
      ),
    ),
  );
  await tester.pump(); // let the initial page land
  await tester.pump();
}

void main() {
  testWidgets('renders the thread newest-first with author names', (
    tester,
  ) async {
    final fake = _FakeComments()
      ..store.addAll([
        _c('a', 'first', at: 1),
        _c('b', 'second', at: 2),
      ]);
    await _pump(tester, fake);

    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsOneWidget);
    // Newest ("second") is above "first".
    final secondY = tester.getTopLeft(find.text('second')).dy;
    final firstY = tester.getTopLeft(find.text('first')).dy;
    expect(secondY, lessThan(firstY));
  });

  testWidgets('empty thread shows the empty state', (tester) async {
    final fake = _FakeComments();
    await _pump(tester, fake);
    expect(find.textContaining('No comments yet'), findsOneWidget);
  });

  testWidgets('signed-out viewer sees a sign-in prompt, not a composer', (
    tester,
  ) async {
    final fake = _FakeComments(userId: null);
    await _pump(tester, fake);
    expect(find.textContaining('Sign in'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('posting clears the field and prepends the new comment', (
    tester,
  ) async {
    final fake = _FakeComments();
    await _pump(tester, fake);

    await tester.enterText(find.byType(TextField), 'nice episode');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(fake.added, isTrue);
    expect(find.text('nice episode'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '');
  });

  testWidgets('own comment exposes a delete action; others do not', (
    tester,
  ) async {
    final fake = _FakeComments()
      ..store.addAll([_c('mine', 'hello', user: 'me'), _c('theirs', 'hi')]);
    await _pump(tester, fake);

    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
  });

  testWidgets('deleting removes the row after confirmation', (tester) async {
    final fake = _FakeComments()..store.add(_c('mine', 'bye', user: 'me'));
    await _pump(tester, fake);

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete comment'));
    await tester.pumpAndSettle();

    expect(fake.deleted, isTrue);
    expect(find.text('bye'), findsNothing);
  });
}
