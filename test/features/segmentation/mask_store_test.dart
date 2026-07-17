import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';

Future<List<int>> _alphaChannelOf(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  final data = await frame.image.toByteData();
  final rgba = data!.buffer.asUint8List();
  return [for (var i = 3; i < rgba.length; i += 4) rgba[i]];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encodePng carries mask coverage in the alpha channel', () async {
    final mask = AlphaMask(
      width: 2,
      height: 2,
      alpha: Uint8List.fromList([0, 64, 128, 255]),
    );
    final png = await MaskStore.encodePng(mask);
    expect(await _alphaChannelOf(png), [0, 64, 128, 255]);
  });

  test('save writes a PNG into the assets dir and returns its path', () async {
    final tmp = Directory.systemTemp.createTempSync('sm_mask_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    final mask = AlphaMask.filled(3, 3, 200);
    final path = await MaskStore(baseDir: tmp).save(mask, id: 'layer42');

    final file = File(path);
    expect(file.existsSync(), isTrue);
    expect(path, contains('layer42'));
    expect(path, endsWith('.png'));
    // Round-trips to a decodable 3x3 image.
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 3);
    expect(frame.image.height, 3);
  });
}
