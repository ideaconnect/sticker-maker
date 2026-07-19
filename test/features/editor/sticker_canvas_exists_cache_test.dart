import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/features/editor/widgets/sticker_canvas.dart';

/// Proves the perf fix from the 2026-07-19 review: [StickerCanvas] must not
/// re-`File.existsSync` per rebuild (i.e. per pointer-move frame during a drag)
/// when a layer's asset/mask path is unchanged.
///
/// Rebuilds are forced with `markNeedsBuild` (not a new widget), so the assert
/// is strictly about the existence cache — not widget-identity short-circuiting.
Widget _host(Frame frame) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: 300,
        child: StickerCanvas(frame: frame),
      ),
    ),
  ),
);

Future<void> _rebuild(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    tester.element(find.byType(StickerCanvas)).markNeedsBuild();
    await tester.pump();
  }
}

void main() {
  setUp(() {
    StickerCanvas.existsCache.clear();
    StickerCanvas.fileExists = StickerCanvas.defaultFileExists;
  });
  tearDown(() {
    StickerCanvas.existsCache.clear();
    StickerCanvas.fileExists = StickerCanvas.defaultFileExists;
  });

  testWidgets('existence is probed once per path across many rebuilds', (
    tester,
  ) async {
    final probes = <String>[];
    StickerCanvas.fileExists = (path) {
      probes.add(path);
      return true; // pretend both files exist
    };

    const asset = '/assets/img_rex.png';
    const mask = '/assets/mask_rex_1.png';
    const frame = Frame(
      id: 'f',
      layers: [
        ImageLayer(id: 'i', name: 'Rex', assetPath: asset, maskPath: mask),
      ],
    );

    await tester.pumpWidget(_host(frame));
    await _rebuild(tester, 8); // 8 extra builds of the same element

    // Despite ~9 builds, each path is stat-probed exactly once.
    expect(probes.where((p) => p == asset), hasLength(1));
    expect(probes.where((p) => p == mask), hasLength(1));
    expect(StickerCanvas.existsCache[asset], isTrue);
    expect(StickerCanvas.existsCache[mask], isTrue);
  });

  testWidgets('a cached result is reused even after the file changes on disk', (
    tester,
  ) async {
    // First probe reports "exists"; a later probe would report "gone". The cache
    // must keep the first answer, so no second probe is made for the same path.
    var live = true;
    var probeCount = 0;
    StickerCanvas.fileExists = (path) {
      probeCount++;
      return live;
    };

    const asset = '/assets/img_rex.png';
    const frame = Frame(
      id: 'f',
      layers: [ImageLayer(id: 'i', name: 'Rex', assetPath: asset)],
    );

    await tester.pumpWidget(_host(frame));
    expect(probeCount, 1);

    // The file "disappears", but the cache shields the canvas from re-stat-ing.
    live = false;
    await _rebuild(tester, 5);
    expect(probeCount, 1, reason: 'no re-stat while the path is unchanged');
    expect(StickerCanvas.existsCache[asset], isTrue);
  });
}
