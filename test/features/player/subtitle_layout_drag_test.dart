// Guards dragging the caption.
//
// A drag writes the caption's anchor, which is also the control the studio's
// position sliders write, so the two must agree. The bounds matter as much as
// the movement, and the bound is the screen itself: a caption has to be
// draggable to every edge, and it is the renderer keeping the *block* inside the
// frame that stops a drag pushing half a line off the picture — not a bound on
// the anchor. An earlier model bounded the anchor well inside the frame as well,
// which put a band around the edges that a drag could not enter.

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/subtitle_layout.dart';

void main() {
  const layout = SubtitleLayout();

  test('a drag moves the anchor by the same fraction', () {
    final moved = layout.dragged(dxFraction: 0.1, dyFraction: -0.05);
    expect(moved.anchorX, closeTo(layout.anchorX + 0.1, 0.0001));
    expect(moved.anchorY, closeTo(layout.anchorY - 0.05, 0.0001));
  });

  test('a drag to the right reaches the right edge', () {
    expect(layout.dragged(dxFraction: 5, dyFraction: 0).anchorX, 1.0);
  });

  test('a drag to the left reaches the left edge', () {
    expect(layout.dragged(dxFraction: -5, dyFraction: 0).anchorX, 0.0);
  });

  test('a drag downwards reaches the bottom edge', () {
    expect(layout.dragged(dxFraction: 0, dyFraction: 5).anchorY, 1.0);
  });

  test('a drag upwards reaches the top edge', () {
    expect(layout.dragged(dxFraction: 0, dyFraction: -5).anchorY, 0.0);
  });

  test('an absolute move lands exactly on the requested anchor', () {
    final moved = layout.movedTo(anchorX: 0.42, anchorY: 0.55);
    expect(moved.anchorX, closeTo(0.42, 0.0001));
    expect(moved.anchorY, closeTo(0.55, 0.0001));
  });

  test('an absolute move is bounded by the screen and nothing else', () {
    final moved = layout.movedTo(anchorX: 5, anchorY: -5);
    expect(moved.anchorX, 1.0);
    expect(moved.anchorY, 0.0);
  });

  test('every corner of the screen is reachable', () {
    final topLeft = layout.movedTo(anchorX: 0, anchorY: 0);
    expect(topLeft.anchorX, 0.0);
    expect(topLeft.anchorY, 0.0);
    final bottomRight = layout.movedTo(anchorX: 1, anchorY: 1);
    expect(bottomRight.anchorX, 1.0);
    expect(bottomRight.anchorY, 1.0);
  });

  test('a zero drag changes nothing', () {
    expect(layout.dragged(dxFraction: 0, dyFraction: 0), layout);
  });
}
