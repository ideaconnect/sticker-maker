import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/image_adjustments.dart';
import 'package:sticker_maker/core/rendering/color_matrix.dart';

void main() {
  test('identity adjustments produce the identity matrix', () {
    final m = ImageAdjustments.identity.toColorMatrix();
    expect(m, hasLength(20));
    for (var i = 0; i < 20; i++) {
      expect(m[i], closeTo(ColorMatrix.identity[i], 1e-9));
    }
  });

  test('brightness scales the RGB diagonal', () {
    final m = const ImageAdjustments(brightness: 1.5).toColorMatrix();
    expect(m[0], closeTo(1.5, 1e-9)); // R
    expect(m[6], closeTo(1.5, 1e-9)); // G
    expect(m[12], closeTo(1.5, 1e-9)); // B
    expect(m[18], closeTo(1.0, 1e-9)); // A untouched
  });

  test('saturation 0 collapses each row to the luma weights', () {
    final m = const ImageAdjustments(saturation: 0).toColorMatrix();
    // Row 0 (red output) becomes the luma coefficients.
    expect(m[0], closeTo(0.2126, 1e-6));
    expect(m[1], closeTo(0.7152, 1e-6));
    expect(m[2], closeTo(0.0722, 1e-6));
    // All three rows are identical for greyscale.
    expect(m[5], closeTo(m[0], 1e-9));
    expect(m[10], closeTo(m[0], 1e-9));
  });

  test('contrast adds a translation term', () {
    final m = const ImageAdjustments(contrast: 0.5).toColorMatrix();
    expect(m[0], closeTo(0.5, 1e-9));
    expect(m[4], closeTo(127.5 * 0.5, 1e-6)); // R translation
  });

  test('a 360° hue rotation is (near) identity', () {
    final m = const ImageAdjustments(hue: 360).toColorMatrix();
    for (var i = 0; i < 20; i++) {
      expect(m[i], closeTo(ColorMatrix.identity[i], 1e-6));
    }
  });

  test('multiply composes affine matrices', () {
    final doubled = ColorMatrix.multiply(
      ColorMatrix.brightness(2),
      ColorMatrix.brightness(3),
    );
    expect(doubled[0], closeTo(6, 1e-9));
  });
}
