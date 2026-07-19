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

  test('addImageLayer auto-numbers photos and reuses freed names (#73)', () {
    final h = harness(twoLayerProject()); // already contains "Photo"
    final second = h.controller.addImageLayer(assetPath: 'b.png');
    final third = h.controller.addImageLayer(assetPath: 'c.png');
    expect(second.name, 'Photo 2');
    expect(third.name, 'Photo 3');

    // Freeing "Photo 2" makes it the next auto-name; explicit names win.
    h.controller.removeLayer(second.id);
    expect(h.controller.addImageLayer(assetPath: 'd.png').name, 'Photo 2');
    expect(
      h.controller.addImageLayer(assetPath: 'e.png', name: 'Sky').name,
      'Sky',
    );
  });

  test('additional photos cascade-offset from center (#74)', () {
    final h = harness(twoLayerProject()); // one ImageLayer at identity
    final second = h.controller.addImageLayer(assetPath: 'b.png');
    final third = h.controller.addImageLayer(assetPath: 'c.png');
    expect(second.transform.position, const Offset(280, 280));
    expect(third.transform.position, const Offset(304, 304));
  });

  test('clearing bubble text never blanks the layer name (#82)', () {
    final h = harness(twoLayerProject());
    final bubble = h.controller.addBubbleLayer(text: 'Hello!');
    h.controller.updateBubbleLayer(bubble.id, text: '');
    final updated = h.container
        .read(editorControllerProvider)
        .layers
        .whereType<BubbleLayer>()
        .single;
    expect(updated.text, '');
    expect(updated.name, 'Hello!', reason: 'keeps the last non-empty name');
  });

  test('bubble edits undo per property group, not as one blob (#82)', () {
    final h = harness(twoLayerProject());
    final bubble = h.controller.addBubbleLayer();
    BubbleLayer current() => h.container
        .read(editorControllerProvider)
        .layers
        .whereType<BubbleLayer>()
        .single;

    h.controller.updateBubbleLayer(bubble.id, shape: BubbleShape.thought);
    h.controller.updateBubbleLayer(
      bubble.id,
      fillColor: const Color(0xFFFF0000),
    );
    expect(current().shape, BubbleShape.thought);
    expect(current().fillColor, const Color(0xFFFF0000));

    // One undo reverts only the fill; the shape edit is its own step.
    h.controller.undo();
    expect(current().fillColor, isNot(const Color(0xFFFF0000)));
    expect(current().shape, BubbleShape.thought);
    h.controller.undo();
    expect(current().shape, BubbleShape.speech);
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

  test('addEmoji adds a decorative, selected text layer', () {
    final h = harness(twoLayerProject());
    final layer = h.controller.addEmoji('🐶');
    final s = h.container.read(editorControllerProvider);
    expect(s.selectedLayerId, layer.id);
    final added = s.layers.firstWhere((l) => l.id == layer.id) as TextLayer;
    expect(added.text, '🐶');
    expect(added.decorative, isTrue, reason: 'no caption stroke on emoji');
  });

  test('updateImageOutline sets width and color; coalesces to one undo', () {
    final h = harness(twoLayerProject());
    ImageLayer img() =>
        h.container
                .read(editorControllerProvider)
                .layers
                .firstWhere((l) => l.id == 'img')
            as ImageLayer;

    expect(img().hasOutline, isFalse, reason: 'off by default');

    // Consecutive slider ticks coalesce (coalesce: outline:img).
    h.controller.updateImageOutline('img', width: 8);
    h.controller.updateImageOutline('img', width: 16);
    h.controller.updateImageOutline('img', color: const Color(0xFFFF0000));
    expect(img().outlineWidth, 16);
    expect(img().outlineColor, const Color(0xFFFF0000));
    expect(img().hasOutline, isTrue);

    // The coalesced edits undo together, back to no outline.
    h.controller.undo();
    expect(img().hasOutline, isFalse);
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

  test('renameLayer changes a layer name of either type', () {
    final h = harness(twoLayerProject());
    h.controller.renameLayer('img', 'Dog photo');
    h.controller.renameLayer('txt', 'Caption 1');
    final layers = h.container.read(editorControllerProvider).layers;
    expect(layers.firstWhere((l) => l.id == 'img').name, 'Dog photo');
    expect(layers.firstWhere((l) => l.id == 'txt').name, 'Caption 1');
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

  group('undo / redo', () {
    ImageLayer imgOf(ProviderContainer c) =>
        c.read(editorControllerProvider).layers.firstWhere((l) => l.id == 'img')
            as ImageLayer;

    test('starts with empty history', () {
      final h = harness(twoLayerProject());
      expect(h.controller.canUndo, isFalse);
      expect(h.controller.canRedo, isFalse);
      h.controller.undo(); // no-op
      h.controller.redo(); // no-op
      expect(h.container.read(editorControllerProvider).layers, hasLength(2));
    });

    test('undo reverses an edit and redo re-applies it', () {
      final h = harness(twoLayerProject());
      h.controller.addTextLayer(text: 'New');
      expect(h.controller.canUndo, isTrue);
      expect(h.container.read(editorControllerProvider).layers, hasLength(3));

      h.controller.undo();
      expect(h.container.read(editorControllerProvider).layers, hasLength(2));
      expect(h.controller.canRedo, isTrue);

      h.controller.redo();
      expect(h.container.read(editorControllerProvider).layers, hasLength(3));
    });

    test('selecting a layer or switching tool is not undoable', () {
      final h = harness(twoLayerProject());
      h.controller.selectLayer('img');
      h.controller.setTool(EditorTool.text);
      expect(h.controller.canUndo, isFalse);
    });

    test('a continuous edit coalesces into one undo step', () {
      final h = harness(twoLayerProject());
      h.controller.updateImageAdjustments(
        'img',
        const ImageAdjustments(brightness: 1.1),
      );
      h.controller.updateImageAdjustments(
        'img',
        const ImageAdjustments(brightness: 1.2),
      );
      h.controller.updateImageAdjustments(
        'img',
        const ImageAdjustments(brightness: 1.3),
      );
      expect(h.controller.canUndo, isTrue);

      h.controller.undo(); // one step reverts the whole drag
      expect(imgOf(h.container).adjustments, ImageAdjustments.identity);
      expect(h.controller.canUndo, isFalse);
    });

    test('endEdit closes a step so the next drag is separate', () {
      final h = harness(twoLayerProject());
      h.controller.updateImageAdjustments(
        'img',
        const ImageAdjustments(brightness: 1.2),
      );
      h.controller.endEdit();
      h.controller.updateImageAdjustments(
        'img',
        const ImageAdjustments(brightness: 1.5),
      );

      h.controller.undo();
      expect(imgOf(h.container).adjustments.brightness, closeTo(1.2, 1e-9));
      h.controller.undo();
      expect(imgOf(h.container).adjustments, ImageAdjustments.identity);
    });

    test('a new edit clears the redo stack', () {
      final h = harness(twoLayerProject());
      h.controller.addTextLayer(text: 'A');
      h.controller.undo();
      expect(h.controller.canRedo, isTrue);
      h.controller.addTextLayer(text: 'B');
      expect(h.controller.canRedo, isFalse);
    });
  });
}
