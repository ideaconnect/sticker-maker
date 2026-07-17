import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/frame.dart';
import '../../../core/models/image_adjustments.dart';
import '../../../core/models/layer.dart';
import '../../../core/models/layer_transform.dart';
import '../../../core/models/sticker_project.dart';
import 'editor_state.dart';
import 'editor_tool.dart';

/// Owns the editor document and drives every mutation. All document edits go
/// through [_commit], which records an immutable snapshot for undo/redo (#20).
/// Continuous gestures (slider drags, typing) coalesce into a single history
/// step via a coalesce key, reset at interaction boundaries and by [endEdit].
class EditorController extends Notifier<EditorState> {
  /// Optional seed project (used by the route / tests). Defaults to a demo
  /// project with a single "WOOF!" caption so the canvas is not empty before
  /// image import (#21) lands.
  EditorController([this._seed]);

  final StickerProject? _seed;
  int _seq = 0;

  static const int _maxHistory = 50;
  final List<StickerProject> _undoStack = [];
  final List<StickerProject> _redoStack = [];
  String? _coalesceKey;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

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

  // ------------------------------------------------------------ history
  /// Commits a new document, recording history. When [coalesce] matches the
  /// previous commit's key, the two fold into one undo step (e.g. a drag).
  void _commit(
    StickerProject next, {
    String? coalesce,
    bool clearSelection = false,
  }) {
    final coalescing =
        coalesce != null && coalesce == _coalesceKey && _undoStack.isNotEmpty;
    if (!coalescing) {
      _undoStack.add(state.project);
      if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    }
    _coalesceKey = coalesce;
    _redoStack.clear();
    state = state.copyWith(project: next, clearSelection: clearSelection);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(state.project);
    final prev = _undoStack.removeLast();
    _coalesceKey = null;
    state = state.copyWith(project: prev, clearSelection: true);
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(state.project);
    final next = _redoStack.removeLast();
    _coalesceKey = null;
    state = state.copyWith(project: next, clearSelection: true);
  }

  /// Ends a continuous edit (e.g. a slider drag), so the next edit starts a
  /// fresh undo step.
  void endEdit() => _coalesceKey = null;

  /// Replaces the current document (e.g. opening a saved project), resetting
  /// history. Bumps the id counter past any loaded ids to avoid collisions.
  void loadProject(StickerProject project) {
    _undoStack.clear();
    _redoStack.clear();
    _coalesceKey = null;
    for (final frame in project.frames) {
      _bumpSeqPast(frame.id);
      for (final layer in frame.layers) {
        _bumpSeqPast(layer.id);
      }
    }
    state = EditorState(project: project);
  }

  void _bumpSeqPast(String id) {
    final i = id.lastIndexOf('_');
    if (i < 0) return;
    final n = int.tryParse(id.substring(i + 1));
    if (n != null && n >= _seq) _seq = n + 1;
  }

  // ------------------------------------------------------------ UI state
  void setTool(EditorTool tool) {
    _coalesceKey = null;
    state = state.copyWith(tool: tool);
  }

  void selectLayer(String? id) {
    _coalesceKey = null;
    state = state.copyWith(selectedLayerId: id, clearSelection: id == null);
  }

  // ------------------------------------------------------------ layer ops
  void _mutateLayers(
    List<Layer> Function(List<Layer>) transform, {
    String? coalesce,
  }) {
    final frames = [...state.project.frames];
    final index = state.project.safeFrameIndex;
    frames[index] = frames[index].copyWith(
      layers: transform(frames[index].layers),
    );
    _commit(state.project.copyWith(frames: frames), coalesce: coalesce);
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
    coalesce: 'opacity:$id',
    image: (l) => l.copyWith(opacity: opacity),
    text: (l) => l.copyWith(opacity: opacity),
  );

  void updateTransform(String id, LayerTransform transform) => _updateLayer(
    id,
    coalesce: 'transform:$id',
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
    coalesce: 'text:$id',
    text: (l) => l.copyWith(
      text: text,
      name: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
    ),
  );

  void renameLayer(String id, String name) => _updateLayer(
    id,
    image: (l) => l.copyWith(name: name),
    text: (l) => l.copyWith(name: name),
  );

  void updateImageAdjustments(String id, ImageAdjustments adjustments) =>
      _updateLayer(
        id,
        coalesce: 'adjust:$id',
        image: (l) => l.copyWith(adjustments: adjustments),
      );

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
    String? coalesce,
  }) {
    _mutateLayers(
      (layers) => layers.map((layer) {
        if (layer.id != id) return layer;
        return switch (layer) {
          ImageLayer() => image?.call(layer) ?? layer,
          TextLayer() => text?.call(layer) ?? layer,
        };
      }).toList(),
      coalesce: coalesce,
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
    _commit(
      project.copyWith(frames: frames, currentFrameIndex: frames.length - 1),
      clearSelection: true,
    );
  }

  /// Frame navigation — not an undoable document edit.
  void selectFrame(int index) {
    final project = state.project;
    if (index < 0 || index >= project.frames.length) return;
    _coalesceKey = null;
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
    _commit(
      project.copyWith(frames: frames, currentFrameIndex: current),
      clearSelection: true,
    );
  }

  void rename(String name) => _commit(state.project.copyWith(name: name));
}

/// Editor state for the active document. Override in tests / the editor route
/// to seed a specific project.
final editorControllerProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);
