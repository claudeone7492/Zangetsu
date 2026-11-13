import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/reading/reader_highlights.dart';
import 'package:watch_app/features/reader/reader_selection_menu.dart';
import 'package:watch_app/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late int changed;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('selection_menu_test');
    Hive.init(dir.path);
    await ReaderHighlightStore.init();
    sl.registerSingleton<ReaderHighlightStore>(ReaderHighlightStore());
    changed = 0;
  });

  tearDown(() async {
    await sl.reset();
    await Hive.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// A real [SelectableRegion] wired to the reader's menu builder — the same
  /// long-press → toolbar → highlight path the reader uses, no mocks.
  Widget harness({String selected = 'the chosen passage'}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SelectionArea(
        onSelectionChanged: (v) => _lastSelection = v?.plainText ?? '',
        contextMenuBuilder: (ctx, state) => buildReaderSelectionMenu(
          context: ctx,
          state: state,
          selectedText: _lastSelection,
          sourceId: 's',
          showId: 'b',
          chapterUrl: 'https://x/c1',
          chapterTitle: 'Book',
          onChanged: () => changed++,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(selected, style: const TextStyle(fontSize: 20)),
        ),
      ),
    ),
  );

  Future<void> selectAll(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    // Long-press then drag selects a word and raises the context menu.
    await tester.longPress(find.byType(Text));
    await tester.pumpAndSettle();
  }

  testWidgets('long-press raises the custom menu with Highlight and Copy', (
    tester,
  ) async {
    await selectAll(tester);
    expect(find.text('Highlight'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('Highlight saves the passage and reports the change', (
    tester,
  ) async {
    await selectAll(tester);
    // The tap triggers a real Hive write, which only resolves under runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.text('Highlight'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    final saved = sl<ReaderHighlightStore>().forChapter('https://x/c1');
    expect(saved, hasLength(1));
    expect(saved.single.text, isNotEmpty);
    expect(changed, 1);
  });

  testWidgets('an empty selection falls back to a Copy-only menu', (
    tester,
  ) async {
    // Builder deliberately passes no selection text, as happens when the
    // toolbar is built before a drag has produced any.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SelectionArea(
            contextMenuBuilder: (ctx, state) => buildReaderSelectionMenu(
              context: ctx,
              state: state,
              selectedText: '',
              sourceId: 's',
              showId: 'b',
              chapterUrl: 'https://x/c1',
              chapterTitle: 'Book',
              onChanged: () {},
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Text('some readable text', style: TextStyle(fontSize: 20)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(Text));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Highlight'), findsNothing);
  });
}

String _lastSelection = '';
