// The caption's own gestures and the studio's plate / entrance.
//
// A drag must reach the caller as a fraction of the surface — the caller stores
// it, so the exact fraction is what matters, not the pixels. And the plate and
// the entrance have to be real widgets around the text, because that is the
// difference between the studio's Look page working on the video and working
// only in the preview.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/subtitle_style.dart';
import 'package:watch_app/features/player/subtitle_style_model.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(400, 400),
  }) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox.fromSize(size: size, child: child)),
      ),
    );
  }

  testWidgets('a drag is reported as a fraction of the surface', (tester) async {
    final moves = <Offset>[];
    await pump(
      tester,
      PositionedSubtitle(
        text: 'Line',
        position: 90,
        style: const TextStyle(fontSize: 14),
        onDrag: (dx, dy) => moves.add(Offset(dx, dy)),
      ),
    );
    await tester.drag(find.text('Line'), const Offset(40, -20));
    await tester.pump();
    expect(moves, isNotEmpty);
    final total = moves.fold(Offset.zero, (a, b) => a + b);
    // 40/400 right and 20/400 up.
    expect(total.dx, closeTo(0.1, 0.02));
    expect(total.dy, closeTo(-0.05, 0.02));
  });

  testWidgets('without a gesture handler the caption is inert', (tester) async {
    await pump(
      tester,
      PositionedSubtitle(
        text: 'Line',
        position: 90,
        style: const TextStyle(fontSize: 14),
      ),
    );
    // No handler at all → no GestureDetector, and an IgnorePointer wraps the
    // block so a tap on the text does not reach a layer inside it.
    expect(
      find.descendant(
        of: find.byType(PositionedSubtitle),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );
    expect(
      tester.widget<IgnorePointer>(find.byType(IgnorePointer)).ignoring,
      isTrue,
    );
  });

  testWidgets('a tap on the caption is reported', (tester) async {
    var taps = 0;
    await pump(
      tester,
      PositionedSubtitle(
        text: 'Line',
        position: 90,
        style: const TextStyle(fontSize: 14),
        onTap: () => taps++,
      ),
    );
    await tester.tap(find.text('Line'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a pinch on the caption reports a relative multiplier', (
    tester,
  ) async {
    final factors = <double>[];
    await pump(
      tester,
      PositionedSubtitle(
        text: 'A reasonably long caption line',
        position: 90,
        style: const TextStyle(fontSize: 20),
        onScale: factors.add,
      ),
    );
    final center = tester.getCenter(find.text('A reasonably long caption line'));
    final g1 = await tester.startGesture(center - const Offset(10, 0));
    final g2 = await tester.startGesture(center + const Offset(10, 0));
    await tester.pump();
    await g1.moveTo(center - const Offset(30, 0));
    await g2.moveTo(center + const Offset(30, 0));
    await tester.pump();
    await g1.up();
    await g2.up();
    await tester.pump();
    expect(factors, isNotEmpty);
    expect(factors.reduce((a, b) => a * b), greaterThan(1.0));
  });

  testWidgets('the studio plate wraps the text', (tester) async {
    await pump(
      tester,
      PositionedSubtitle(
        text: 'Line',
        position: 90,
        style: const TextStyle(fontSize: 14),
        studio: const SubtitleStyle(
          plateMode: SubtitlePlateMode.plate,
          platePadding: 10,
        ),
      ),
    );
    final decorations = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox));
    final plate = decorations.where((d) {
      final dec = d.decoration;
      return dec is BoxDecoration && dec.color != null;
    });
    expect(plate, isNotEmpty);
  });

  testWidgets('an entrance animates and then settles on the text', (
    tester,
  ) async {
    await pump(
      tester,
      PositionedSubtitle(
        text: 'Line',
        position: 90,
        style: const TextStyle(fontSize: 14),
        studio: const SubtitleStyle(
          entrance: SubtitleEntrance.riseFade,
          entranceMs: 200,
        ),
      ),
    );
    // Mid-animation the opacity is below one.
    await tester.pump(const Duration(milliseconds: 20));
    final mid = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(mid.opacity, lessThan(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    expect(find.text('Line'), findsOneWidget);
  });

  testWidgets('uppercase is applied on the video, not only in the preview', (
    tester,
  ) async {
    await pump(
      tester,
      PositionedSubtitle(
        text: 'hello',
        position: 90,
        style: const TextStyle(fontSize: 14),
        studio: const SubtitleStyle(uppercase: true),
      ),
    );
    expect(find.text('HELLO'), findsOneWidget);
    expect(find.text('hello'), findsNothing);
  });

  testWidgets('a dragged caption moves to the anchor it is given', (
    tester,
  ) async {
    await pump(
      tester,
      PositionedSubtitle(
        text: 'Line',
        position: 50,
        anchorX: 0,
        style: const TextStyle(fontSize: 14),
      ),
    );
    final frame = tester.getRect(find.byType(PositionedSubtitle));
    final text = tester.getRect(find.text('Line'));
    expect(text.left, closeTo(frame.left + 16, 0.5));
  });
}
