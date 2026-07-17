import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/editor/mask_mapper.dart';

void main() {
  group('MaskMapper.canvasToMask', () {
    test('identity: canvas centre maps to image centre', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 440), // fills the 440 box exactly
        position: Offset(256, 256),
        layerScale: 1,
        rotation: 0,
      );
      expect(
        mapper.canvasToMask(const Offset(256, 256)),
        const Offset(220, 220),
      );
    });

    test('a point off the layer box returns null', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 440),
        position: Offset(256, 256),
        layerScale: 1,
        rotation: 0,
      );
      // Far outside the 440 box centred at 256.
      expect(mapper.canvasToMask(const Offset(0, 0)), isNull);
    });

    test('letterbox of a wide image maps vertical padding to null', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 220), // wide -> letterboxed top/bottom in the box
        position: Offset(256, 256),
        layerScale: 1,
        rotation: 0,
      );
      // Centre still lands mid-image.
      expect(
        mapper.canvasToMask(const Offset(256, 256)),
        const Offset(220, 110),
      );
      // The 220-tall photo occupies canvas-y [146, 366]; y=130 is in the top
      // letterbox, above the photo.
      expect(mapper.canvasToMask(const Offset(256, 130)), isNull);
    });

    test('layer scale zooms the mapping', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 440),
        position: Offset(256, 256),
        layerScale: 2, // the photo is drawn twice as large
        rotation: 0,
      );
      // A canvas point 220 logical right of centre is only half-way (110 box
      // units) into the scaled photo -> image x = 330.
      expect(
        mapper.canvasToMask(const Offset(476, 256))!.dx,
        closeTo(330, 0.001),
      );
    });

    test('rotation is inverted', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 440),
        position: Offset(256, 256),
        layerScale: 1,
        rotation: math.pi / 2, // 90°
      );
      // A point 100 logical to the right of centre, with the layer rotated 90°,
      // came from 100 *below* centre in the image's own frame.
      final p = mapper.canvasToMask(const Offset(356, 256))!;
      expect(p.dx, closeTo(220, 0.001));
      expect(p.dy, closeTo(120, 0.001));
    });
  });

  group('MaskMapper.radiusToMask', () {
    test('identity radius is unchanged', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 440),
        position: Offset(256, 256),
        layerScale: 1,
        rotation: 0,
      );
      expect(mapper.radiusToMask(20), closeTo(20, 0.001));
    });

    test('a scaled-up layer shrinks the radius in mask pixels', () {
      const mapper = MaskMapper(
        imageSize: Size(440, 440),
        position: Offset(256, 256),
        layerScale: 2,
        rotation: 0,
      );
      expect(mapper.radiusToMask(20), closeTo(10, 0.001));
    });

    test('a high-res image enlarges the radius in mask pixels', () {
      const mapper = MaskMapper(
        imageSize: Size(880, 880), // contain scale 0.5 -> box->image factor 2
        position: Offset(256, 256),
        layerScale: 1,
        rotation: 0,
      );
      expect(mapper.radiusToMask(20), closeTo(40, 0.001));
    });
  });
}
