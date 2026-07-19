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

  /// When true, layers added via the Add menu are inserted onto **every** frame
  /// (a fresh id per frame) — the basis for animating one caption across frames.
  /// Toggled from the Frames panel; only takes effect on animated projects.
  bool addToAllFrames = false;

  /// Adds a layer to the current frame, or — when [addToAllFrames] is on and the
  /// project is animated — a fresh-id copy to every frame, selecting the copy on
  /// the current frame. [make] is called once per target frame.
  T _addLayer<T extends Layer>(T Function() make) {
    if (addToAllFrames && state.project.frameCount > 1) {
      final project = state.project;
      final currentIdx = project.safeFrameIndex;
      late T selected;
      final frames = <Frame>[];
      for (var i = 0; i < project.frames.length; i++) {
        final layer = make();
        if (i == currentIdx) selected = layer;
        frames.add(
          project.frames[i].copyWith(
            layers: [...project.frames[i].layers, layer],
          ),
        );
      }
      _commit(project.copyWith(frames: frames));
      selectLayer(selected.id);
      return selected;
    }
    final layer = make();
    _mutateLayers((layers) => [...layers, layer]);
    selectLayer(layer.id);
    return layer;
  }

  TextLayer addTextLayer({
    String text = 'Text',
    String fontFamily = 'Bangers',
    double fontSize = 40,
  }) => _addLayer(
    () => TextLayer(
      id: _newId('l'),
      name: text,
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
    ),
  );

  /// With no explicit [name], photos are auto-numbered ("Photo", "Photo 2", …)
  /// against the current frame so multiple image layers stay tellable apart
  /// in the Layers panel (#73). Additional photos land cascade-offset from
  /// center (24 logical px per existing photo, cycling) so a new image never
  /// exactly buries the one below (#74).
  ImageLayer addImageLayer({required String assetPath, String? name}) {
    final resolved = name ?? _nextPhotoName();
    final existing = state.layers.whereType<ImageLayer>().length;
    final cascade = (existing % 5) * 24.0;
    final transform = cascade == 0
        ? LayerTransform.identity
        : LayerTransform(position: Offset(256 + cascade, 256 + cascade));
    return _addLayer(
      () => ImageLayer(
        id: _newId('l'),
        name: resolved,
        assetPath: assetPath,
        transform: transform,
      ),
    );
  }

  /// The smallest unused "Photo N" name on the current frame ("Photo" = N 1).
  String _nextPhotoName() {
    final names = state.layers
        .whereType<ImageLayer>()
        .map((l) => l.name)
        .toSet();
    if (!names.contains('Photo')) return 'Photo';
    var n = 2;
    while (names.contains('Photo $n')) {
      n++;
    }
    return 'Photo $n';
  }

  /// Drops an [emoji] onto the canvas as a decorative (no outline/shadow) text
  /// layer from the sticker library (#61). Centered, large, and selected.
  TextLayer addEmoji(String emoji, {double fontSize = 96}) => _addLayer(
    () => TextLayer(
      id: _newId('l'),
      name: emoji,
      text: emoji,
      fontFamily: 'Rubik',
      fontSize: fontSize,
      decorative: true,
    ),
  );

  void removeLayer(String id) {
    _mutateLayers((layers) => layers.where((l) => l.id != id).toList());
    if (state.selectedLayerId == id) selectLayer(null);
  }

  /// How far a duplicated layer is nudged from its source, in logical px, so
  /// the copy never exactly buries the original.
  static const double duplicateNudge = 16;

  /// Inserts a fresh-id copy of layer [id] directly above the source (one
  /// z-slot later in the bottom-to-top list), nudged by [duplicateNudge], and
  /// selects it. A single undoable step.
  void duplicateLayer(String id) {
    final index = state.layers.indexWhere((l) => l.id == id);
    if (index < 0) return;
    final source = state.layers[index];
    final nudged = source.transform.copyWith(
      position: source.transform.position.translate(
        duplicateNudge,
        duplicateNudge,
      ),
    );
    final clone = _cloneWithNewId(source);
    final copy = switch (clone) {
      ImageLayer() => clone.copyWith(transform: nudged),
      TextLayer() => clone.copyWith(transform: nudged),
      BubbleLayer() => clone.copyWith(transform: nudged),
    };
    _mutateLayers((layers) => [...layers]..insert(index + 1, copy));
    selectLayer(copy.id);
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
    bubble: (l) => l.copyWith(visible: !l.visible),
  );

  void setOpacity(String id, double opacity) => _updateLayer(
    id,
    coalesce: 'opacity:$id',
    image: (l) => l.copyWith(opacity: opacity),
    text: (l) => l.copyWith(opacity: opacity),
    bubble: (l) => l.copyWith(opacity: opacity),
  );

  void updateTransform(String id, LayerTransform transform) => _updateLayer(
    id,
    coalesce: 'transform:$id',
    image: (l) => l.copyWith(transform: transform),
    text: (l) => l.copyWith(transform: transform),
    bubble: (l) => l.copyWith(transform: transform),
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
    bubble: (l) => l.copyWith(name: name),
  );

  /// Adds a comic speech bubble (centred a little above the canvas middle) and
  /// selects it.
  BubbleLayer addBubbleLayer({
    String text = 'Woof!',
    BubbleShape shape = BubbleShape.speech,
  }) => _addLayer(
    () => BubbleLayer(
      id: _newId('l'),
      name: text.isEmpty ? 'Bubble' : text,
      text: text,
      shape: shape,
      transform: const LayerTransform(position: Offset(256, 220)),
    ),
  );

  void updateBubbleLayer(
    String id, {
    String? text,
    BubbleShape? shape,
    String? fontFamily,
    double? fontSize,
    Color? fillColor,
    Color? strokeColor,
    Color? textColor,
    Offset? tail,
  }) {
    // Coalesce per property group, not per bubble — otherwise shape → fill →
    // typing all collapsed into one giant undo step (#82).
    final group = text != null
        ? 'text'
        : shape != null
        ? 'shape'
        : tail != null
        ? 'tail'
        : fontSize != null
        ? 'size'
        : fontFamily != null
        ? 'font'
        : 'color';
    _updateLayer(
      id,
      coalesce: 'bubble:$id:$group',
      bubble: (l) => l.copyWith(
        text: text,
        // Mirror the layer name, but never rename to '' when the caption is
        // cleared (#82) — keep the last non-empty name instead.
        name: text == null || text.trim().isEmpty ? null : text,
        shape: shape,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fillColor: fillColor,
        strokeColor: strokeColor,
        textColor: textColor,
        tail: tail,
      ),
    );
  }

  void updateImageAdjustments(String id, ImageAdjustments adjustments) =>
      _updateLayer(
        id,
        coalesce: 'adjust:$id',
        image: (l) => l.copyWith(adjustments: adjustments),
      );

  /// Sets the die-cut outline width (logical px; 0 disables) and/or color for a
  /// cut-out image layer. Coalesces consecutive slider ticks into one undo step.
  void updateImageOutline(String id, {double? width, Color? color}) =>
      _updateLayer(
        id,
        coalesce: 'outline:$id',
        image: (l) => l.copyWith(
          outlineWidth: width ?? l.outlineWidth,
          outlineColor: color ?? l.outlineColor,
        ),
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
    BubbleLayer Function(BubbleLayer)? bubble,
    String? coalesce,
  }) {
    _mutateLayers(
      (layers) => layers.map((layer) {
        if (layer.id != id) return layer;
        return switch (layer) {
          ImageLayer() => image?.call(layer) ?? layer,
          TextLayer() => text?.call(layer) ?? layer,
          BubbleLayer() => bubble?.call(layer) ?? layer,
        };
      }).toList(),
      coalesce: coalesce,
    );
  }

  // ------------------------------------------------------------ frame ops
  Layer _cloneWithNewId(Layer layer) => switch (layer) {
    ImageLayer() => layer.copyWith(id: _newId('l')),
    TextLayer() => layer.copyWith(id: _newId('l')),
    BubbleLayer() => layer.copyWith(id: _newId('l')),
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
    // Keep viewing the same frame: deleting one before the current shifts it
    // left by one, so decrement to compensate.
    var current = project.currentFrameIndex;
    if (index < current) current -= 1;
    _commit(
      project.copyWith(
        frames: frames,
        currentFrameIndex: current.clamp(0, frames.length - 1),
      ),
      clearSelection: true,
    );
  }

  /// Inserts a copy of frame [index] right after it, and selects the copy.
  void duplicateFrame(int index) {
    final project = state.project;
    if (index < 0 || index >= project.frames.length) return;
    final source = project.frames[index];
    final clone = Frame(
      id: _newId('f'),
      layers: source.layers.map(_cloneWithNewId).toList(),
    );
    final frames = [...project.frames]..insert(index + 1, clone);
    _commit(
      project.copyWith(frames: frames, currentFrameIndex: index + 1),
      clearSelection: true,
    );
  }

  /// Moves the frame at [oldIndex] to [newIndex] as a single undoable step,
  /// mirroring [reorderLayer]'s list-move. The currently viewed frame stays
  /// selected: its index follows the move (tracked by frame id). Out-of-range
  /// or no-op indices are ignored.
  void reorderFrame(int oldIndex, int newIndex) {
    final project = state.project;
    final frames = project.frames;
    if (oldIndex < 0 || oldIndex >= frames.length) return;
    final target = newIndex.clamp(0, frames.length - 1);
    if (target == oldIndex) return;
    final selectedId = frames[project.safeFrameIndex].id;
    final next = [...frames];
    final moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    final current = next.indexWhere((f) => f.id == selectedId);
    _commit(
      project.copyWith(
        frames: next,
        currentFrameIndex: current < 0 ? project.safeFrameIndex : current,
      ),
    );
  }

  /// Renames the project. Blank input is rejected — the old name is kept —
  /// and renaming to the current name is a no-op (no empty undo step).
  void rename(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == state.project.name) return;
    _commit(state.project.copyWith(name: trimmed));
  }

  /// True when [maskPath] is still reachable — referenced by the live document
  /// or by any undo/redo snapshot. A superseded mask PNG may be deleted only
  /// while this is false, so an undo/redo can never surface a missing mask
  /// (drives the delete-on-supersede GC in the editor, #review perf 2026-07-19).
  bool isMaskReferenced(String maskPath) {
    bool inProject(StickerProject project) => project.frames.any(
      (frame) => frame.layers.any(
        (layer) => layer is ImageLayer && layer.maskPath == maskPath,
      ),
    );
    return inProject(state.project) ||
        _undoStack.any(inProject) ||
        _redoStack.any(inProject);
  }
}

/// Editor state for the active document. Override in tests / the editor route
/// to seed a specific project.
final editorControllerProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);
