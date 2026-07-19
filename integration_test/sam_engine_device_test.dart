// OBJ-5 (#87) device validation: MobileSAM on real hardware — asset
// availability, encoder/decoder latency, embedding-cache effect, mask sanity,
// and process RSS around the encoder pass.
//
//   flutter test integration_test/sam_engine_device_test.dart -d <device>

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/features/segmentation/engines/object/mobile_sam_engine.dart';

/// VmRSS / VmHWM from /proc/self/status, in MB (-1 when unavailable).
int _procMb(String field) {
  try {
    final line = File('/proc/self/status')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('$field:'));
    return int.parse(line.replaceAll(RegExp(r'[^0-9]'), '')) ~/ 1024;
  } catch (_) {
    return -1;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MobileSAM segments a tapped object with sane latency', (
    tester,
  ) async {
    final engine = MobileSamEngine();
    expect(
      await engine.isAvailable(),
      isTrue,
      reason: 'both .onnx assets must be bundled',
    );

    // 1536×1024 synthetic photo: gradient background + bright disc — the
    // "object" the tap points at (matches the conversion-time fixture).
    final image = img.Image(width: 1536, height: 1024);
    for (var y = 0; y < 1024; y++) {
      for (var x = 0; x < 1536; x++) {
        image.setPixelRgb(x, y, 40 + (x * 120) ~/ 1536, 60 + (y * 60) ~/ 1024, 90);
      }
    }
    img.fillCircle(
      image,
      x: (1536 * 0.6).round(),
      y: 512,
      radius: 220,
      color: img.ColorRgb8(235, 210, 60),
    );
    final tmp = await getTemporaryDirectory();
    final photo = File('${tmp.path}/sam_probe.png')
      ..writeAsBytesSync(img.encodePng(image));

    final rssBefore = _procMb('VmRSS');

    // Cold: decode + resize + encoder session + TinyViT pass + cache write.
    final cold = Stopwatch()..start();
    await engine.precompute(photo.path);
    cold.stop();

    final rssAfter = _procMb('VmRSS');

    // Tap: decoder-only against the cached embedding.
    final tap = Stopwatch()..start();
    final mask = await engine.segmentAt(photo.path, [
      const PromptPoint(Offset(1536 * 0.6, 512)),
    ]);
    tap.stop();

    // Second tap elsewhere — still embedding-cached.
    final warm = Stopwatch()..start();
    final miss = await engine.segmentAt(photo.path, [
      const PromptPoint(Offset(80, 80)),
    ]);
    warm.stop();

    // ignore: avoid_print
    print(
      'SAM_METRICS encoder_cold_ms:${cold.elapsedMilliseconds} '
      'tap_ms:${tap.elapsedMilliseconds} '
      'warm_tap_ms:${warm.elapsedMilliseconds} '
      'rss_before_mb:$rssBefore rss_after_mb:$rssAfter '
      'vm_hwm_mb:${_procMb('VmHWM')}',
    );

    expect(mask, isNotNull);
    expect(miss, isNotNull);
    expect(mask!.width, 1536);
    expect(mask.height, 1024);
    expect(
      mask.at((1536 * 0.6).round(), 512),
      255,
      reason: 'the tapped disc is the object',
    );
    expect(mask.at(30, 30), 0, reason: 'the far background is not');
    var object = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask.alpha[i] > 0) object++;
    }
    final fraction = object / mask.length;
    expect(
      fraction,
      inInclusiveRange(0.02, 0.6),
      reason: 'mask should be roughly disc-sized, got $fraction',
    );

    await engine.dispose();
  });
}
