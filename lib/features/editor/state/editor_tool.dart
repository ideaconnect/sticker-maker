import 'package:flutter/material.dart';

import '../../../core/theme/sm_tokens.dart';

/// The six editor tools, each carrying its own presentation. This is the single
/// source of truth for the tool set; [SmAccent] stays a pure color key in the
/// theme layer and is mapped from here.
enum EditorTool {
  layers('Layers', 'Layers', Icons.layers_outlined, SmAccent.layers),
  adjust('Adjust', 'Adjust', Icons.tune, SmAccent.adjust),
  text('Text', 'Text', Icons.text_fields, SmAccent.text),
  erase('Erase', 'Manual erase', Icons.brush_outlined, SmAccent.erase),
  cutout(
    'Cut out',
    'AI Background Removal',
    Icons.auto_awesome_outlined,
    SmAccent.cutout,
  ),
  frames('Frames', 'Animation frames', Icons.animation, SmAccent.frames);

  const EditorTool(this.tabLabel, this.panelTitle, this.icon, this.accent);

  /// Short label shown in the bottom tool bar.
  final String tabLabel;

  /// Longer title shown at the top of the tool's contextual panel.
  final String panelTitle;

  final IconData icon;

  /// Color key resolved against [SmTokens].
  final SmAccent accent;
}
