import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/core/theme/app_theme.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
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
}
