import 'package:flutter/foundation.dart';

/// An 8-bit, single-channel alpha mask: the output currency of every
/// [SegmentationEngine]. Each byte in [alpha] is the foreground coverage of one
/// pixel, `0` (fully background / transparent) … `255` (fully foreground /
/// opaque), stored row-major (`y * width + x`).
///
/// Masks are immutable; post-processing steps return new instances.
@immutable
class AlphaMask {
  const AlphaMask({
    required this.width,
    required this.height,
    required this.alpha,
  }) : assert(width > 0 && height > 0, 'mask dimensions must be positive'),
       assert(
         alpha.length == width * height,
         'alpha length ${alpha.length} != $width*$height',
       );

  /// A mask with every pixel set to [value] (clamped to 0…255).
  factory AlphaMask.filled(int width, int height, int value) {
    final v = value.clamp(0, 255);
    return AlphaMask(
      width: width,
      height: height,
      alpha: Uint8List(width * height)..fillRange(0, width * height, v),
    );
  }

  /// A fully-transparent (all-background) mask.
  factory AlphaMask.empty(int width, int height) =>
      AlphaMask.filled(width, height, 0);

  final int width;
  final int height;

  /// Row-major coverage bytes, length `width * height`.
  final Uint8List alpha;

  int get length => alpha.length;

  /// Coverage at pixel ([x], [y]). No bounds checking beyond the backing list.
  int at(int x, int y) => alpha[y * width + x];

  /// Fraction of pixels whose coverage is at or above [cutoff] (0.0 … 1.0).
  /// Handy for "did the model actually find a subject?" heuristics.
  double coverage([int cutoff = 128]) {
    var fg = 0;
    for (var i = 0; i < alpha.length; i++) {
      if (alpha[i] >= cutoff) fg++;
    }
    return fg / alpha.length;
  }

  AlphaMask copyWith({Uint8List? alpha}) =>
      AlphaMask(width: width, height: height, alpha: alpha ?? this.alpha);

  @override
  bool operator ==(Object other) =>
      other is AlphaMask &&
      other.width == width &&
      other.height == height &&
      listEquals(other.alpha, alpha);

  @override
  int get hashCode => Object.hash(width, height, Object.hashAll(alpha));

  @override
  String toString() => 'AlphaMask(${width}x$height)';
}
