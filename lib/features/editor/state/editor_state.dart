import 'package:flutter/foundation.dart';

import '../../../core/models/frame.dart';
import '../../../core/models/layer.dart';
import '../../../core/models/sticker_project.dart';
import 'editor_tool.dart';

/// Immutable editor state: the document plus transient UI state (which tool is
/// active and which layer is selected).
@immutable
class EditorState {
  const EditorState({
    required this.project,
    this.selectedLayerId,
    this.tool = EditorTool.adjust,
  });

  final StickerProject project;
  final String? selectedLayerId;
  final EditorTool tool;

  Frame get currentFrame => project.currentFrame;

  /// Layers of the current frame, in z-order (bottom → top).
  List<Layer> get layers => currentFrame.layers;

  Layer? get selectedLayer {
    if (selectedLayerId == null) return null;
    for (final layer in layers) {
      if (layer.id == selectedLayerId) return layer;
    }
    return null;
  }

  EditorState copyWith({
    StickerProject? project,
    String? selectedLayerId,
    bool clearSelection = false,
    EditorTool? tool,
  }) {
    return EditorState(
      project: project ?? this.project,
      selectedLayerId: clearSelection
          ? null
          : (selectedLayerId ?? this.selectedLayerId),
      tool: tool ?? this.tool,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EditorState &&
      other.project == project &&
      other.selectedLayerId == selectedLayerId &&
      other.tool == tool;

  @override
  int get hashCode => Object.hash(project, selectedLayerId, tool);
}
