import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/image_adjustments.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/layer_transform.dart';
import 'package:sticker_maker/features/editor/widgets/sticker_canvas.dart';
import 'package:sticker_maker/features/export/sticker_renderer.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';

// ---------------------------------------------------------------- PNG fixtures

/// Encodes [w]×[h] straight-alpha [rgba] bytes to a PNG file on [dir]. Uses
/// `dart:ui`, so the caller must be inside an async test / `runAsync`.
Future<String> _writePng(
  Directory dir,
  String name,
  int w,
  int h,
  Uint8List rgba,
) async {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    w,
    h,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  final image = await completer.future;
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file.path;
}

/// A solid [w]×[h] image, every pixel [color] (with its alpha).
Future<String> _writeSolid(
  Directory dir,
  String name,
  int w,
  int h,
  Color color,
) {
  final rgba = Uint8List(w * h * 4);
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  final a = (color.a * 255).round();
  for (var i = 0; i < w * h; i++) {
    final o = i * 4;
    rgba[o] = r;
    rgba[o + 1] = g;
    rgba[o + 2] = b;
    rgba[o + 3] = a;
  }
  return _writePng(dir, name, w, h, rgba);
}

// ---------------------------------------------------------------- pixel access

int _alpha(ByteData data, int size, int x, int y) =>
    data.getUint8((y * size + x) * 4 + 3);

int _channel(ByteData data, int size, int x, int y, int c) =>
    data.getUint8((y * size + x) * 4 + c);

Future<ByteData> _bytes(ui.Image image) async {
  final data = await image.toByteData();
  return data!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_parity_'));
  tearDown(() {
    // On Windows a just-decoded PNG can stay briefly locked; the OS reaps temp.
    imageCache.clear();
    imageCache.clearLiveImages();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  // -------------------------------------------------------- transform math
  //
  // A wide (4:1) opaque strip fitted into the square box becomes a horizontal
  // band; the layer's rotation (π/2) turns it VERTICAL and its scale (2) sets
  // the band's width. Sampling inside/outside the band pins the full
  // position*scale → rotate → scale pipeline at two output sizes.
  test('renderer pins the position*scale → rotate → scale transform', () async {
    final path = await _writeSolid(
      tmp,
      'strip.png',
      40,
      10,
      const Color(0xFFFF3050),
    );
    final frame = Frame(
      id: 'f',
      layers: [
        ImageLayer(
          id: 'i',
          name: 'strip',
          assetPath: path,
          transform: const LayerTransform(
            position: Offset(200, 300),
            scale: 2,
            rotation: math.pi / 2,
          ),
        ),
      ],
    );

    // At size 512 (canvas scale 1) the band is vertical, x ∈ [90, 310], full y.
    final img512 = await StickerRenderer.renderImage(frame);
    final d512 = await _bytes(img512);
    expect(_alpha(d512, 512, 200, 40), greaterThan(200), reason: 'band top');
    expect(
      _alpha(d512, 512, 200, 480),
      greaterThan(200),
      reason: 'band bottom',
    );
    expect(_alpha(d512, 512, 200, 300), greaterThan(200), reason: 'centre');
    // Only opaque here because scale=2 widened the band past x=145 (scale=1).
    expect(
      _alpha(d512, 512, 110, 300),
      greaterThan(200),
      reason: 'scale widens',
    );
    // Outside the vertical band → transparent (opaque only if rotation ignored).
    expect(_alpha(d512, 512, 40, 300), lessThan(50), reason: 'left of band');
    expect(_alpha(d512, 512, 470, 300), lessThan(50), reason: 'right of band');
    img512.dispose();

    // At tray size 96 everything scales by 96/512: band x ∈ [~17, ~58].
    final img96 = await StickerRenderer.renderImage(frame, size: 96);
    final d96 = await _bytes(img96);
    expect(_alpha(d96, 96, 37, 10), greaterThan(200), reason: 'tray band top');
    expect(
      _alpha(d96, 96, 37, 90),
      greaterThan(200),
      reason: 'tray band bottom',
    );
    expect(_alpha(d96, 96, 5, 48), lessThan(50), reason: 'tray left of band');
    expect(_alpha(d96, 96, 80, 48), lessThan(50), reason: 'tray right of band');
    img96.dispose();
  });

  // -------------------------------------------------------- opacity fade
  test('renderer renders an opacity:0.5 layer at ~half alpha', () async {
    final path = await _writeSolid(
      tmp,
      'solid.png',
      32,
      32,
      const Color(0xFFFFFFFF),
    );
    Frame frameAt(double opacity) => Frame(
      id: 'f',
      layers: [
        ImageLayer(id: 'i', name: 's', assetPath: path, opacity: opacity),
      ],
    );

    final full = await StickerRenderer.renderImage(frameAt(1.0), size: 64);
    final half = await StickerRenderer.renderImage(frameAt(0.5), size: 64);
    final fa = _alpha(await _bytes(full), 64, 32, 32);
    final ha = _alpha(await _bytes(half), 64, 32, 32);
    expect(fa, greaterThan(240), reason: 'opaque at opacity 1');
    expect(ha, inInclusiveRange(108, 148), reason: '~128 at opacity 0.5');
    full.dispose();
    half.dispose();
  });

  // -------------------------------------------------------- ImageAdjustments
  test('renderer applies ImageAdjustments on the export path', () async {
    // Mid-grey 128; brightness 0.5 multiplies RGB → ~64, alpha untouched.
    final path = await _writeSolid(
      tmp,
      'grey.png',
      32,
      32,
      const Color(0xFF808080),
    );
    Frame frameWith(ImageAdjustments adj) => Frame(
      id: 'f',
      layers: [
        ImageLayer(id: 'i', name: 'g', assetPath: path, adjustments: adj),
      ],
    );

    final plain = await StickerRenderer.renderImage(
      frameWith(ImageAdjustments.identity),
      size: 64,
    );
    final dark = await StickerRenderer.renderImage(
      frameWith(const ImageAdjustments(brightness: 0.5)),
      size: 64,
    );
    final dp = await _bytes(plain);
    final dd = await _bytes(dark);
    expect(
      _channel(dp, 64, 32, 32, 0),
      inInclusiveRange(118, 138),
      reason: 'grey unchanged at identity',
    );
    expect(
      _channel(dd, 64, 32, 32, 0),
      inInclusiveRange(50, 78),
      reason: 'brightness 0.5 halves the channel',
    );
    expect(
      _alpha(dd, 64, 32, 32),
      greaterThan(240),
      reason: 'brightness leaves alpha opaque',
    );
    plain.dispose();
    dark.dispose();
  });

  // -------------------------------------------------------- canvas ↔ export
  testWidgets('StickerCanvas and StickerRenderer agree on a mixed frame', (
    tester,
  ) async {
    const key = ValueKey('parity-canvas');
    const size = 512;

    late String base;
    late String mask;
    await tester.runAsync(() async {
      base = await _writeSolid(
        tmp,
        'photo.png',
        24,
        24,
        const Color(0xFF2FB3A8),
      );
      mask = await MaskStore(baseDir: tmp).save(AlphaMask.filled(24, 24, 255));
    });

    // Off-centre image (scale 1.4 + rotation) at the bottom of the z-order, with
    // a bubble above it and a caption below — the three layer kinds at once.
    final frame = Frame(
      id: 'f',
      layers: [
        ImageLayer(
          id: 'img',
          name: 'photo',
          assetPath: base,
          maskPath: mask,
          transform: const LayerTransform(
            position: Offset(210, 250), // off-centre
            scale: 1.4,
            rotation: 0.3,
          ),
        ),
        const BubbleLayer(
          id: 'bub',
          name: 'bubble',
          text: 'Hi',
          transform: LayerTransform(position: Offset(256, 120)),
        ),
        const TextLayer(
          id: 'txt',
          name: 'cap',
          text: 'WOOF',
          fontFamily: 'Rubik',
          transform: LayerTransform(position: Offset(256, 410)),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox.square(
                dimension: 512,
                child: StickerCanvas(frame: frame),
              ),
            ),
          ),
        ),
      ),
    );

    // Bounded poll: pump real-async frames until the (async-decoded) image has
    // composited at the canvas centre, instead of a fixed wall-clock wait.
    final canvasBytes = await _pumpUntilOpaque(tester, key, size, 256, 256);

    late Uint8List renderBytes;
    await tester.runAsync(() async {
      // Default target size is 512 — the same square the canvas is pumped at.
      final img = await StickerRenderer.renderImage(frame);
      renderBytes = (await img.toByteData())!.buffer.asUint8List();
      img.dispose();
    });

    final stats = _diff(canvasBytes, renderBytes);
    // Same host, same Skia, and the two paths now share the fitted-box constant,
    // so at canvas-scale 1 they render in lockstep (measured mean abs error
    // ~0.004, zero gross-diff pixels). These bounds leave head-room for edge AA
    // yet a flipped/ignored layer, a wrong transform order, dropped opacity or a
    // diverged fitted box would blow far past them.
    expect(
      stats.meanAbsError,
      lessThan(5),
      reason: 'mean abs error ${stats.meanAbsError}',
    );
    expect(
      stats.grossFraction,
      lessThan(0.02),
      reason: 'gross-diff fraction ${stats.grossFraction}',
    );
  });
}

