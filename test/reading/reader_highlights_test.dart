import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/reading/reader_highlights.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp();
    Hive.init(dir.path);
    await ReaderHighlightStore.init();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('toggle', () {
    test('adds then removes the same passage', () async {
      final store = ReaderHighlightStore();
      final first = await store.toggle(
        sourceId: 's',
        showId: 'b',
        chapterUrl: 'https://x/c1',
        chapterTitle: 'Book',
        text: 'a memorable line',
        colorValue: HighlightColors.all.first,
      );
      expect(first, isNotNull);
      expect(store.forChapter('https://x/c1'), hasLength(1));

      final second = await store.toggle(
        sourceId: 's',
        showId: 'b',
        chapterUrl: 'https://x/c1',
        chapterTitle: 'Book',
        text: 'a memorable line',
        colorValue: HighlightColors.all.first,
      );
      expect(second, isNull);
      expect(store.forChapter('https://x/c1'), isEmpty);
    });

    test('same text in a different chapter is a distinct highlight', () async {
      final store = ReaderHighlightStore();
      for (final url in ['https://x/c1', 'https://x/c2']) {
        await store.toggle(
          sourceId: 's',
          showId: 'b',
          chapterUrl: url,
          chapterTitle: 'Book',
          text: 'shared line',
          colorValue: HighlightColors.all.first,
        );
      }
      expect(store.forChapter('https://x/c1'), hasLength(1));
      expect(store.forChapter('https://x/c2'), hasLength(1));
      expect(store.all(), hasLength(2));
    });
  });

  test('update recolours without changing identity', () async {
    final store = ReaderHighlightStore();
    final h = await store.toggle(
      sourceId: 's',
      showId: 'b',
      chapterUrl: 'https://x/c1',
      chapterTitle: 'Book',
      text: 'line',
      colorValue: HighlightColors.all.first,
    );
    await store.update(h!.id, colorValue: HighlightColors.all.last);
    expect(store.byId(h.id)!.colorValue, HighlightColors.all.last);
  });

  test('survives a close/reopen of the box', () async {
    final store = ReaderHighlightStore();
    await store.toggle(
      sourceId: 's',
      showId: 'b',
      chapterUrl: 'https://x/c1',
      chapterTitle: 'Book',
      text: 'persisted line',
      colorValue: HighlightColors.all.first,
    );
    await Hive.box(ReaderHighlightStore.boxName).close();
    await ReaderHighlightStore.init();
    expect(
      ReaderHighlightStore().forChapter('https://x/c1').single.text,
      'persisted line',
    );
  });

  group('applyHighlightsToHtml', () {
    test('wraps the passage in a background-coloured span', () {
      final h = _highlight('hello world', 0xFFFFD54F);
      final out = applyHighlightsToHtml('<p>well hello world ok</p>', [h]);
      expect(out, contains('background-color:#ffd54f;'));
      expect(out, contains('>hello world</span>'));
      // The surrounding text is untouched.
      expect(out, contains('<p>well '));
    });

    test('escapes a passage containing html characters before matching', () {
      final h = _highlight('a & b', 0xFF81C784);
      final out = applyHighlightsToHtml('<p>x a &amp; b y</p>', [h]);
      expect(out, contains('>a &amp; b</span>'));
    });

    test('is a no-op with no highlights', () {
      const html = '<p>unchanged</p>';
      expect(applyHighlightsToHtml(html, const []), html);
    });

    test('matches a passage across the HTML\'s own whitespace', () {
      // The selection was normalised to single spaces, but the source HTML
      // wraps the same sentence over a newline and indentation.
      final h = _highlight('hello there world', 0xFF64B5F6);
      final out = applyHighlightsToHtml(
        '<p>hello\n   there\tworld</p>',
        [h],
      );
      expect(out, contains('<span style="background-color:#64b5f6;">'));
      expect(out, contains('hello\n   there\tworld</span>'));
    });
  });

  group('applyHighlightsToSpans', () {
    test('splits a span and colours only the matched run', () {
      final h = _highlight('middle', 0xFF64B5F6);
      final spans = applyHighlightsToSpans(
        const [TextSpan(text: 'start middle end')],
        [h],
      );
      expect(spans, hasLength(3));
      expect((spans[0] as TextSpan).text, 'start ');
      expect((spans[1] as TextSpan).text, 'middle');
      expect((spans[1] as TextSpan).style!.backgroundColor, const Color(0xFF64B5F6));
      expect((spans[2] as TextSpan).text, ' end');
    });

    test('leaves spans untouched when nothing matches', () {
      final h = _highlight('absent', 0xFF64B5F6);
      final spans = applyHighlightsToSpans(
        const [TextSpan(text: 'only this')],
        [h],
      );
      expect(spans, hasLength(1));
      expect((spans.single as TextSpan).text, 'only this');
      expect((spans.single as TextSpan).style?.backgroundColor, isNull);
    });
  });

  test('normalizeHighlightText collapses whitespace', () {
    expect(normalizeHighlightText('  a\n  b\tc '), 'a b c');
  });
}

ReaderHighlight _highlight(String text, int color) => ReaderHighlight(
  id: ReaderHighlightStore.idFor('https://x/c1', text),
  sourceId: 's',
  showId: 'b',
  chapterUrl: 'https://x/c1',
  chapterTitle: 'Book',
  text: text,
  colorValue: color,
  createdAt: DateTime(2026, 1, 1),
);
