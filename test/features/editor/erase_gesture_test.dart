import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/editor/state/editor_tool.dart';
import 'package:sticker_maker/features/editor/widgets/editor_canvas.dart';

const _project = StickerProject(
  id: 'p',
  name: 'e',
  frames: [
    Frame(
      id: 'f',
      layers: [ImageLayer(id: 'img', name: 'Doggo', assetPath: '/no.png')],
    ),
  ],
);

Future<ProviderContainer> _pumpCanvas(
  WidgetTester tester,
  List<List<Offset>> captured,
) async {
  final container = ProviderContainer(
    overrides: [
      editorControllerProvider.overrideWith(() => EditorController(_project)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 300,
              child: EditorCanvas(
                onEmptyTap: () {},
                dropPlaceholder: const SizedBox(),
                onEraseStroke: captured.add,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('an erase-mode drag over the selected photo emits a stroke', (
    tester,
  ) async {
    final captured = <List<Offset>>[];
    final container = await _pumpCanvas(tester, captured);

    container.read(editorControllerProvider.notifier).selectLayer('img');
    container.read(editorControllerProvider.notifier).setTool(EditorTool.erase);
    await tester.pump();

    await tester.drag(find.byType(EditorCanvas), const Offset(60, 20));
    await tester.pump();

    expect(captured, hasLength(1), reason: 'one stroke emitted');
    expect(captured.first, isNotEmpty, reason: 'stroke has points');
  });

  testWidgets('a normal-mode drag moves the layer, emits no stroke', (
    tester,
  ) async {
    final captured = <List<Offset>>[];
    final container = await _pumpCanvas(tester, captured);

    container.read(editorControllerProvider.notifier).selectLayer('img');
    // Default tool (layers), not erase.
    await tester.pump();

    final before = _imagePosition(container);
    await tester.drag(find.byType(EditorCanvas), const Offset(60, 20));
    await tester.pump();

    expect(captured, isEmpty, reason: 'no stroke in normal mode');
    expect(
      _imagePosition(container),
      isNot(before),
      reason: 'the drag moved the layer instead',
    );
  });
}

Offset _imagePosition(ProviderContainer container) {
  final layer = container
      .read(editorControllerProvider)
      .currentFrame
      .layers
      .first;
  return layer.transform.position;
}
