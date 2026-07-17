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

  test('save then load round-trips the mask coverage exactly', () async {
    final tmp = Directory.systemTemp.createTempSync('sm_mask_rt_');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final mask = AlphaMask(
      width: 4,
      height: 2,
      alpha: Uint8List.fromList([0, 32, 64, 96, 128, 160, 200, 255]),
    );
    final store = MaskStore(baseDir: tmp);
    final loaded = await store.load(await store.save(mask, id: 'rt'));

    expect(loaded.width, 4);
    expect(loaded.height, 2);
    expect(loaded.alpha, mask.alpha);
  });

  test('decodeImageSize reads dimensions without full decode work', () async {
    final tmp = Directory.systemTemp.createTempSync('sm_mask_sz_');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final path = await MaskStore(
      baseDir: tmp,
    ).save(AlphaMask.filled(7, 5, 255));
    final size = await MaskStore.decodeImageSize(path);
    expect(size.width, 7);
    expect(size.height, 5);
  });
}
