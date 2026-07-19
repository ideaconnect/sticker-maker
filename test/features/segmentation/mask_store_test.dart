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

/// Writes an [AlphaMask] to a real PNG at [dir]/[name] and returns its path.
Future<String> _writePng(Directory dir, String name, AlphaMask mask) async {
  final bytes = await MaskStore.encodePng(mask);
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes);
  return path;
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

  test('decodeImageSize reads a real PNG header for a non-square, larger '
      'fixture', () async {
    final tmp = Directory.systemTemp.createTempSync('sm_mask_hdr_');
    addTearDown(() {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {}
    });
    // A non-square fixture pins width/height ordering; the header path
    // (ui.ImageDescriptor) returns dimensions without decoding the bitmap.
    // (A truncated-after-header discriminator isn't feasible here:
    // ImageDescriptor.encoded validates the whole encoded stream.)
    final path = await _writePng(
      tmp,
      'mask.png',
      AlphaMask.filled(40, 24, 255),
    );
    final size = await MaskStore.decodeImageSize(path);
    expect(size.width, 40);
    expect(size.height, 24);
  });

  test(
    'deleteMask removes a mask file, and is a no-op when already gone',
    () async {
      final tmp = Directory.systemTemp.createTempSync('sm_mask_del_');
      addTearDown(() {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final store = MaskStore(baseDir: tmp);
      final path = await store.save(AlphaMask.filled(3, 3, 255), id: 'gone');
      expect(File(path).existsSync(), isTrue);

      await store.deleteMask(path);
      expect(File(path).existsSync(), isFalse);
      // Deleting a missing file must not throw.
      await store.deleteMask(path);
      await store.deleteMask('${tmp.path}/never_existed.png');
    },
  );

  group('SupersededMaskCollector', () {
    test('deletes a superseded mask only once it is unreachable', () async {
      final tmp = Directory.systemTemp.createTempSync('sm_mask_gc_');
      addTearDown(() {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final store = MaskStore(baseDir: tmp);
      // p0 is the mask a later stroke (p1) supersedes. Distinct explicit paths
      // (real save() timestamps could collide within a microsecond).
      final p0 = await _writePng(
        tmp,
        'mask_a_0.png',
        AlphaMask.filled(2, 2, 9),
      );
      final p1 = await _writePng(
        tmp,
        'mask_a_1.png',
        AlphaMask.filled(2, 2, 9),
      );

      final gc = SupersededMaskCollector(store);
      gc.supersede(p0, p1);
      expect(gc.pending, contains(p0));

      // Still undo-reachable → kept, and stays queued for a later pass.
      await gc.collect((path) => true);
      expect(File(p0).existsSync(), isTrue);
      expect(gc.pending, contains(p0));

      // Now unreachable → the file is reclaimed and forgotten.
      await gc.collect((path) => false);
      expect(File(p0).existsSync(), isFalse);
      expect(gc.pending, isEmpty);
      // The current mask (never superseded) is untouched throughout.
      expect(File(p1).existsSync(), isTrue);
    });

    test('ignores a null or unchanged previous path', () async {
      final tmp = Directory.systemTemp.createTempSync('sm_mask_gc2_');
      addTearDown(() {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {}
      });
      final store = MaskStore(baseDir: tmp);
      final p = await _writePng(tmp, 'mask_a.png', AlphaMask.filled(2, 2, 9));
      final gc = SupersededMaskCollector(store)
        ..supersede(null, p) // first-ever mask: nothing to reclaim
        ..supersede(p, p); // same path re-saved: never delete the live one
      expect(gc.pending, isEmpty);
      await gc.collect((path) => false);
      expect(File(p).existsSync(), isTrue);
    });
  });
}
