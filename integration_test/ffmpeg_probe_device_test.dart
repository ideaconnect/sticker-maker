// ANIM-1 (#66) device smoke test: proves the bundled ffmpeg-kit "video" build
// actually provides both animated-sticker encoders on real hardware —
//   * libvpx-vp9 with yuva420p (WebM VP9 + alpha, Telegram), and
//   * libwebp_anim (animated WebP, WhatsApp) — the one item research flagged
//     as UNCERTAIN until tested on-device.
//
//   flutter test integration_test/ffmpeg_probe_device_test.dart -d <device>

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

/// Writes [n] tiny transparent PNG frames (moving opaque square) to [dir],
/// named 1.png…n.png as an ffmpeg `%d.png` sequence.
Future<void> _writeFrames(Directory dir, int n) async {
  for (var i = 1; i <= n; i++) {
    final im = img.Image(width: 64, height: 64, numChannels: 4);
    img.fillRect(
      im,
      x1: 8 * i,
      y1: 8 * i,
      x2: 8 * i + 20,
      y2: 8 * i + 20,
      color: img.ColorRgba8(255, 64, 129, 255),
    );
    File('${dir.path}/$i.png').writeAsBytesSync(img.encodePng(im));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ffmpeg build ships libvpx-vp9 and libwebp_anim encoders', (
    tester,
  ) async {
    final session = await FFmpegKit.execute('-hide_banner -encoders');
    expect(ReturnCode.isSuccess(await session.getReturnCode()), isTrue);
    final out = await session.getOutput() ?? '';
    // ignore: avoid_print
    print('FFMPEG_HAS_VP9:${out.contains('libvpx-vp9')}');
    // ignore: avoid_print
    print('FFMPEG_HAS_WEBP_ANIM:${out.contains('libwebp_anim')}');
    expect(out, contains('libvpx-vp9'), reason: 'VP9 encoder must be present');
    expect(
      out,
      contains('libwebp_anim'),
      reason: 'animated WebP encoder must be present',
    );
  });

  testWidgets('encodes a transparent WebM VP9 (alpha) from PNG frames', (
    tester,
  ) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/ffprobe_webm')
      ..createSync(recursive: true);
    await _writeFrames(dir, 3);
    final outPath = '${dir.path}/out.webm';

    final session = await FFmpegKit.execute(
      '-y -framerate 10 -i ${dir.path}/%d.png '
      '-c:v libvpx-vp9 -pix_fmt yuva420p -b:v 100K -an $outPath',
    );
    final rc = await session.getReturnCode();
    expect(
      ReturnCode.isSuccess(rc),
      isTrue,
      reason: 'webm encode failed: ${await session.getOutput()}',
    );

    final bytes = File(outPath).readAsBytesSync();
    // ignore: avoid_print
    print('FFMPEG_WEBM_BYTES:${bytes.length}');
    // EBML magic — a real Matroska/WebM container.
    expect(bytes.sublist(0, 4), [0x1A, 0x45, 0xDF, 0xA3]);
    expect(bytes.length, greaterThan(200));
  });

  testWidgets('encodes an animated WebP with alpha from PNG frames', (
    tester,
  ) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/ffprobe_webp')
      ..createSync(recursive: true);
    await _writeFrames(dir, 3);
    final outPath = '${dir.path}/out.webp';

    final session = await FFmpegKit.execute(
      '-y -framerate 10 -i ${dir.path}/%d.png '
      '-c:v libwebp_anim -lossless 0 -q:v 70 -loop 0 $outPath',
    );
    final rc = await session.getReturnCode();
    expect(
      ReturnCode.isSuccess(rc),
      isTrue,
      reason: 'webp encode failed: ${await session.getOutput()}',
    );

    final bytes = File(outPath).readAsBytesSync();
    // ignore: avoid_print
    print('FFMPEG_ANIMWEBP_BYTES:${bytes.length}');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WEBP');

    final decoded = img.decodeWebP(bytes);
    expect(decoded, isNotNull);
    // ignore: avoid_print
    print('FFMPEG_ANIMWEBP_FRAMES:${decoded!.numFrames}');
    expect(decoded.numFrames, 3, reason: 'must be a real 3-frame animation');
  });
}
