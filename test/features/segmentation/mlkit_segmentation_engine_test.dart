import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/engines/mlkit_segmentation_engine.dart';

void main() {
  group('MlKitSegmentationEngine.maskFromConfidence', () {
    test('maps confidences 0…1 to 8-bit alpha, row-major', () {
      final mask = MlKitSegmentationEngine.maskFromConfidence(
        [0.0, 0.5, 1.0, 0.25],
        2,
        2,
      );
      expect(mask.width, 2);
      expect(mask.height, 2);
      // 0.5*255 = 127.5 → 128 ; 0.25*255 = 63.75 → 64
      expect(mask.alpha, [0, 128, 255, 64]);
    });

    test('clamps out-of-range confidences to 0…255', () {
      final mask = MlKitSegmentationEngine.maskFromConfidence(
        [-0.2, 1.5],
        2,
        1,
      );
      expect(mask.alpha, [0, 255]);
    });
  });
}
