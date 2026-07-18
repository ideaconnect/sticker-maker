// On-device verification of the AI background-removal pipeline (#26/#2).
//
// This is a DEVICE test: it needs ML Kit (a native plugin) and a real photo, so
// it can't run headlessly. It reads a fixture the harness pushes to the app's
// external files dir and skips cleanly when that's absent (CI / other devices).
//
//   adb push <photo>.jpg /sdcard/Android/data/tech.idct.stickermaker/files/seg_fixture.jpg
//   flutter test integration_test/segmentation_device_test.dart -d <device>
//
// It asserts ML Kit finds a real subject, then writes the mask + a rendered
// transparent cut-out back to the external dir so they can be pulled and eyeballed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/sticker_encoder.dart';
import 'package:sticker_maker/features/export/sticker_renderer.dart';
import 'package:sticker_maker/features/segmentation/engines/mlkit_segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';
import 'package:sticker_maker/features/segmentation/segmentation_engine.dart';
import 'package:sticker_maker/features/segmentation/segmentation_registry.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ML Kit removes the background from a real photo on-device', (
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

    final registry = SegmentationRegistry([MlKitSegmentationEngine()]);
    expect(
      await registry.resolve(),
      isNotNull,
      reason: 'ML Kit should be available on Android',
    );

    // The ML Kit model is a Play-services module that downloads on first use;
    // give it a few tries before declaring failure.
    SegmentationResult? result;
    for (var attempt = 0; attempt < 6 && result == null; attempt++) {
      result = await registry.segment(
        SegmentationRequest(imagePath: fixture.path),
      );
      if (result == null) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }

    expect(
      result,
      isNotNull,
      reason: 'ML Kit produced no mask (model still downloading?)',
    );
    expect(result!.engineId, 'mlkit');

    // A real subject occupies a meaningful, non-degenerate slice of the frame.
    final coverage = result.mask.coverage();
    expect(coverage, greaterThan(0.02), reason: 'found a subject ($coverage)');
    expect(
      coverage,
      lessThan(0.98),
      reason: 'did not just select the whole frame ($coverage)',
    );

    // Build the cut-out frame (photo ∩ mask), then take it all the way through
    // the export pipeline to a WhatsApp/Telegram-ready transparent WebP — proving
    // the AI + the WebP encoder work together on real hardware.
    final maskPng = await MaskStore.encodePng(result.mask);
    final maskFile = File('${ext.path}/seg_mask.png')
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

    // PNG render sanity, then the real WebP export.
    final png = await StickerRenderer.renderPng(cutoutFrame, size: 192);
    expect(png.length, greaterThan(0));

    final webp = await StickerEncoder.webp(cutoutFrame, size: 192);
    final decodedWebp = img.decodeWebP(webp.bytes);
    expect(decodedWebp, isNotNull, reason: 'WebP round-trips on device');
    expect(
      decodedWebp!.hasAlpha,
      isTrue,
      reason: 'WebP keeps the transparent background',
    );

    // Emit the WebP as base64 — the test log survives the post-run uninstall.
    // ignore: avoid_print
    print('SEG_COVERAGE:${coverage.toStringAsFixed(4)}');
    // ignore: avoid_print
    print('SEG_WEBP_BYTES:${webp.byteLength}');
    // ignore: avoid_print
    print('SEG_WEBP_B64_START');
    // ignore: avoid_print
    print(base64Encode(webp.bytes));
    // ignore: avoid_print
    print('SEG_WEBP_B64_END');
  });
}
