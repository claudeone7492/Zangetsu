import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

import 'sharpen.dart';

/// Applies [Sharpen] to whatever [inner] decodes, at decode time.
///
/// Wrapping the provider rather than post-processing the widget keeps the work
/// off the frame: the page is sharpened once per decode, in the same place the
/// resize already happens, so scrolling and zooming reuse the sharpened image.
/// The cost is a convolution over the decoded page, which is why it is opt-in.
class SharpenImageProvider extends ImageProvider<SharpenImageProvider> {
  const SharpenImageProvider(this.inner, {this.amount = 1.0});

  final ImageProvider inner;
  final double amount;

  @override
  Future<SharpenImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<SharpenImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    SharpenImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      _load(key),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
      ],
    );
  }

  Future<ImageInfo> _load(SharpenImageProvider key) {
    final stream = key.inner.resolve(ImageConfiguration.empty);
    final completer = Completer<ImageInfo>();
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        unawaited(_sharpen(info, completer));
      },
      onError: (error, stack) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Future<void> _sharpen(ImageInfo info, Completer<ImageInfo> out) async {
    final source = info.image;
    try {
      final data = await source.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) {
        out.complete(info);
        return;
      }
      final decoded = img.Image.fromBytes(
        width: source.width,
        height: source.height,
        bytes: data.buffer,
        numChannels: 4,
      );
      final png = img.encodePng(Sharpen.apply(decoded, amount: amount));
      final codec = await ui.instantiateImageCodec(Uint8List.fromList(png));
      final frame = await codec.getNextFrame();
      out.complete(
        ImageInfo(
          image: frame.image,
          scale: info.scale,
          debugLabel: info.debugLabel,
        ),
      );
      info.dispose();
    } catch (_) {
      // An un-sharpenable page still has to draw: hand back the original.
      if (!out.isCompleted) out.complete(info);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is SharpenImageProvider &&
      other.inner == inner &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(inner, amount);

  @override
  String toString() => 'SharpenImageProvider($inner, amount: $amount)';
}
