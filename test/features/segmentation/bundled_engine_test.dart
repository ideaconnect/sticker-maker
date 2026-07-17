import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/features/segmentation/engines/bundled/bundled_segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/engines/bundled/mask_tensor.dart';
import 'package:sticker_maker/features/segmentation/engines/bundled/segmenter.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';

/// A fake native seam: records what the engine fed it and returns a fixed 2x2
/// probability map, so the pure decode/pack/unpack pipeline can be tested with
/// no ORT runtime and no device.
class _FakeSegmenter implements Segmenter {
  List<int>? lastShape;
  int? lastInputLength;

  @override
  Future<Float32List> infer(Float32List input, List<int> shape) async {
    lastShape = shape;
    lastInputLength = input.length;
    return Float32List.fromList([0.0, 0.5, 0.5, 1.0]);
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'bundled engine runs decode -> pack -> infer -> unpack end to end',
    () async {
      final tmp = Directory.systemTemp.createTempSync('sm_bundled_');
      addTearDown(() {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {}
      });

      // A 3x2 solid test photo.
      final image = img.Image(width: 3, height: 2);
      img.fill(image, color: img.ColorRgb8(120, 130, 140));
      final path = '${tmp.path}/in.png';
      File(path).writeAsBytesSync(img.encodePng(image));

      final fake = _FakeSegmenter();
      final engine = BundledSegmentationEngine(
        config: const ModelConfig(assetPath: 'x', inputSize: 2),
        segmenterFactory: (_) async => fake,
      );

      final result = await engine.segment(
        SegmentationRequest(imagePath: path),
      );

      expect(result.engineId, 'bundled');
      // Pre-processing packed a [1,3,2,2] NCHW tensor (12 floats).
      expect(fake.lastShape, [1, 3, 2, 2]);
      expect(fake.lastInputLength, 12);
      // Mask comes back at the original photo resolution.
      expect(result.mask.width, 3);
      expect(result.mask.height, 2);
      // The fake map is 0 at top-left, 1 at bottom-right.
      expect(result.mask.at(0, 0), lessThan(64));
      expect(result.mask.at(2, 1), greaterThan(192));
    },
  );

  test('a bad image path fails as a SegmentationException', () async {
    final engine = BundledSegmentationEngine(
      config: const ModelConfig(assetPath: 'x', inputSize: 2),
      segmenterFactory: (_) async => _FakeSegmenter(),
    );
    await expectLater(
      engine.segment(const SegmentationRequest(imagePath: '/no/such/file.png')),
      throwsA(isA<SegmentationException>()),
    );
  });
}
