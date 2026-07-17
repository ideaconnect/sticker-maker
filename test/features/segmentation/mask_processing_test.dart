import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_processing.dart';

AlphaMask maskOf(int w, int h, List<int> values) =>
    AlphaMask(width: w, height: h, alpha: Uint8List.fromList(values));

void main() {
  group('threshold', () {
    test('snaps below the cutoff to low and at/above to high', () {
      final out = MaskProcessing.threshold(maskOf(3, 1, [100, 128, 200]), 128);
      expect(out.alpha, [0, 255, 255]);
    });

    test('honours custom low/high', () {
      final out = MaskProcessing.threshold(
        maskOf(2, 1, [10, 250]),
        128,
        low: 5,
        high: 200,
      );
      expect(out.alpha, [5, 200]);
    });
  });

  group('feather', () {
    test('radius 0 is a no-op', () {
      final input = maskOf(3, 1, [0, 255, 0]);
      expect(MaskProcessing.feather(input, 0), equals(input));
    });

    test('box-blurs a hard edge, clamping at the border', () {
      // Single row so only the horizontal pass matters; window = 3.
      final out = MaskProcessing.feather(maskOf(5, 1, [0, 0, 255, 0, 0]), 1);
      expect(out.alpha, [0, 85, 85, 85, 0]); // 255 ~/ 3 == 85
    });

    test('a uniform mask is unchanged by feathering', () {
      final input = AlphaMask.filled(4, 4, 200);
      expect(MaskProcessing.feather(input, 2), equals(input));
    });
  });

  group('keepLargestComponent', () {
    test('drops a stray speck, keeps the main blob (soft edges preserved)', () {
      // 5x5: a 3x3 block of 255 in the top-left (9 px) and a lone speck bottom-
      // right. The speck must be removed; the block kept verbatim.
      final mask = maskOf(5, 5, [
        255, 255, 255, 0, 0, //
        255, 200, 255, 0, 0, // note the soft 200 inside the blob
        255, 255, 255, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 255, //  <- speck
      ]);
      final out = MaskProcessing.keepLargestComponent(mask);
      expect(out.at(4, 4), 0, reason: 'speck removed');
      expect(out.at(0, 0), 255, reason: 'blob kept');
      expect(out.at(1, 1), 200, reason: 'soft value inside blob preserved');
      expect(out.coverage(1), 9 / 25);
    });

    test('diagonal-only pixels are separate (4-connectivity)', () {
      // Two single pixels touching only at a corner → two components of size 1.
      // Neither is "largest" over the other, so the first-labelled one wins.
      final mask = maskOf(2, 2, [255, 0, 0, 255]);
      final out = MaskProcessing.keepLargestComponent(mask);
      expect(out.coverage(1), 0.25); // exactly one pixel survives
    });

    test('all-background input yields an empty mask', () {
      final out = MaskProcessing.keepLargestComponent(AlphaMask.empty(3, 3));
      expect(out, equals(AlphaMask.empty(3, 3)));
    });
  });

  group('process chain', () {
    test('threshold → largest-component → feather, in order', () {
      final mask = maskOf(5, 5, [
        130, 130, 130, 0, 0, //
        130, 130, 130, 0, 0, //
        130, 130, 130, 0, 0, //
        0, 0, 0, 0, 0, //
        0, 0, 0, 0, 200, //  <- speck above threshold but not largest
      ]);
      final out = MaskProcessing.process(
        mask,
        const MaskProcessingOptions(threshold: 128),
      );
      expect(out.at(4, 4), 0, reason: 'speck removed by largest-component');
      // Interior of the thresholded 3x3 block is solid 255 after feather.
      expect(out.at(1, 1), 255);
    });

    test('defaults keep the soft mask but still clean specks', () {
      final mask = maskOf(3, 3, [
        255, 255, 0, //
        255, 255, 0, //
        0, 0, 255, //  <- corner speck
      ]);
      final out = MaskProcessing.process(mask, const MaskProcessingOptions());
      // The speck's own strong value is gone; only faint feather bleed from the
      // neighbouring blob remains (a kept speck would read ~140+ here).
      expect(
        out.at(2, 2),
        lessThan(100),
        reason: 'speck removed (only feather bleed remains)',
      );
      expect(out.coverage() > 0, isTrue, reason: 'main blob survives');
    });
  });
}
