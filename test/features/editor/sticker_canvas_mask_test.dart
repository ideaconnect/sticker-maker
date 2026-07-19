import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/editor/widgets/sticker_canvas.dart';
import 'package:sticker_maker/features/segmentation/alpha_mask.dart';
import 'package:sticker_maker/features/segmentation/mask_store.dart';

/// Encodes an [AlphaMask] to a real PNG on disk (real `dart:ui` async, so the
/// caller must be inside [WidgetTester.runAsync]).
Future<String> _writePng(Directory dir, String name, AlphaMask mask) async {
  final bytes = await MaskStore.encodePng(mask);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  return file.path;
}

const _canvasKey = ValueKey('mask-canvas');
const _canvasSide = 300;

Widget _canvas(Frame frame) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: _canvasKey,
        child: SizedBox.square(
          dimension: _canvasSide.toDouble(),
          child: StickerCanvas(frame: frame),
        ),
      ),
    ),
  ),
);

/// Captures the keyed canvas at 1:1 and returns its RGBA bytes.
Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_canvasKey),
  );
  final image = await boundary.toImage();
  final data = await image.toByteData();
  image.dispose();
  return data!.buffer.asUint8List();
}

int _alphaAt(Uint8List rgba, int x, int y) =>
    rgba[(y * _canvasSide + x) * 4 + 3];

/// Bounded poll: interleave short real-async waits with pumps until pixel
/// ([x],[y]) has composited to opaque, or a frame budget is exhausted. Returns
/// the captured RGBA. Replaces a fixed wall-clock delay that could pass
/// vacuously (before any decode) on a loaded machine.
Future<Uint8List> _pumpUntilOpaque(
  WidgetTester tester,
  int x,
  int y, {
  int maxFrames = 150,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump();
    Uint8List? rgba;
    await tester.runAsync(() async {
      rgba = await _capture(tester);
    });
    if (_alphaAt(rgba!, x, y) > 200) return rgba!;
  }
  fail('masked image never composited within $maxFrames frames');
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_canvasmask_'));
  tearDown(() {
    // Best-effort: on Windows the just-decoded PNGs can still be locked when the
    // test ends; the OS reaps the temp dir regardless.
    imageCache.clear();
    imageCache.clearLiveImages();
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a masked photo layer composites its mask into real pixels', (
    tester,
  ) async {
    late String base;
    late String mask;
    await tester.runAsync(() async {
      base = await _writePng(tmp, 'base.png', AlphaMask.filled(16, 16, 255));
      // Left half opaque, right half transparent.
      final bytes = AlphaMask.filled(16, 16, 255).alpha;
      for (var y = 0; y < 16; y++) {
        for (var x = 8; x < 16; x++) {
          bytes[y * 16 + x] = 0;
        }
      }
      mask = await _writePng(
        tmp,
        'mask.png',
        AlphaMask(width: 16, height: 16, alpha: bytes),
      );
    });

    await tester.pumpWidget(
      _canvas(
        Frame(
          id: 'f',
          layers: [
            ImageLayer(id: 'i', name: 'Rex', assetPath: base, maskPath: mask),
          ],
        ),
      ),
    );

    // The 300-px canvas maps the 512-logical box centred at (256,256) onto a
    // ~258-px box centred at (150,150): its left half is the mask's opaque half,
    // its right half is the masked-out half. Poll until the composite lands on
    // the left half, then assert the actual pixels rather than widget structure.
    final rgba = await _pumpUntilOpaque(tester, 75, 150);

    // Effect, not structure: the mask's opaque half survives, the masked-out
    // half is cut to transparent. A flipped mask, a wrong blend mode (anything
    // but dstIn) or an ignored mask would fail one of these.
    expect(
      _alphaAt(rgba, 75, 150),
      greaterThan(200),
      reason: 'mask opaque half stays opaque',
    );
    expect(
      _alphaAt(rgba, 225, 150),
      lessThan(40),
      reason: 'masked-out half is cut to transparent',
    );

    // The composite path still draws a CustomPaint and never falls back to a
    // plain Image.file widget.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unmasked photo layer uses Image.file (no compositing)', (
    tester,
  ) async {
    late String base;
    await tester.runAsync(() async {
      base = await _writePng(tmp, 'base.png', AlphaMask.filled(16, 16, 255));
    });

    await tester.pumpWidget(
      _canvas(
        Frame(
          id: 'f',
          layers: [ImageLayer(id: 'i', name: 'Rex', assetPath: base)],
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });
}
