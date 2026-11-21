import 'package:image/image.dart' as img;

/// Unsharp-mask style sharpening for reader pages.
///
/// Hikari's `SharpenTransformation.kt` runs a 3×3 kernel before the page is
/// shown. This is the same kernel over `package:image`, applied only when the
/// reader toggle is on.
class Sharpen {
  const Sharpen._();

  static const List<num> _kernel = [0, -1, 0, -1, 5, -1, 0, -1, 0];

  static img.Image apply(img.Image source, {double amount = 1.0}) {
    if (amount <= 0) return source;
    return img.convolution(source, filter: _kernel, div: 1);
  }
}
