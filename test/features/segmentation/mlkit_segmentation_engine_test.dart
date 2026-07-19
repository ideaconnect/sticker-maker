import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/engines/mlkit_segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/segmentation_registry.dart';

/// The engine below ML Kit in the registry — proves the fall-through reaches
/// it when ML Kit fails.
class _NextEngine implements SegmentationEngine {
  @override
  String get id => 'next';
  @override
  String get label => 'Next';
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<SegmentationResult> segment(SegmentationRequest request) async =>
      SegmentationResult(mask: AlphaMask.filled(2, 2, 255), engineId: id);
}

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

  group('MlKitSegmentationEngine.segment failure wrapping', () {
    test('a file-read failure surfaces as SegmentationException, not '
        'FileSystemException (the interface contract)', () async {
      final engine = MlKitSegmentationEngine();
      await expectLater(
        engine.segment(
          const SegmentationRequest(imagePath: '/no/such/photo.png'),
        ),
        throwsA(
          isA<SegmentationException>().having(
            (e) => e.engineId,
            'engineId',
            'mlkit',
          ),
        ),
      );
    });

    test(
      'the registry falls through to the next engine on that failure',
      () async {
        // isAvailable() checks defaultTargetPlatform — pin it to Android so the
        // ML Kit engine is attempted first regardless of the host OS.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        final registry = SegmentationRegistry([
          MlKitSegmentationEngine(),
          _NextEngine(),
        ]);
        final result = await registry.segment(
          const SegmentationRequest(imagePath: '/no/such/photo.png'),
        );
        expect(
          result?.engineId,
          'next',
          reason:
              'an untyped ML Kit throw must not abort the fall-through chain',
        );
      },
    );
  });
}
