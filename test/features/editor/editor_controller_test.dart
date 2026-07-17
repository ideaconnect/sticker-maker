import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sticker_maker/core/models/frame.dart';
import 'package:sticker_maker/core/models/image_adjustments.dart';
import 'package:sticker_maker/core/models/layer.dart';
import 'package:sticker_maker/core/models/sticker_project.dart';
import 'package:sticker_maker/features/editor/state/editor_controller.dart';
import 'package:sticker_maker/features/editor/state/editor_state.dart';
import 'package:sticker_maker/features/editor/state/editor_tool.dart';

/// Builds a container seeded with [project] (or the default demo project).
({ProviderContainer container, EditorController controller}) harness([
  StickerProject? project,
]) {
  final container = ProviderContainer(
    overrides: project == null
        ? const []
        : [
            editorControllerProvider.overrideWith(
              () => EditorController(project),
            ),
          ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    controller: container.read(editorControllerProvider.notifier),
  );
}

StickerProject twoLayerProject() => const StickerProject(
  id: 'p',
  name: 'P',
  frames: [
    Frame(
      id: 'f0',
      layers: [
        ImageLayer(id: 'img', name: 'Photo', assetPath: 'p.png'),
        TextLayer(id: 'txt', name: 'Cap', text: 'Hi', fontFamily: 'Rubik'),
      ],
    ),
  ],
);

void main() {
  test('initial demo state', () {
    final h = harness();
    final s = h.container.read(editorControllerProvider);
    expect(s.tool, EditorTool.adjust);
    expect(s.selectedLayerId, isNull);
    expect(s.layers, hasLength(1));
    expect(s.layers.single, isA<TextLayer>());
  });

  test('setTool and selectLayer', () {
    final h = harness(twoLayerProject());
    h.controller.setTool(EditorTool.text);
    h.controller.selectLayer('txt');
    final s = h.container.read(editorControllerProvider);
    expect(s.tool, EditorTool.text);
    expect(s.selectedLayer, isA<TextLayer>());
    expect(s.selectedLayer!.id, 'txt');
  });

  test('addTextLayer appends and selects', () {
    final h = harness(twoLayerProject());
    final added = h.controller.addTextLayer(text: 'New');
    final s = h.container.read(editorControllerProvider);
    expect(s.layers, hasLength(3));
    expect(s.layers.last.id, added.id);
    expect(s.selectedLayerId, added.id);
  });

  test('addImageLayer appends and selects', () {
    final h = harness(twoLayerProject());
    final added = h.controller.addImageLayer(assetPath: 'a.png');
    final s = h.container.read(editorControllerProvider);
    expect(s.layers.last, isA<ImageLayer>());
    expect(s.selectedLayerId, added.id);
  });

  test('removeLayer clears selection when the selected layer is removed', () {
    final h = harness(twoLayerProject());
    h.controller.selectLayer('txt');
    h.controller.removeLayer('txt');
    final s = h.container.read(editorControllerProvider);
    expect(s.layers, hasLength(1));
    expect(s.selectedLayerId, isNull);
  });

  test('reorderLayer moves a layer', () {
    final h = harness(twoLayerProject());
    h.controller.reorderLayer(0, 1); // img to top
    final s = h.container.read(editorControllerProvider);
    expect(s.layers.map((l) => l.id), ['txt', 'img']);
  });

  test('toggleVisibility flips the flag', () {
    final h = harness(twoLayerProject());
    h.controller.toggleVisibility('img');
    expect(
      h.container.read(editorControllerProvider).layers.first.visible,
      isFalse,
    );
    h.controller.toggleVisibility('img');
    expect(
      h.container.read(editorControllerProvider).layers.first.visible,
      isTrue,
    );
  });

  test('setOpacity updates the layer', () {
    final h = harness(twoLayerProject());
    h.controller.setOpacity('txt', 0.5);
    final txt = h.container
        .read(editorControllerProvider)
        .layers
        .firstWhere((l) => l.id == 'txt');
    expect(txt.opacity, 0.5);
  });

  test('updateTextLayer edits text-specific fields', () {
    final h = harness(twoLayerProject());
    h.controller.updateTextLayer(
      'txt',
      text: 'Bye',
      fontSize: 60,
      color: const Color(0xFF34D399),
    );
    final txt =
        h.container
                .read(editorControllerProvider)
                .layers
                .firstWhere((l) => l.id == 'txt')
            as TextLayer;
    expect(txt.text, 'Bye');
    expect(txt.name, 'Bye');
    expect(txt.fontSize, 60);
    expect(txt.color, const Color(0xFF34D399));
  });

  test('updateImageAdjustments only touches image layers', () {
    final h = harness(twoLayerProject());
    const adj = ImageAdjustments(brightness: 1.3);
    h.controller.updateImageAdjustments('img', adj);
    // A no-op on a text id must not throw or change anything.
    h.controller.updateImageAdjustments('txt', adj);
    final img =
        h.container
                .read(editorControllerProvider)
                .layers
                .firstWhere((l) => l.id == 'img')
            as ImageLayer;
    expect(img.adjustments, adj);
  });

  test('setImageMask sets and clears the mask path', () {
    final h = harness(twoLayerProject());
    h.controller.setImageMask('img', 'img.mask.png');
    var img =
        h.container
                .read(editorControllerProvider)
                .layers
                .firstWhere((l) => l.id == 'img')
            as ImageLayer;
    expect(img.maskPath, 'img.mask.png');
    h.controller.setImageMask('img', null);
    img =
        h.container
                .read(editorControllerProvider)
                .layers
                .firstWhere((l) => l.id == 'img')
            as ImageLayer;
    expect(img.maskPath, isNull);
  });

  group('frames', () {
    test('addFrame duplicates layers with fresh ids and selects it', () {
      final h = harness(twoLayerProject());
      h.controller.addFrame();
      final p = h.container.read(editorControllerProvider).project;
      expect(p.frameCount, 2);
      expect(p.currentFrameIndex, 1);
      final srcIds = p.frames[0].layers.map((l) => l.id).toSet();
      final dupIds = p.frames[1].layers.map((l) => l.id).toSet();
      expect(p.frames[1].layers, hasLength(2));
      expect(srcIds.intersection(dupIds), isEmpty); // ids are unique
    });

    test('selectFrame changes the current frame and ignores bad indices', () {
      final h = harness(twoLayerProject());
      h.controller.addFrame();
      h.controller.selectFrame(0);
      expect(
        h.container.read(editorControllerProvider).project.currentFrameIndex,
        0,
      );
      h.controller.selectFrame(99); // ignored
      expect(
        h.container.read(editorControllerProvider).project.currentFrameIndex,
        0,
      );
    });

    test('deleteFrame keeps at least one frame', () {
      final h = harness(twoLayerProject());
      h.controller.deleteFrame(0); // only frame -> ignored
      expect(h.container.read(editorControllerProvider).project.frameCount, 1);
      h.controller.addFrame();
      h.controller.deleteFrame(1);
      expect(h.container.read(editorControllerProvider).project.frameCount, 1);
    });
  });

  test('rename updates the project name', () {
    final h = harness(twoLayerProject());
    h.controller.rename('Party pug');
    expect(
      h.container.read(editorControllerProvider).project.name,
      'Party pug',
    );
  });

  test('EditorState.copyWith clears selection with the sentinel', () {
    const base = EditorState(
      project: StickerProject(
        id: 'x',
        name: 'x',
        frames: [Frame(id: 'f')],
      ),
      selectedLayerId: 'abc',
    );
    expect(base.copyWith(clearSelection: true).selectedLayerId, isNull);
    expect(base.copyWith(tool: EditorTool.frames).selectedLayerId, 'abc');
  });
}
