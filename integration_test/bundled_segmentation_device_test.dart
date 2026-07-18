// On-device verification of the BUNDLED U²-Netp ONNX engine (#28).
//
// Unlike the ML Kit test, this exercises `BundledSegmentationEngine` →
// `OrtSegmenter` → native `flutter_onnxruntime` loading assets/models/u2netp.onnx.
// It's the only path that proves the bundled opset-17 model actually loads and
// runs under ORT Mobile on real hardware (page-size / ABI / opset support).
//
//   adb push <photo>.jpg /sdcard/Android/data/tech.idct.stickermaker/files/seg_fixture.jpg
//   flutter test integration_test/bundled_segmentation_device_test.dart -d <device>
//
// Skips cleanly when the fixture is absent (CI / other devices).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/sticker_encoder.dart';
import 'package:sticker_maker/features/segmentation/engines/bundled/bundled_segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('bundled U²-Netp ONNX cuts out a real photo on-device', (
    tester,
  ) async {
    final ext = await getExternalStorageDirectory();
    final fixture = File('${ext!.path}/seg_fixture.jpg');
    if (!fixture.existsSync()) {
      markTestSkipped(
        'no seg_fixture.jpg on device — push a photo to '
        '${ext.path}/seg_fixture.jpg first',
      );
      return;
    }

    final engine = BundledSegmentationEngine();
    expect(
      await engine.isAvailable(),
      isTrue,
      reason:
          'assets/models/u2netp.onnx must be bundled for the offline engine',
    );

    // Runs the whole native pipeline: decode → 320² NCHW → ORT inference → mask.
    final result = await engine.segment(
      SegmentationRequest(imagePath: fixture.path),
    );
    expect(result.engineId, 'bundled');

    // A real subject occupies a meaningful, non-degenerate slice of the frame.
    final coverage = result.mask.coverage();
    expect(coverage, greaterThan(0.02), reason: 'found a subject ($coverage)');
    expect(
      coverage,
      lessThan(0.98),
      reason: 'did not just select the whole frame ($coverage)',
    );

    // Persist mask + take it through the real WebP export, proving the ONNX
    // model and the encoder cooperate on-device.
    final maskPng = await MaskStore.encodePng(result.mask);
    final maskFile = File('${ext.path}/seg_bundled_mask.png')
      ..writeAsBytesSync(maskPng);
    final cutoutFrame = Frame(
      id: 'f',
      layers: [
        ImageLayer(
          id: 'i',
          name: 'photo',
          assetPath: fixture.path,
          maskPath: maskFile.path,
        ),
      ],
    );

    final webp = await StickerEncoder.webp(cutoutFrame, size: 192);
    final decodedWebp = img.decodeWebP(webp.bytes);
    expect(decodedWebp, isNotNull, reason: 'WebP round-trips on device');
    expect(
      decodedWebp!.hasAlpha,
      isTrue,
      reason: 'transparent background kept',
    );

    // Emit results — the log survives the post-run uninstall.
    // ignore: avoid_print
    print('BUNDLED_SEG_COVERAGE:${coverage.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('BUNDLED_SEG_WEBP_BYTES:${webp.byteLength}');
    // ignore: avoid_print
    print('BUNDLED_SEG_WEBP_B64_START');
    // ignore: avoid_print
    print(base64Encode(webp.bytes));
    // ignore: avoid_print
    print('BUNDLED_SEG_WEBP_B64_END');
  });
}
