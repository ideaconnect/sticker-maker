import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/editor/widgets/bubble_view.dart';
import 'package:sticker_maker/features/editor/widgets/editor_canvas.dart';

StickerProject centeredImage() => const StickerProject(
  id: 'p',
  name: 'P',
  frames: [
    Frame(
      id: 'f',
      layers: [ImageLayer(id: 'img', name: 'Photo', assetPath: 'nope.png')],
    ),
  ],
);

Future<ProviderContainer> pumpCanvas(
  WidgetTester tester,
  StickerProject project,
) async {
  final container = ProviderContainer(
    overrides: [
      editorControllerProvider.overrideWith(() => EditorController(project)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildStickerTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 320,
              child: EditorCanvas(
                onEmptyTap: () {},
                dropPlaceholder: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

ImageLayer imgOf(ProviderContainer c) =>
    c.read(editorControllerProvider).layers.single as ImageLayer;

void main() {
  testWidgets('tapping a layer selects it, tapping empty space deselects', (
    tester,
  ) async {
    final c = await pumpCanvas(tester, centeredImage());
    expect(c.read(editorControllerProvider).selectedLayerId, isNull);

    await tester.tap(find.byType(EditorCanvas)); // center = the layer
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedLayerId, 'img');

    await tester.tapAt(
      tester.getTopLeft(find.byType(EditorCanvas)) + const Offset(4, 4),
    );
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedLayerId, isNull);
  });

  testWidgets('dragging moves the selected layer', (tester) async {
    final c = await pumpCanvas(tester, centeredImage());
    final before = imgOf(c).transform.position;

    await tester.drag(find.byType(EditorCanvas), const Offset(48, 0));
    await tester.pumpAndSettle();

    final after = imgOf(c).transform.position;
    expect(after.dx, greaterThan(before.dx));
    expect(after.dy, closeTo(before.dy, 0.01));
    // The drag registers as one coalesced undo step.
    expect(c.read(editorControllerProvider.notifier).canUndo, isTrue);
  });

  testWidgets('a wide photo hit box shrinks to its content rect (#74)', (
    tester,
  ) async {
    // A real 200×100 file so the canvas can read the encoded header dims.
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('canvas74_'),
    ))!;
    addTearDown(() {
      imageCache.clear();
      imageCache.clearLiveImages();
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Windows can briefly keep the decoded file handle open.
      }
    });
    final file = File('${dir.path}/wide.png');
    await tester.runAsync(
      () => file.writeAsBytes(img.encodePng(img.Image(width: 200, height: 100))),
    );

    final c = await pumpCanvas(
      tester,
      StickerProject(
        id: 'p',
        name: 'P',
        frames: [
          Frame(
            id: 'f',
            layers: [
              ImageLayer(id: 'img', name: 'Photo', assetPath: file.path),
            ],
          ),
        ],
      ),
    );
    // Let the fire-and-forget header read complete. Each await hop in
    // _ensureDims needs a real-async window (IO/engine completion) followed
    // by a pump (fake-zone microtask flush), so interleave several.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Canvas widget is 320px for a 512 logical grid. The 2:1 photo fills
    // 440×220 logical centered at (256,256) → y spans 146..366. A tap at
    // logical (256,80) is inside the OLD 440 square (36..476) but above the
    // content rect, so it must NOT select the photo.
    final topLeft = tester.getTopLeft(find.byType(EditorCanvas));
    const scale = 320 / 512;
    await tester.tapAt(topLeft + const Offset(256 * scale, 80 * scale));
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedLayerId, isNull);

    // Dead-center is inside the content rect → selects.
    await tester.tapAt(topLeft + const Offset(256 * scale, 256 * scale));
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedLayerId, 'img');
  });

  testWidgets('dragging the tail handle re-aims the bubble tail (#78)', (
    tester,
  ) async {
    final c = await pumpCanvas(
      tester,
      const StickerProject(
        id: 'p',
        name: 'P',
        frames: [
          Frame(
            id: 'f',
            layers: [BubbleLayer(id: 'bub', name: 'B')],
          ),
        ],
      ),
    );

    // Select the bubble so its selection UI (incl. the tail knob) shows.
    await tester.tap(find.byType(EditorCanvas));
    await tester.pumpAndSettle();
    expect(c.read(editorControllerProvider).selectedLayerId, 'bub');

    BubbleLayer bubble() =>
        c.read(editorControllerProvider).layers.single as BubbleLayer;
    final before = bubble();
    const canvasScale = 320 / 512;

    // The tail tip in canvas px: bubble box centered at (256,256) logical.
    final tipLocal = bubbleTailTip(before, kBubbleBaseSize);
    final tipLogical =
        const Offset(256, 256) +
        (tipLocal -
            Offset(kBubbleBaseSize.width / 2, kBubbleBaseSize.height / 2));
    final start =
        tester.getTopLeft(find.byType(EditorCanvas)) + tipLogical * canvasScale;

    // Drag the knob upward — the tail should flip above the body (dy < 0)
    // and the bubble itself must NOT move (the handle wins the gesture).
    await tester.dragFrom(start, const Offset(0, -110 * canvasScale));
    await tester.pumpAndSettle();

    expect(bubble().tail.dy, lessThan(0));
    expect(bubble().transform.position, before.transform.position);
    expect(
      c.read(editorControllerProvider.notifier).canUndo,
      isTrue,
      reason: 'the drag lands as one undoable edit',
    );
  });
}