/// Captures the keyed [RepaintBoundary] at 1:1 and returns its RGBA bytes.
Future<Uint8List> _capture(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final image = await boundary.toImage();
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Interleaved runAsync/pump loop until pixel ([x],[y]) is opaque (the
/// async-loaded image finished compositing) or a frame budget is exhausted.
Future<Uint8List> _pumpUntilOpaque(
  WidgetTester tester,
  Key key,
  int size,
  int x,
  int y, {
  int maxFrames = 150,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump();
    Uint8List? bytes;
    await tester.runAsync(() async {
      bytes = await _capture(tester, key);
    });
    if (bytes![(y * size + x) * 4 + 3] > 200) return bytes!;
  }
  fail('image never composited within $maxFrames frames');
}

class _DiffStats {
  const _DiffStats(this.meanAbsError, this.grossFraction);
  final double meanAbsError;
  final double grossFraction;
}

/// Mean absolute per-channel error and the fraction of pixels that differ
/// grossly (any channel off by > 96) between two equal-length RGBA buffers.
_DiffStats _diff(Uint8List a, Uint8List b) {
  final n = math.min(a.length, b.length);
  var sum = 0;
  var gross = 0;
  final pixels = n ~/ 4;
  for (var p = 0; p < pixels; p++) {
    final o = p * 4;
    var worst = 0;
    for (var c = 0; c < 4; c++) {
      final d = (a[o + c] - b[o + c]).abs();
      sum += d;
      if (d > worst) worst = d;
    }
    if (worst > 96) gross++;
  }
  return _DiffStats(sum / (pixels * 4), gross / pixels);
}
