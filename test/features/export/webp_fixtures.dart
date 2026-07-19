import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';

/// Shared WhatsApp static-budget fixtures: a photo-like incompressible source
/// image and the tiny-but-valid WebP that fake lossy encoders return.

/// Writes a seeded-random opaque-RGB [edge]² PNG into [dir]. Random noise is
/// incompressible, so the lossless VP8L re-encode of a canvas painted with it
/// lands far above WhatsApp's 100 KB static cap — the case that must engage
/// the lossy quality ladder (2026-07-19 review, top finding).
File writeNoisyPng(Directory dir, {int edge = 512, int seed = 7}) {
  final rnd = Random(seed);
  final image = img.Image(width: edge, height: edge, numChannels: 4);
  for (final p in image) {
    p
      ..r = rnd.nextInt(256)
      ..g = rnd.nextInt(256)
      ..b = rnd.nextInt(256)
      ..a = 255;
  }
  return File('${dir.path}/noise_$seed.png')
    ..writeAsBytesSync(img.encodePng(image));
}

/// A frame whose single [ImageLayer] shows the (noisy) image at [assetPath],
/// centered — the shape of a real photo-cutout sticker.
Frame noisyFrame(String id, String assetPath) => Frame(
  id: '${id}_f',
  layers: [ImageLayer(id: '${id}_i', name: 'photo', assetPath: assetPath)],
);

/// A single-frame project around [noisyFrame].
StickerProject noisyProject(String id, String assetPath) =>
    StickerProject(id: id, name: id, frames: [noisyFrame(id, assetPath)]);

/// A tiny but VALID flat 512×512 WebP (a few hundred bytes) — what fake lossy
/// encoders return, so written sticker files stay decodable and assertable.
Uint8List smallValidWebp512() =>
    img.encodeWebP(img.Image(width: 512, height: 512, numChannels: 4));
