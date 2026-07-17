import 'dart:io';

import 'package:flutter/material.dart';
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

Widget _canvas(Frame frame) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: 300,
        child: StickerCanvas(frame: frame),
      ),
    ),
  ),
);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('sm_canvasmask_'));
  tearDown(() {
    // Best-effort: on Windows the just-decoded PNGs can still be locked when the
    // test ends; the OS reaps the temp dir regardless.
    try {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('a masked photo layer composites (CustomPaint, not Image.file)', (
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
    // Let _MaskedImage decode both files (real async), then reflect its state.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    // The composite path draws with a CustomPaint and never falls back to the
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
