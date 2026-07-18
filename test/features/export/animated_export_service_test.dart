import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/export/animated_export_service.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';

StickerProject _project(int frameCount) => StickerProject(
  id: 'p',
  name: 'Anim',
  frames: [
    for (var i = 0; i < frameCount; i++)
      Frame(
        id: 'f$i',
        layers: [
          TextLayer(id: 't$i', name: 'A', text: 'A$i', fontFamily: 'Rubik'),
        ],
      ),
  ],
);

/// Pure fake rasterizer — no dart:ui, so tests run under any async zone.
Future<RgbaFrame> _fakeRaster(Frame frame, int durationMs) async => RgbaFrame(
  bytes: Uint8List(16),
  width: 2,
  height: 2,
  durationMs: durationMs,
);

void main() {
  test(
    'routes webm specs to the webm encoder with the bitrate ladder',
    () async {
      final webm = FakeAnimationEncoder(id: 'webm', format: 'webm');
      final webp = FakeAnimationEncoder(id: 'webp');
      final service = AnimatedExportService(
        webmEncoder: webm,
        webpEncoder: webp,
        rasterizer: _fakeRaster,
      );

      final sticker = await service.encode(
        _project(4),
        AnimationSpec.telegramWebm,
      );

      expect(sticker.format, 'webm');
      expect(webm.lastFrameCount, 4, reason: 'all frames within caps');
      expect(webp.lastFrameCount, isNull, reason: 'webp encoder untouched');
      // Fake bytes = frames*quality; the first ladder rung already fits 256 KB.
      expect(sticker.byteLength, 4 * telegramBitrateLadder.first);
    },
  );

  test('routes webp specs to the webp encoder', () async {
    final webm = FakeAnimationEncoder(id: 'webm', format: 'webm');
    final webp = FakeAnimationEncoder(id: 'webp');
    final service = AnimatedExportService(
      webmEncoder: webm,
      webpEncoder: webp,
      rasterizer: _fakeRaster,
    );

    final sticker = await service.encode(
      _project(3),
      AnimationSpec.whatsappWebp,
    );

    expect(sticker.format, 'webp');
    expect(webp.lastQuality, whatsappQualityLadder.first);
  });

  test('plans frame timing: Telegram truncates past the 3 s cap', () async {
    final webm = FakeAnimationEncoder(id: 'webm', format: 'webm');
    final service = AnimatedExportService(
      webmEncoder: webm,
      webpEncoder: FakeAnimationEncoder(),
      rasterizer: _fakeRaster,
    );

    // 60 frames at 12 fps = 5 s — must be truncated to ≤3 s (36 frames).
    await service.encode(_project(60), AnimationSpec.telegramWebm);
    expect(webm.lastFrameCount, lessThanOrEqualTo(36));
  });

  test('an unavailable encoder surfaces as a StateError', () {
    final service = AnimatedExportService(
      webmEncoder: FakeAnimationEncoder(available: false),
      webpEncoder: FakeAnimationEncoder(),
      rasterizer: _fakeRaster,
    );
    expect(
      service.encode(_project(2), AnimationSpec.telegramWebm),
      throwsStateError,
    );
  });
}
