import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'alpha_mask.dart';

/// Persists an [AlphaMask] to disk as a PNG so it can back an
/// [ImageLayer.maskPath] non-destructively (the original photo is untouched).
///
/// The PNG carries the coverage in its **alpha channel** (RGB left white), which
/// makes render-time compositing a single `BlendMode.dstIn` draw — see
/// `StickerCanvas`.
class MaskStore {
  MaskStore({this.baseDir});

  /// Overridable in tests; defaults to the app documents directory.
  final Directory? baseDir;

  int _stamp() => DateTime.now().microsecondsSinceEpoch;

  Future<Directory> _assetsDir() async {
    final base = baseDir ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/projects/assets');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Encodes [mask] and writes it into the project assets. [id] (a layer id)
  /// keeps the filename stable/greppable; a timestamp keeps successive cut-outs
  /// of the same layer distinct so the canvas image cache reloads.
  Future<String> save(AlphaMask mask, {String? id}) async {
    final png = await encodePng(mask);
    final dir = await _assetsDir();
    final tag = id == null ? '${_stamp()}' : '${id}_${_stamp()}';
    final dest = '${dir.path}/mask_$tag.png';
    await File(dest).writeAsBytes(png);
    return dest;
  }

  /// Loads a mask PNG back into an [AlphaMask] (reads its alpha channel).
  Future<AlphaMask> load(String path) async =>
      decodeAlpha(await File(path).readAsBytes());

  /// Decodes mask PNG [bytes] into an [AlphaMask].
  static Future<AlphaMask> decodeAlpha(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData();
    final w = image.width;
    final h = image.height;
    image.dispose();
    codec.dispose();
    if (data == null) throw StateError('failed to decode mask PNG');
    final rgba = data.buffer.asUint8List();
    final alpha = Uint8List(w * h);
    for (var i = 0; i < w * h; i++) {
      alpha[i] = rgba[i * 4 + 3];
    }
    return AlphaMask(width: w, height: h, alpha: alpha);
  }

  /// Decodes just the pixel dimensions of the image at [path].
  static Future<ui.Size> decodeImageSize(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    return size;
  }

  /// Converts an [AlphaMask] to PNG bytes: opaque white pixels whose alpha is
  /// the mask coverage. Uses `dart:ui`, so it runs on-device / in the test
  /// engine (not in a bare Dart VM).
  static Future<Uint8List> encodePng(AlphaMask mask) async {
    final rgba = Uint8List(mask.length * 4);
    for (var i = 0; i < mask.length; i++) {
      final o = i * 4;
      rgba[o] = 255;
      rgba[o + 1] = 255;
      rgba[o + 2] = 255;
      rgba[o + 3] = mask.alpha[i];
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      mask.width,
      mask.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw StateError('failed to encode mask PNG');
    }
    return data.buffer.asUint8List();
  }
}

final maskStoreProvider = Provider<MaskStore>((ref) => MaskStore());
