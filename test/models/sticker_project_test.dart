import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/image_adjustments.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/layer_transform.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';

/// Encodes a value to JSON text and back, exercising the real string boundary.
Map<String, dynamic> jsonRoundTrip(Map<String, dynamic> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, dynamic>();

void main() {
  group('LayerTransform', () {
    test('round-trips through JSON', () {
      const t = LayerTransform(
        position: Offset(120, 340),
        scale: 1.5,
        rotation: -0.25,
      );
      expect(LayerTransform.fromJson(jsonRoundTrip(t.toJson())), t);
    });

    test('copyWith overrides only given fields', () {
      const t = LayerTransform();
      expect(t.copyWith(scale: 2).scale, 2);
      expect(t.copyWith(scale: 2).position, t.position);
    });
  });

  group('ImageAdjustments', () {
    test('identity and round-trip', () {
      expect(ImageAdjustments.identity.isIdentity, isTrue);
      const a = ImageAdjustments(
        brightness: 1.2,
        contrast: 0.8,
        saturation: 1.4,
        hue: -30,
      );
      expect(a.isIdentity, isFalse);
      expect(ImageAdjustments.fromJson(jsonRoundTrip(a.toJson())), a);
    });

    test('fromJson tolerates missing keys', () {
      expect(ImageAdjustments.fromJson(const {}), ImageAdjustments.identity);
    });
  });

  group('ImageLayer', () {
    test('round-trips with mask and adjustments', () {
      const layer = ImageLayer(
        id: 'l1',
        name: 'Rex',
        assetPath: 'assets/rex.png',
        maskPath: 'assets/rex.mask.png',
        transform: LayerTransform(position: Offset(200, 200), scale: 1.1),
        opacity: 0.9,
        adjustments: ImageAdjustments(brightness: 1.1),
      );
      final decoded = Layer.fromJson(jsonRoundTrip(layer.toJson()));
      expect(decoded, isA<ImageLayer>());
      expect(decoded, layer);
    });

    test('copyWith can clear the mask', () {
      const layer = ImageLayer(
        id: 'l1',
        name: 'Rex',
        assetPath: 'a.png',
        maskPath: 'a.mask.png',
      );
      expect(layer.copyWith(clearMask: true).maskPath, isNull);
      expect(layer.copyWith(name: 'Dog').maskPath, 'a.mask.png');
    });
  });

  group('TextLayer', () {
    test('round-trips including color', () {
      const layer = TextLayer(
        id: 't1',
        name: 'Caption',
        text: 'WOOF!',
        fontFamily: 'Bangers',
        fontSize: 48,
        color: Color(0xFF34D399),
      );
      final decoded = Layer.fromJson(jsonRoundTrip(layer.toJson()));
      expect(decoded, isA<TextLayer>());
      expect(decoded, layer);
    });
  });

  test('Layer.fromJson throws on unknown type', () {
    expect(
      () => Layer.fromJson(const {'type': 'bubble'}),
      throwsA(isA<FormatException>()),
    );
  });

  group('Frame', () {
    test('round-trips a mixed layer list preserving order', () {
      const frame = Frame(
        id: 'f0',
        layers: [
          ImageLayer(id: 'i', name: 'Photo', assetPath: 'p.png'),
          TextLayer(id: 't', name: 'Cap', text: 'Hi', fontFamily: 'Rubik'),
        ],
      );
      final decoded = Frame.fromJson(jsonRoundTrip(frame.toJson()));
      expect(decoded, frame);
      expect(decoded.layers.first, isA<ImageLayer>());
      expect(decoded.layers.last, isA<TextLayer>());
    });
  });

  group('StickerProject', () {
    StickerProject sample() => StickerProject(
      id: 'p1',
      name: 'Rex woof',
      currentFrameIndex: 1,
      createdAt: DateTime.utc(2026, 7, 17, 10),
      updatedAt: DateTime.utc(2026, 7, 17, 11),
      frames: const [
        Frame(
          id: 'f0',
          layers: [ImageLayer(id: 'i', name: 'Photo', assetPath: 'p.png')],
        ),
        Frame(id: 'f1'),
      ],
    );

    test('round-trips through JSON', () {
      final p = sample();
      final decoded = StickerProject.fromJson(jsonRoundTrip(p.toJson()));
      expect(decoded, p);
    });

    test('writes the current schema version', () {
      expect(sample().toJson()['version'], StickerProject.schemaVersion);
    });

    test('derived properties', () {
      final p = sample();
      expect(p.isAnimated, isTrue);
      expect(p.frameCount, 2);
      expect(p.safeFrameIndex, 1);
      expect(p.layerCount, 0); // current frame (index 1) is empty
      expect(p.currentFrame.id, 'f1');
    });

    test('safeFrameIndex clamps an out-of-range index', () {
      final p = sample().copyWith(currentFrameIndex: 99);
      expect(p.safeFrameIndex, 1);
      expect(() => p.currentFrame, returnsNormally);
    });

    test('empty() has one empty frame and is static', () {
      final p = StickerProject.empty(id: 'x');
      expect(p.frameCount, 1);
      expect(p.isAnimated, isFalse);
      expect(p.layerCount, 0);
    });

    test('rejects a manifest newer than the supported schema', () {
      final future = sample().toJson()
        ..['version'] = StickerProject.schemaVersion + 1;
      expect(
        () => StickerProject.fromJson(jsonRoundTrip(future)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
