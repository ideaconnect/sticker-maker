import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/export/sticker_renderer.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';

/// A [side]×[side] mask whose centred [sq]×[sq] square is fully opaque (the
/// "subject"), transparent elsewhere.
AlphaMask _centeredSquare(int side, int sq) {
  final a = Uint8List(side * side);
  final lo = (side - sq) ~/ 2;
  final hi = lo + sq;
  for (var y = 0; y < side; y++) {
    for (var x = 0; x < side; x++) {
      if (x >= lo && x < hi && y >= lo && y < hi) a[y * side + x] = 255;
    }
  }
  return AlphaMask(width: side, height: side, alpha: a);
}

Future<int> _opaqueCount(ui.Image image) async {
  final data = await image.toByteData();
  final rgba = data!.buffer.asUint8List();
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 0) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late String basePath;
  late String maskPath;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('sm_outline_');
    final store = MaskStore(baseDir: tmp);
    // Opaque white "photo" + a centred-square cut-out mask.
    basePath = await store.save(AlphaMask.filled(64, 64, 255), id: 'base');
    maskPath = await store.save(_centeredSquare(64, 24), id: 'mask');
  });
  tearDown(() {
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Frame buildFrame({required double outline, int color = 0xFFFFFFFF}) => Frame(
    id: 'f',
    layers: [
      ImageLayer(
        id: 'i',
        name: 'p',
        assetPath: basePath,
        maskPath: maskPath,
        outlineWidth: outline,
        outlineColor: ui.Color(color),
      ),
    ],
  );

  test('a die-cut outline adds a ring of pixels around the subject', () async {
    final plain = await StickerRenderer.renderImage(
      buildFrame(outline: 0),
      size: 128,
    );
    final outlined = await StickerRenderer.renderImage(
      buildFrame(outline: 24),
      size: 128,
    );
    final plainOpaque = await _opaqueCount(plain);
    final outlinedOpaque = await _opaqueCount(outlined);

    expect(plainOpaque, greaterThan(0), reason: 'subject renders');
    expect(
      outlinedOpaque,
      greaterThan(plainOpaque),
      reason: 'the outline grows the opaque silhouette',
    );
    plain.dispose();
    outlined.dispose();
  });

  test('the ring uses the configured outline color', () async {
    final plain = await StickerRenderer.renderImage(
      buildFrame(outline: 0),
      size: 128,
    );
    // A red outline so ring pixels are unambiguous.
    final red = await StickerRenderer.renderImage(
      buildFrame(outline: 24, color: 0xFFFF0000),
      size: 128,
    );
    final plainRgba = (await plain.toByteData())!.buffer.asUint8List();
    final redRgba = (await red.toByteData())!.buffer.asUint8List();

    // Find a pixel that is opaque only in the outlined render (i.e. on the ring).
    var found = false;
    for (var i = 0; i < redRgba.length; i += 4) {
      if (redRgba[i + 3] > 200 && plainRgba[i + 3] == 0) {
        expect(redRgba[i], greaterThan(180), reason: 'ring is red (R)');
        expect(redRgba[i + 1], lessThan(80), reason: 'ring is red (G)');
        expect(redRgba[i + 2], lessThan(80), reason: 'ring is red (B)');
        found = true;
        break;
      }
    }
    expect(found, isTrue, reason: 'a ring pixel exists outside the subject');
    plain.dispose();
    red.dispose();
  });
}
