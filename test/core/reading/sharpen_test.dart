import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:watch_app/core/reading/sharpen.dart';

void main() {
  test('keeps the page size', () {
    final source = img.Image(width: 5, height: 5);
    img.fill(source, color: img.ColorRgb8(120, 120, 120));
    source.setPixelRgb(2, 2, 255, 255, 255);
    final out = Sharpen.apply(source);
    expect(out.width, 5);
    expect(out.height, 5);
  });

  test('amount zero is a no-op', () {
    final source = img.Image(width: 2, height: 2);
    expect(identical(Sharpen.apply(source, amount: 0), source), isTrue);
  });
}
