import 'dart:math' as math;
import 'dart:ui';

/// Maps points from the editor's 512-logical canvas space into an image layer's
/// mask-pixel space, inverting the same transform the renderer applies: the
/// layer sits centred at [position], its content is a [boxSize]-logical square
/// scaled by [layerScale] and rotated by [rotation], and the photo is fit
/// (BoxFit.contain) inside that square.
///
/// Pure and self-contained so the fiddly geometry can be unit-tested without a
/// device (see StickerCanvas `_MaskedImagePainter` for the forward direction).
class MaskMapper {
  const MaskMapper({
    required this.imageSize,
    required this.position,
    required this.layerScale,
    required this.rotation,
    this.boxSize = 440,
  });

  /// Source image (== mask) size in pixels.
  final Size imageSize;

  /// Layer centre in 512-logical units.
  final Offset position;

  /// Layer's own scale and rotation (radians).
  final double layerScale;
  final double rotation;

  /// The logical square the photo is fit into (matches the renderer's 440).
  final double boxSize;

  /// The uniform BoxFit.contain factor (image px -> box logical).
  double get _containScale =>
      math.min(boxSize / imageSize.width, boxSize / imageSize.height);

  Size get _fitSize =>
      Size(imageSize.width * _containScale, imageSize.height * _containScale);

  /// A logical canvas point -> mask pixel coordinate, or null when the point
  /// falls outside the photo (on the transparent letterbox / off the layer).
  Offset? canvasToMask(Offset canvasLogical) {
    final rel = canvasLogical - position;
    // Undo the layer rotation.
    final a = -rotation;
    final cosA = math.cos(a);
    final sinA = math.sin(a);
    final unrot = Offset(
      rel.dx * cosA - rel.dy * sinA,
      rel.dx * sinA + rel.dy * cosA,
    );
    // Undo the layer scale, into the centred box frame.
    final box = unrot / layerScale;
    final bx = box.dx + boxSize / 2;
    final by = box.dy + boxSize / 2;
    // Undo the contain letterbox into image pixels.
    final fit = _fitSize;
    final offX = (boxSize - fit.width) / 2;
    final offY = (boxSize - fit.height) / 2;
    final ix = (bx - offX) / fit.width * imageSize.width;
    final iy = (by - offY) / fit.height * imageSize.height;
    if (ix < 0 || iy < 0 || ix >= imageSize.width || iy >= imageSize.height) {
      return null;
    }
    return Offset(ix, iy);
  }

  /// A brush radius in logical canvas units -> mask pixels.
  double radiusToMask(double logicalRadius) =>
      logicalRadius / layerScale / _containScale;
}
