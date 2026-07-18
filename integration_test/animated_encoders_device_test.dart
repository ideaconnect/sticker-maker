// ANIM-2/ANIM-3 (#67/#68) device verification: real 512² frames rendered by
// StickerRenderer, encoded on-hardware into
//   * Telegram-compliant WebM VP9 + alpha (≤256 KB), and
//   * WhatsApp-compliant animated WebP (≤500 KB, ≥8 ms frames),
// using the byte-budget ladders. Also asserts alpha actually survives.
//
//   flutter test integration_test/animated_encoders_device_test.dart -d <device>

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/export/ffmpeg_animation_encoder.dart';
import 'package:sticker_maker/features/export/sticker_renderer.dart';

/// Renders [count] real animation frames (growing caption) to straight-alpha
/// RGBA at 512², through the actual production renderer.
Future<List<RgbaFrame>> _renderFrames(int count, int durationMs) async {
  final frames = <RgbaFrame>[];
  for (var i = 0; i < count; i++) {
    final frame = Frame(
      id: 'f$i',
      layers: [
        TextLayer(
          id: 't$i',
          name: 'W',
          text: 'WOOF ${i + 1}',
          fontFamily: 'Bangers',
          fontSize: 40.0 + 6 * i,
        ),
      ],
    );
    final image = await StickerRenderer.renderImage(frame);
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    image.dispose();
    frames.add(
      RgbaFrame(
        bytes: data!.buffer.asUint8List(),
        width: 512,
        height: 512,
        durationMs: durationMs,
      ),
    );
  }
  return frames;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Telegram: WebM VP9+alpha within 256 KB from real frames',
    (tester) async {
      final encoder = FfmpegWebmVp9Encoder();
      expect(await encoder.isAvailable(), isTrue);

      final frames = await _renderFrames(8, 125); // 1 s at 8 fps
      final result = await encodeWithinBudget(
        encoder,
        frames,
        AnimationSpec.telegramWebm,
        qualities: telegramBitrateLadderFor(1),
      );

      // ignore: avoid_print
      print('TG_WEBM_BYTES:${result.bytes.length} q:${result.quality}');
      expect(result.withinBudget, isTrue);
      expect(result.bytes.length, lessThanOrEqualTo(256 * 1024));
      // EBML magic — real Matroska/WebM.
      expect(result.bytes.sublist(0, 4), [0x1A, 0x45, 0xDF, 0xA3]);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'WhatsApp: animated WebP within 500 KB, 512², >=8 ms frames, alpha kept',
    (tester) async {
      final encoder = FfmpegAnimWebpEncoder();
      expect(await encoder.isAvailable(), isTrue);

      final frames = await _renderFrames(8, 125);
      final result = await encodeWithinBudget(
        encoder,
        frames,
        AnimationSpec.whatsappWebp,
        qualities: whatsappQualityLadder,
      );

      // ignore: avoid_print
      print('WA_WEBP_BYTES:${result.bytes.length} q:${result.quality}');
      expect(result.withinBudget, isTrue);
      expect(result.bytes.length, lessThanOrEqualTo(500 * 1024));

      final decoded = img.decodeWebP(result.bytes)!;
      // ignore: avoid_print
      print('WA_WEBP_FRAMES:${decoded.numFrames}');
      expect(decoded.width, 512);
      expect(decoded.height, 512);
      expect(decoded.numFrames, 8, reason: 'all frames kept');
      for (final f in decoded.frames) {
        expect(f.frameDuration, greaterThanOrEqualTo(8));
      }
      // The transparent background survived (WhatsApp requirement).
      expect(decoded.frames.first.getPixel(0, 0).a, 0);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  testWidgets(
    'the WebM stream really carries alpha (alpha_mode metadata)',
    (tester) async {
      final encoder = FfmpegWebmVp9Encoder();
      final frames = await _renderFrames(3, 125);
      final bytes = await encoder.encode(frames, quality: 200, loop: true);

      final tmp = await getTemporaryDirectory();
      final path = '${tmp.path}/alpha_probe.webm';
      File(path).writeAsBytesSync(bytes);

      // Probe our own output with the bundled ffmpeg: an alpha WebM's stream
      // info shows alpha_mode container metadata (and yuva420p when decoded).
      final probe = await FFmpegKit.execute('-hide_banner -i $path');
      final out = await probe.getOutput() ?? '';
      // ignore: avoid_print
      print(
        'TG_WEBM_ALPHA_META:${out.contains('alpha_mode')} '
        'YUVA:${out.contains('yuva420p')}',
      );
      expect(
        out.contains('alpha_mode') || out.contains('yuva420p'),
        isTrue,
        reason: 'container/stream must signal the alpha plane',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
