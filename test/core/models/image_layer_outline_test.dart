import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/layer.dart';

void main() {
  group('ImageLayer die-cut outline', () {
    const layer = ImageLayer(id: 'i', name: 'p', assetPath: 'a.png');

    test('defaults to no outline (white)', () {
      expect(layer.outlineWidth, 0);
      expect(layer.hasOutline, isFalse);
      expect(layer.outlineColor, const Color(0xFFFFFFFF));
    });

    test('copyWith sets width and color', () {
      final o = layer.copyWith(
        outlineWidth: 12,
        outlineColor: const Color(0xFF00FF00),
      );
      expect(o.outlineWidth, 12);
      expect(o.hasOutline, isTrue);
      expect(o.outlineColor, const Color(0xFF00FF00));
    });

    test('JSON round-trips the outline', () {
      final o = layer.copyWith(
        outlineWidth: 20,
        outlineColor: const Color(0xFF123456),
        maskPath: 'm.png',
      );
      final restored = ImageLayer.fromJson(o.toJson());
      expect(restored.outlineWidth, 20);
      expect(restored.outlineColor, const Color(0xFF123456));
      expect(restored, o);
    });

    test('legacy JSON without outline keys defaults to off', () {
      final json = {
        'type': 'image',
        'id': 'i',
        'name': 'p',
        'transform': layer.transform.toJson(),
        'visible': true,
        'opacity': 1.0,
        'assetPath': 'a.png',
        'maskPath': null,
        'adjustments': const <String, dynamic>{},
      };
      final restored = ImageLayer.fromJson(json);
      expect(restored.outlineWidth, 0);
      expect(restored.outlineColor, const Color(0xFFFFFFFF));
    });

    test('== distinguishes outline width and color', () {
      expect(layer == layer.copyWith(outlineWidth: 5), isFalse);
      expect(
        layer == layer.copyWith(outlineColor: const Color(0xFF000000)),
        isFalse,
      );
    });
  });
}
