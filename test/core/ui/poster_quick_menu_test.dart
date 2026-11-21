import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/ui/poster_quick_menu.dart';

void main() {
  Future<List<PosterQuickAction>> pumpMenu(WidgetTester tester) async {
    final picks = <PosterQuickAction>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 300,
              child: PosterQuickMenuArea(
                hold: const Duration(milliseconds: 100),
                onPick: picks.add,
                builder: (context, open) =>
                    ColoredBox(color: open ? Colors.red : Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );
    return picks;
  }

  testWidgets('a quick tap never opens the menu', (tester) async {
    final picks = await pumpMenu(tester);
    await tester.tap(find.byType(PosterQuickMenuArea));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Slide to explore'), findsNothing);
    expect(picks, isEmpty);
  });

  testWidgets('holding opens the discs, sliding picks one', (tester) async {
    final picks = await pumpMenu(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PosterQuickMenuArea)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Slide to explore'), findsOneWidget);

    // Far right of the 200 px cell = the fourth disc (Close).
    await gesture.moveTo(
      tester.getTopLeft(find.byType(PosterQuickMenuArea)) +
          const Offset(190, 150),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(picks, [PosterQuickAction.close]);
    expect(find.text('Slide to explore'), findsNothing);
  });

  testWidgets('moving past the slop before the hold cancels it', (tester) async {
    final picks = await pumpMenu(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PosterQuickMenuArea)),
    );
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Slide to explore'), findsNothing);
    await gesture.up();
    expect(picks, isEmpty);
  });

  testWidgets('the left edge selects Details', (tester) async {
    final picks = await pumpMenu(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PosterQuickMenuArea)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.moveTo(
      tester.getTopLeft(find.byType(PosterQuickMenuArea)) +
          const Offset(10, 150),
    );
    await tester.pump();
    await gesture.up();
    expect(picks, [PosterQuickAction.details]);
  });
}
