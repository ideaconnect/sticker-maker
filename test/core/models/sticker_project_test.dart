import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';

void main() {
  StickerProject base({double? fps}) => StickerProject(
    id: 'p',
    name: 'P',
    frames: const [
      Frame(id: 'f0'),
      Frame(id: 'f1'),
    ],
    fps: fps ?? StickerProject.defaultFps,
  );

  group('StickerProject.fps', () {
    test('defaults to defaultFps', () {
      expect(StickerProject.empty(id: 'x').fps, StickerProject.defaultFps);
      expect(base().fps, 8);
    });

    test('survives a JSON round-trip', () {
      final restored = StickerProject.fromJson(base(fps: 0.5).toJson());
      expect(restored.fps, 0.5);
    });

    test('pre-fps manifests (no fps key) default to defaultFps', () {
      final json = base().toJson()..remove('fps');
      expect(StickerProject.fromJson(json).fps, StickerProject.defaultFps);
    });

    test('out-of-range persisted fps is clamped on load', () {
      final tooFast = base().toJson()..['fps'] = 999.0;
      expect(StickerProject.fromJson(tooFast).fps, StickerProject.maxFps);
      final tooSlow = base().toJson()..['fps'] = 0.001;
      expect(StickerProject.fromJson(tooSlow).fps, StickerProject.minFps);
    });

    test('copyWith replaces fps and leaves it otherwise untouched', () {
      expect(base(fps: 8).copyWith(fps: 2).fps, 2);
      expect(base(fps: 2).copyWith(name: 'Q').fps, 2);
    });

    test('fps participates in equality', () {
      expect(base(fps: 2), isNot(base(fps: 4)));
      expect(base(fps: 2), base(fps: 2));
    });
  });
}
