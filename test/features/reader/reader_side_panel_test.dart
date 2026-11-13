import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/models/episode.dart';
import 'package:watch_app/features/reader/reader_side_panel.dart';
import 'package:watch_app/l10n/app_localizations.dart';

Episode _chapter(String url, String title, double number) =>
    Episode(id: title, title: title, url: url, number: number);

void main() {
  Widget harness({
    required int index,
    ValueNotifier<bool>? autoRead,
    ValueChanged<int>? onChapterSelected,
    int highlightCount = 0,
  }) {
    final notifier = autoRead ?? ValueNotifier<bool>(false);
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        endDrawer: ReaderSidePanel(
          showTitle: 'My Book',
          chapters: [
            _chapter('u1', 'The First', 1),
            _chapter('u2', 'The Second', 2),
            _chapter('u3', 'The Third', 3),
          ],
          index: index,
          autoReadOn: notifier,
          highlightCount: highlightCount,
          onChapterSelected: onChapterSelected ?? (_) {},
          onAutoReadChanged: (_) {},
          onOpenTextSize: () {},
          onOpenSettings: () {},
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester, Widget widget) async {
    await tester.pumpWidget(widget);
    final state = tester.state<ScaffoldState>(find.byType(Scaffold));
    state.openEndDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('lists every chapter and marks the current one', (tester) async {
    await open(tester, harness(index: 1));
    expect(find.text('The First'), findsOneWidget);
    expect(find.text('The Second'), findsOneWidget);
    expect(find.text('The Third'), findsOneWidget);
    expect(find.textContaining('Chapter 2 of 3'), findsOneWidget);
    // The current row carries the play marker.
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('tapping another chapter reports its index', (tester) async {
    int? picked;
    await open(tester, harness(index: 0, onChapterSelected: (i) => picked = i));
    await tester.tap(find.text('The Third'));
    await tester.pumpAndSettle();
    expect(picked, 2);
  });

  testWidgets('the auto-read switch reflects the live notifier', (
    tester,
  ) async {
    final autoRead = ValueNotifier<bool>(false);
    await open(tester, harness(index: 0, autoRead: autoRead));
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    autoRead.value = true;
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('the stats tab shows progress, chapter count and highlights', (
    tester,
  ) async {
    await open(tester, harness(index: 1, highlightCount: 4));
    await tester.tap(find.text('Reading stats'));
    await tester.pumpAndSettle();
    expect(find.text('67%'), findsOneWidget); // 2 of 3
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('4'), findsOneWidget);
  });
}
