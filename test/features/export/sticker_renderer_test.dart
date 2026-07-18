import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/sticker_renderer.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';

const _textFrame = Frame(
  id: 'f',
  layers: [TextLayer(id: 't', name: 'W', text: 'WOOF', fontFamily: 'Rubik')],
);

Future<int> _maxAlpha(ui.Image image) async {
  final data = await image.toByteData();
  final rgba = data!.buffer.asUint8List();
  var maxA = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > maxA) maxA = rgba[i];
  }
  return maxA;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders a frame to a 512x512 PNG', () async {
    final png = await StickerRenderer.renderPng(_textFrame);
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 512);
  });

  test('honours a custom target size', () async {
    final image = await StickerRenderer.renderImage(_textFrame, size: 256);
    expect(image.width, 256);
    expect(image.height, 256);
    image.dispose();
  });

  test('an empty frame renders fully transparent', () async {
    final image = await StickerRenderer.renderImage(
      const Frame(id: 'f'),
      size: 8,
    );
    expect(await _maxAlpha(image), 0);
    image.dispose();
  });

  test('a photo layer composites opaque pixels at the centre', () async {
    final tmp = Directory.systemTemp.createTempSync('sm_render_');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    // A 16x16 fully-opaque white PNG as the photo.
    final path = await MaskStore(
      baseDir: tmp,
    ).save(AlphaMask.filled(16, 16, 255));

    final frame = Frame(
      id: 'f',
      layers: [ImageLayer(id: 'i', name: 'Photo', assetPath: path)],
    );
    final image = await StickerRenderer.renderImage(frame, size: 64);
    final data = await image.toByteData();
    final rgba = data!.buffer.asUint8List();
    // Centre pixel (32,32) sits inside the fitted photo box → opaque.
    const centre = (32 * 64 + 32) * 4;
    expect(rgba[centre + 3], greaterThan(0), reason: 'centre is opaque');
    image.dispose();
  });
}
