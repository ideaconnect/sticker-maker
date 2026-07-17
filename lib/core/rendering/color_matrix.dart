import 'dart:math' as math;

import '../models/image_adjustments.dart';

/// Builds 4×5 color matrices (the format [ColorFilter.matrix] expects) for the
/// Adjust tool, and composes them into a single matrix for an
/// [ImageAdjustments]. Matrices operate on 0–255 channel values; the 5th column
/// is a constant translation in the same range.
abstract final class ColorMatrix {
  ColorMatrix._();

  /// Rec. 709 luma coefficients.
  static const double _lr = 0.2126;
  static const double _lg = 0.7152;
  static const double _lb = 0.0722;

  static const List<double> identity = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  /// Multiplicative RGB scale (1.0 = unchanged).
  static List<double> brightness(double b) => [
    b, 0, 0, 0, 0, //
    0, b, 0, 0, 0, //
    0, 0, b, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  /// Contrast around mid-grey (1.0 = unchanged).
  static List<double> contrast(double c) {
    final t = 127.5 * (1 - c);
    return [
      c, 0, 0, 0, t, //
      0, c, 0, 0, t, //
      0, 0, c, 0, t, //
      0, 0, 0, 1, 0,
    ];
  }

  /// Saturation (0 = greyscale, 1 = unchanged, >1 = more saturated).
  static List<double> saturation(double s) {
    final ir = (1 - s) * _lr;
    final ig = (1 - s) * _lg;
    final ib = (1 - s) * _lb;
    return [
      ir + s, ig, ib, 0, 0, //
      ir, ig + s, ib, 0, 0, //
      ir, ig, ib + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  /// Hue rotation in degrees.
  static List<double> hueRotate(double degrees) {
    final rad = degrees * math.pi / 180.0;
    final c = math.cos(rad);
    final s = math.sin(rad);
    return [
      _lr + c * (1 - _lr) + s * (-_lr),
      _lg + c * (-_lg) + s * (-_lg),
      _lb + c * (-_lb) + s * (1 - _lb),
      0,
      0,
      _lr + c * (-_lr) + s * 0.143,
      _lg + c * (1 - _lg) + s * 0.140,
      _lb + c * (-_lb) + s * (-0.283),
      0,
      0,
      _lr + c * (-_lr) + s * (-(1 - _lr)),
      _lg + c * (-_lg) + s * _lg,
      _lb + c * (1 - _lb) + s * _lb,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// Composes `a` after `b` (i.e. `a · b`), treating each 4×5 matrix as a 5×5
  /// affine matrix with an implicit `[0,0,0,0,1]` bottom row.
  static List<double> multiply(List<double> a, List<double> b) {
    double at(List<double> m, int r, int col) =>
        r < 4 ? m[r * 5 + col] : (col == 4 ? 1.0 : 0.0);
    final out = List<double>.filled(20, 0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 5; j++) {
        var sum = 0.0;
        for (var k = 0; k < 5; k++) {
          sum += at(a, i, k) * at(b, k, j);
        }
        out[i * 5 + j] = sum;
      }
    }
    return out;
  }
}

extension ImageAdjustmentsMatrix on ImageAdjustments {
  /// The combined 4×5 color matrix for these adjustments.
  List<double> toColorMatrix() {
    if (isIdentity) return ColorMatrix.identity;
    var m = ColorMatrix.identity;
    m = ColorMatrix.multiply(ColorMatrix.hueRotate(hue), m);
    m = ColorMatrix.multiply(ColorMatrix.saturation(saturation), m);
    m = ColorMatrix.multiply(ColorMatrix.contrast(contrast), m);
    m = ColorMatrix.multiply(ColorMatrix.brightness(brightness), m);
    return m;
  }
}
