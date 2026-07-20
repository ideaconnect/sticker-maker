import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/export/animation_encoder.dart';
import 'package:sticker_maker/features/export/sticker_encoder.dart';

void main() {
  group('AnimationSpec presets', () {
    test('WhatsApp WebP caps', () {
      const s = AnimationSpec.whatsappWebp;
      expect(s.format, 'webp');
      expect(s.maxBytes, 500 * 1024);
      expect(s.maxSeconds, 10);
      expect(s.minFrameMs, 8);
    });

    test('Telegram WebM caps', () {
      const s = AnimationSpec.telegramWebm;
      expect(s.format, 'webm');
      expect(s.maxBytes, 256 * 1024);
      expect(s.maxSeconds, 3);
      expect(s.maxFps, 30);
    });
  });

  group('AnimationPlanner.plan', () {
    test('caps fps to the spec maximum', () {
      final plan = AnimationPlanner.plan(10, 60, AnimationSpec.telegramWebm);
      // 60 fps clamped to 30 → 33 ms/frame.
      expect(plan.frameDurationMs, 33);
    });

    test('truncates to the max duration by keeping the leading frames', () {
      // 100 frames at 30 fps = 3.3 s, but Telegram caps at 3 s.
      final plan = AnimationPlanner.plan(100, 30, AnimationSpec.telegramWebm);
      expect(plan.totalSeconds, lessThanOrEqualTo(3.0));
      expect(plan.frameCount, lessThan(100));
      expect(plan.frameIndices.first, 0);
    });

    test('keeps every frame when within the caps', () {
      final plan = AnimationPlanner.plan(12, 8, AnimationSpec.whatsappWebp);
      expect(plan.frameCount, 12);
    });

    test('honours the WebP minimum frame duration', () {
      // 200 fps would be 5 ms; WhatsApp floors frames at 8 ms.
      final plan = AnimationPlanner.plan(4, 200, AnimationSpec.whatsappWebp);
      expect(plan.frameDurationMs, greaterThanOrEqualTo(8));
    });

    test('sub-1 fps is floored at 1 fps (1 s/frame)', () {
      // Sub-1 rates can't be represented by the targets: at 0.25 fps a single
      // frame would already run 4 s, past Telegram's 3 s cap, and the "slow
      // motion" would collapse to one still. The floor keeps them animated.
      final plan = AnimationPlanner.plan(2, 0.25, AnimationSpec.whatsappWebp);
      expect(plan.frameDurationMs, 1000);
      expect(plan.frameCount, 2);
    });

    test('1 fps still fits Telegram: 3 frames inside the 3 s cap', () {
      final plan = AnimationPlanner.plan(4, 1, AnimationSpec.telegramWebm);
      expect(plan.frameDurationMs, 1000);
      expect(plan.frameCount, 3);
      expect(plan.totalSeconds, lessThanOrEqualTo(3.0));
    });
  });

  group('encoder seam + budget search', () {
    test(
      'FakeAnimationEncoder records the call and returns sized bytes',
      () async {
        final enc = FakeAnimationEncoder();
        final bytes = await enc.encode(
          [
            RgbaFrame(
              bytes: Uint8List(16),
              width: 2,
              height: 2,
              durationMs: 40,
            ),
            RgbaFrame(
              bytes: Uint8List(16),
              width: 2,
              height: 2,
              durationMs: 40,
            ),
          ],
          quality: 50,
          loop: true,
        );
        expect(enc.lastFrameCount, 2);
        expect(enc.lastQuality, 50);
        expect(bytes.length, 2 * 50);
      },
    );

    test('fitToBudget bisects the quality knob to meet the byte cap', () async {
      // Fake bytes scale with quality; reuse the shared budget search.
      final enc = FakeAnimationEncoder();
      final frames = [
        RgbaFrame(bytes: Uint8List(16), width: 2, height: 2, durationMs: 40),
      ];
      final chosen = await StickerEncoder.fitToBudget(
        (quality) => enc.encode(frames, quality: quality, loop: true),
        maxBytes: 60,
        sizes: const [90, 70, 50, 30], // 'sizes' reused as quality candidates
      );
      // 90 and 70 exceed 60; 50 fits (1 frame * 50 = 50 bytes).
      expect(chosen.size, 50);
      expect(chosen.bytes.length, lessThanOrEqualTo(60));
    });
  });
}
