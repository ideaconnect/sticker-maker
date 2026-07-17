import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/frame.dart';
import '../../../core/models/image_adjustments.dart';
import '../../../core/models/layer.dart';
import '../../../core/models/layer_transform.dart';
import '../../../core/models/sticker_project.dart';
import 'editor_state.dart';
import 'editor_tool.dart';

/// Owns the editor document and drives every mutation. All edits go through
/// here and produce a new immutable [EditorState], which keeps the door open
/// for the undo/redo history in issue #20.
class EditorController extends Notifier<EditorState> {
  /// Optional seed project (used by the route / tests). Defaults to a demo
  /// project with a single "WOOF!" caption so the canvas is not empty before
  /// image import (#21) lands.
  EditorController([this._seed]);

  final StickerProject? _seed;
  int _seq = 0;

  String _newId(String prefix) => '${prefix}_${_seq++}';

  @override
  EditorState build() {
    final project = _seed ?? _demoProject();
    return EditorState(project: project);
  }

  StickerProject _demoProject() {
    return StickerProject(
      id: 'demo',
      name: 'Rex woof',
      frames: [
        Frame(
          id: _newId('f'),
          layers: [
            TextLayer(
              id: _newId('l'),
              name: 'WOOF!',
              text: 'WOOF!',
              fontFamily: 'Bangers',
              transform: const LayerTransform(
                position: Offset(256, 400),
                rotation: -0.087, // ~ -5°, matching the design
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ UI state
  void setTool(EditorTool tool) => state = state.copyWith(tool: tool);

  void selectLayer(String? id) =>
      state = state.copyWith(selectedLayerId: id, clearSelection: id == null);

  // ------------------------------------------------------------ layer ops
  void _mutateLayers(List<Layer> Function(List<Layer>) transform) {
    final frames = [...state.project.frames];
    final index = state.project.safeFrameIndex;
    frames[index] = frames[index].copyWith(
      layers: transform(frames[index].layers),
    );
    state = state.copyWith(project: state.project.copyWith(frames: frames));
  }

  TextLayer addTextLayer({
    String text = 'Text',
    String fontFamily = 'Bangers',
    double fontSize = 40,
  }) {
    final layer = TextLayer(
      id: _newId('l'),
      name: text,
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
    );
    _mutateLayers((layers) => [...layers, layer]);
    selectLayer(layer.id);
    return layer;
  }

  ImageLayer addImageLayer({required String assetPath, String name = 'Photo'}) {
    final layer = ImageLayer(id: _newId('l'), name: name, assetPath: assetPath);
    _mutateLayers((layers) => [...layers, layer]);
    selectLayer(layer.id);
    return layer;
  }

  void removeLayer(String id) {
    _mutateLayers((layers) => layers.where((l) => l.id != id).toList());
    if (state.selectedLayerId == id) selectLayer(null);
  }

  void reorderLayer(int oldIndex, int newIndex) {
    _mutateLayers((layers) {
      final next = [...layers];
      final item = next.removeAt(oldIndex);
      next.insert(newIndex.clamp(0, next.length), item);
      return next;
    });
  }

  void toggleVisibility(String id) => _updateLayer(
    id,
    image: (l) => l.copyWith(visible: !l.visible),
    text: (l) => l.copyWith(visible: !l.visible),
  );

  void setOpacity(String id, double opacity) => _updateLayer(
    id,
    image: (l) => l.copyWith(opacity: opacity),
    text: (l) => l.copyWith(opacity: opacity),
  );

  void updateTransform(String id, LayerTransform transform) => _updateLayer(
    id,
    image: (l) => l.copyWith(transform: transform),
    text: (l) => l.copyWith(transform: transform),
  );

  void updateTextLayer(
    String id, {
    String? text,
    String? fontFamily,
    double? fontSize,
    Color? color,
  }) => _updateLayer(
    id,
    text: (l) => l.copyWith(
      text: text,
      name: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
    ),
  );

  void updateImageAdjustments(String id, ImageAdjustments adjustments) =>
      _updateLayer(id, image: (l) => l.copyWith(adjustments: adjustments));

  void setImageMask(String id, String? maskPath) => _updateLayer(
    id,
    image: (l) => maskPath == null
        ? l.copyWith(clearMask: true)
        : l.copyWith(maskPath: maskPath),
  );

  /// Applies a type-specific transform to the matching layer. A callback left
  /// null means "leave that layer type unchanged".
  void _updateLayer(
    String id, {
    ImageLayer Function(ImageLayer)? image,
    TextLayer Function(TextLayer)? text,
  }) {
    _mutateLayers(
      (layers) => layers.map((layer) {
        if (layer.id != id) return layer;
        return switch (layer) {
          ImageLayer() => image?.call(layer) ?? layer,
          TextLayer() => text?.call(layer) ?? layer,
        };
      }).toList(),
    );
  }

  // ------------------------------------------------------------ frame ops
  Layer _cloneWithNewId(Layer layer) => switch (layer) {
    ImageLayer() => layer.copyWith(id: _newId('l')),
    TextLayer() => layer.copyWith(id: _newId('l')),
  };

  /// Adds a new frame that duplicates the current one, and selects it.
  void addFrame() {
    final project = state.project;
    final source = project.currentFrame;
    final clone = Frame(
      id: _newId('f'),
      layers: source.layers.map(_cloneWithNewId).toList(),
    );
    final frames = [...project.frames, clone];
    state = state.copyWith(
      project: project.copyWith(
        frames: frames,
        currentFrameIndex: frames.length - 1,
      ),
      clearSelection: true,
    );
  }

  void selectFrame(int index) {
    final project = state.project;
    if (index < 0 || index >= project.frames.length) return;
    state = state.copyWith(
      project: project.copyWith(currentFrameIndex: index),
      clearSelection: true,
    );
  }

  void deleteFrame(int index) {
    final project = state.project;
    if (project.frames.length <= 1) return; // keep at least one frame
    final frames = [...project.frames]..removeAt(index);
    final current = project.currentFrameIndex.clamp(0, frames.length - 1);
    state = state.copyWith(
      project: project.copyWith(frames: frames, currentFrameIndex: current),
      clearSelection: true,
    );
  }

  void rename(String name) =>
      state = state.copyWith(project: state.project.copyWith(name: name));
}

/// Editor state for the active document. Override in tests / the editor route
/// to seed a specific project.
final editorControllerProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);
