import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_brush.dart';

void main() {
  group('MaskBrush.paint', () {
    test('hard erase clears a disc, leaves the rest opaque', () {
      final out = MaskBrush.paint(
        AlphaMask.filled(10, 10, 255),
        const BrushStroke(
          points: [Offset(5, 5)],
          radius: 2,
          erase: true,
          soft: false,
        ),
      );
      expect(out.at(5, 5), 0, reason: 'centre erased');
      expect(out.at(7, 5), 0, reason: 'edge of disc (d==2) erased');
      expect(out.at(8, 5), 255, reason: 'just outside the disc');
      expect(out.at(0, 0), 255, reason: 'far corner untouched');
    });

    test('hard restore fills a disc on an empty mask', () {
      final out = MaskBrush.paint(
        AlphaMask.empty(10, 10),
        const BrushStroke(
          points: [Offset(5, 5)],
          radius: 2,
          erase: false,
          soft: false,
        ),
      );
      expect(out.at(5, 5), 255);
      expect(out.at(0, 0), 0);
    });

    test('soft erase feathers: full at centre, partial near the edge', () {
      final out = MaskBrush.paint(
        AlphaMask.filled(20, 20, 255),
        const BrushStroke(points: [Offset(10, 10)], radius: 5, erase: true),
      );
      expect(out.at(10, 10), 0, reason: 'centre fully erased');
      final mid = out.at(12, 10); // distance 2 of 5
      expect(mid, greaterThan(0));
      expect(mid, lessThan(255));
      expect(out.at(10, 5), 255, reason: 'at the radius edge, untouched');
    });

    test('a multi-point stroke erases a continuous line', () {
      final out = MaskBrush.paint(
        AlphaMask.filled(20, 5, 255),
        const BrushStroke(
          points: [Offset(2, 2), Offset(18, 2)],
          radius: 1.5,
          erase: true,
          soft: false,
        ),
      );
      expect(out.at(2, 2), 0);
      expect(out.at(10, 2), 0, reason: 'gap between endpoints is filled in');
      expect(out.at(18, 2), 0);
    });

    test('empty stroke or zero radius is a no-op', () {
      final mask = AlphaMask.filled(4, 4, 128);
      expect(
        MaskBrush.paint(
          mask,
          const BrushStroke(points: [], radius: 4, erase: true),
        ),
        equals(mask),
      );
      expect(
        MaskBrush.paint(
          mask,
          const BrushStroke(points: [Offset(2, 2)], radius: 0, erase: true),
        ),
        equals(mask),
      );
    });
  });
}
