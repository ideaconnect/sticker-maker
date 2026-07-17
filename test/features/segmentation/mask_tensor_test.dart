import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/engines/bundled/mask_tensor.dart';

void main() {
  group('MaskTensor.packTensor', () {
    test('normalizes RGB into planar NCHW with the U²-Net recipe', () {
      // 2x2: red, green, blue, white.
      final rgb = Uint8List.fromList([
        255, 0, 0, //
        0, 255, 0, //
        0, 0, 255, //
        255, 255, 255, //
      ]);
      final out = MaskTensor.packTensor(rgb, 2, u2netpConfig);

      expect(out.length, 12); // 3 planes * 4 px
      // R plane [0..3]: ((r/255) - 0.485) / 0.229
      expect(out[0], closeTo(2.2489, 1e-3)); // r=1
      expect(out[1], closeTo(-2.1179, 1e-3)); // r=0
      // G plane [4..7]: ((g/255) - 0.456) / 0.224
      expect(out[5], closeTo(2.4286, 1e-3)); // g=1
      // B plane [8..11]: ((b/255) - 0.406) / 0.225
      expect(out[8], closeTo(-1.8044, 1e-3)); // b=0
      expect(out[10], closeTo(2.64, 1e-3)); // b=1
    });
  });

  group('MaskTensor.unpackMask', () {
    test('low-range guard: a flat high map becomes all-foreground', () {
      final out = Float32List.fromList([0.7, 0.72, 0.71, 0.7]);
      final mask = MaskTensor.unpackMask(out, 2, 2, 2);
      expect(mask.alpha, everyElement(255));
    });

    test('low-range guard: a flat low map becomes all-background', () {
      final out = Float32List.fromList([0.02, 0.0, 0.03, 0.01]);
      final mask = MaskTensor.unpackMask(out, 2, 2, 2);
      expect(mask.alpha, everyElement(0));
    });

    test('min-max normalizes then quantizes at native resolution', () {
      final out = Float32List.fromList([0.0, 0.5, 0.5, 1.0]);
      final mask = MaskTensor.unpackMask(out, 2, 2, 2);
      expect(mask.alpha, [0, 128, 128, 255]);
    });

    test('bilinear upscales to the target size, preserving corners', () {
      final out = Float32List.fromList([0.0, 0.5, 0.5, 1.0]);
      final mask = MaskTensor.unpackMask(out, 2, 4, 4);
      expect(mask.width, 4);
      expect(mask.height, 4);
      expect(mask.at(0, 0), 0);
      expect(mask.at(3, 3), 255);
    });
  });
}
