import 'dart:typed_data';

import '../../alpha_mask.dart';

/// The per-model pre/post-processing recipe. Kept as data (not hard-coded
/// constants) because U²-Net and IS-Net use *different* recipes and silently
/// swapping the model file with the wrong recipe produces garbage masks.
class ModelConfig {
  const ModelConfig({
    required this.assetPath,
    this.inputSize = 320,
    this.mean = const [0.485, 0.456, 0.406],
    this.std = const [0.229, 0.224, 0.225],
    this.scale = 1 / 255.0,
  });

  /// Bundled asset path of the `.onnx` weights.
  final String assetPath;

  /// Square model input side (e.g. 320).
  final int inputSize;

  /// Per-channel (RGB) ImageNet normalization.
  final List<double> mean;
  final List<double> std;

  /// Raw pixel scale applied before normalization (1/255).
  final double scale;
}

/// U²-Netp (small), Apache-2.0. See docs/M2_BUNDLED_SEGMENTATION_DECISION.md.
const u2netpConfig = ModelConfig(assetPath: 'assets/models/u2netp.onnx');

/// Pure tensor <-> image conversions around the native inference seam. No
/// `dart:ui`, no plugin — fully host-unit-testable, which is where recipe bugs
/// (wrong mean/std, BGR order, planar-vs-interleaved) get caught cheaply.
abstract final class MaskTensor {
  MaskTensor._();

  /// Normalizes a `size`×`size` RGB image (row-major, 3 bytes/px: R,G,B) into a
  /// planar **NCHW** `Float32List` `[1,3,size,size]` using [config]'s recipe:
  /// `((px/255) - mean) / std`, R-plane then G-plane then B-plane.
  static Float32List packTensor(Uint8List rgb, int size, ModelConfig config) {
    final n = size * size;
    assert(rgb.length == n * 3, 'rgb must be size*size*3 bytes');
    final out = Float32List(3 * n);
    final s = config.scale;
    final m = config.mean;
    final d = config.std;
    for (var i = 0; i < n; i++) {
      out[i] = (rgb[i * 3] * s - m[0]) / d[0]; // R plane
      out[n + i] = (rgb[i * 3 + 1] * s - m[1]) / d[1]; // G plane
      out[2 * n + i] = (rgb[i * 3 + 2] * s - m[2]) / d[2]; // B plane
    }
    return out;
  }

  /// Converts a model probability map [out] (`size`×`size`, sigmoid ~[0,1])
  /// into an [AlphaMask] at [dstW]×[dstH]:
  ///  * min-max normalize (`normPRED`), with a **low-range guard**: if the map
  ///    is nearly flat (`max-min < lowRangeGuard`) it is treated as uniform
  ///    foreground/background rather than stretching sensor noise into garbage;
  ///  * bilinear upscale of the *continuous* map to the original size;
  ///  * quantize to 8-bit. Foreground = 255.
  ///
  /// The hard threshold / feather / largest-component happen downstream
  /// (`MaskProcessing`) so soft edges survive.
  static AlphaMask unpackMask(
    Float32List out,
    int size,
    int dstW,
    int dstH, {
    double lowRangeGuard = 0.05,
  }) {
    var min = double.infinity;
    var max = double.negativeInfinity;
    var sum = 0.0;
    for (final v in out) {
      if (v < min) min = v;
      if (v > max) max = v;
      sum += v;
    }
    final range = max - min;
    if (range < lowRangeGuard) {
      final mean = sum / out.length;
      return AlphaMask.filled(dstW, dstH, mean >= 0.5 ? 255 : 0);
    }

    // Normalized continuous map at model resolution.
    final norm = Float32List(out.length);
    for (var i = 0; i < out.length; i++) {
      norm[i] = (out[i] - min) / range;
    }

    final alpha = Uint8List(dstW * dstH);
    for (var y = 0; y < dstH; y++) {
      // Map dst pixel centre back to source coordinate (bilinear, edge-clamped).
      final sy = ((y + 0.5) * size / dstH - 0.5).clamp(0.0, size - 1.0);
      final y0 = sy.floor();
      final y1 = (y0 + 1 < size) ? y0 + 1 : y0;
      final fy = sy - y0;
      for (var x = 0; x < dstW; x++) {
        final sx = ((x + 0.5) * size / dstW - 0.5).clamp(0.0, size - 1.0);
        final x0 = sx.floor();
        final x1 = (x0 + 1 < size) ? x0 + 1 : x0;
        final fx = sx - x0;
        final v00 = norm[y0 * size + x0];
        final v01 = norm[y0 * size + x1];
        final v10 = norm[y1 * size + x0];
        final v11 = norm[y1 * size + x1];
        final top = v00 + (v01 - v00) * fx;
        final bot = v10 + (v11 - v10) * fx;
        final v = top + (bot - top) * fy;
        alpha[y * dstW + x] = (v * 255).round().clamp(0, 255);
      }
    }
    return AlphaMask(width: dstW, height: dstH, alpha: alpha);
  }
}
