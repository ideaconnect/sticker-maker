import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/editor/widgets/bubble_view.dart';
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

  test('a decorative (emoji) text layer renders without error', () async {
    const frame = Frame(
      id: 'f',
      layers: [
        TextLayer(
          id: 'e',
          name: '🐶',
          text: '🐶',
          fontFamily: 'Rubik',
          fontSize: 96,
          decorative: true,
        ),
      ],
    );
    final image = await StickerRenderer.renderImage(frame, size: 128);
    expect(image.width, 128);
    expect(image.height, 128);
    image.dispose();
  });

  test('a pathologically long bubble caption never paints outside the body '
      '(#79 / WYSIWYG)', () async {
    // ~1000 characters: past what the body rect holds even at the 6 pt floor,
    // so the caption must be clamped + clipped to the body in the export path.
    final overflowing = 'overflowing caption ' * 50;
    final longFrame = Frame(
      id: 'f',
      layers: [BubbleLayer(id: 'b', name: 'B', text: overflowing)],
    );
    const emptyFrame = Frame(
      id: 'f',
      layers: [BubbleLayer(id: 'b', name: 'B', text: '')],
    );

    const sz = 512; // the default export size, used below for the pixel math
    final withText = await StickerRenderer.renderImage(longFrame);
    final empty = await StickerRenderer.renderImage(emptyFrame);
    final a = (await withText.toByteData())!.buffer.asUint8List();
    final b = (await empty.toByteData())!.buffer.asUint8List();
    withText.dispose();
    empty.dispose();

    // The bubble sits at the default canvas centre (256,256); its body (caption)
    // rect maps into the 512-px export as below. Outside this rect the only
    // thing that changes between the two frames is the caption — so if it is
    // properly clamped/clipped, every pixel there must be byte-identical.
    const scale = sz / 512.0;
    final boxOrigin =
        const Offset(256, 256) * scale -
        Offset(
          kBubbleBaseSize.width * scale / 2,
          kBubbleBaseSize.height * scale / 2,
        );
    final caption = bubbleBodyRect(kBubbleBaseSize * scale)
        .deflate(10 * scale)
        .shift(boxOrigin)
        .inflate(3); // small margin for the anti-aliased clip edge

    var diffOutside = 0;
    for (var y = 0; y < sz; y++) {
      for (var x = 0; x < sz; x++) {
        if (caption.contains(Offset(x.toDouble(), y.toDouble()))) continue;
        final i = (y * sz + x) * 4;
        if (a[i] != b[i] ||
            a[i + 1] != b[i + 1] ||
            a[i + 2] != b[i + 2] ||
            a[i + 3] != b[i + 3]) {
          diffOutside++;
        }
      }
    }
    expect(
      diffOutside,
      0,
      reason: 'the clamped caption must not paint past the bubble body rect',
    );
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
