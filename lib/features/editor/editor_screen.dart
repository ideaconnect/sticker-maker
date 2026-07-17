import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router.dart';
import '../../core/models/image_adjustments.dart';
import '../../core/models/layer.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sm_tokens.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/labeled_slider.dart';
import '../../core/widgets/pill_chip.dart';
import '../../core/widgets/sm_toast.dart';
import '../../core/widgets/tool_tab.dart';
import 'services/image_import.dart';
import 'state/editor_controller.dart';
import 'state/editor_state.dart';
import 'state/editor_tool.dart';
import 'widgets/sticker_canvas.dart';

/// Editor: top bar, model-driven sticker canvas, a contextual panel that swaps
/// per tool, and the six-tab tool bar. State lives in [editorControllerProvider];
/// this widget renders it and dispatches edits. Image-dependent tools (Adjust,
/// Cut out, Erase) wait on image import (#21) / AI segmentation (#2).
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  final TextEditingController _textController = TextEditingController();
  String? _editingTextId;

  // Transient tool UI state not yet backed by the model.
  bool _isPlaying = false; // frame playback (M4)
  double _fps = 8; // (M4)
  bool _eraseMode = true; // erase vs restore (M2)
  bool _softEdges = true;
  double _brushSize = 40;

  EditorController get _controller =>
      ref.read(editorControllerProvider.notifier);

  void _toast(String m) => showSmToast(context, m);

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelMax = math.min(300.0, constraints.maxHeight * 0.5);
            return Column(
              children: [
                _TopBar(
                  title: editor.project.name,
                  onBack: () => context.pop(),
                  onExport: () => context.pushNamed(Routes.export),
                  onUndo: () => _toast('Undo'),
                  onRedo: () => _toast('Redo'),
                ),
                Expanded(child: _canvas(editor)),
                _panel(editor, panelMax),
                _toolBar(editor),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- canvas
  Widget _canvas(EditorState editor) {
    final tokens = context.sm;
    final selected = editor.selectedLayer;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(tokens.radiusCanvas),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x80000000),
                    blurRadius: 50,
                    offset: Offset(0, 20),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens.radiusCanvas),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Checkerboard(),
                    if (editor.layers.isEmpty)
                      Center(
                        child: DottedPlaceholder(
                          onTap: () => _pickPhoto(ImageSource.gallery),
                        ),
                      )
                    else
                      StickerCanvas(frame: editor.currentFrame),
                    if (_hasCutout(editor)) const _CutBadge(),
                    if (selected != null && editor.tool != EditorTool.frames)
                      _SelectionFrame(name: selected.name),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _hasCutout(EditorState editor) =>
      editor.layers.any((l) => l is ImageLayer && l.maskPath != null);

  // ---------------------------------------------------------------- panel
  Widget _panel(EditorState editor, double maxHeight) {
    final tokens = context.sm;
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: tokens.border)),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(tokens.radiusPanel),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: SingleChildScrollView(child: _panelBody(editor)),
    );
  }

  Widget _panelBody(EditorState editor) {
    return switch (editor.tool) {
      EditorTool.adjust => _adjustPanel(editor),
      EditorTool.text => _textPanel(editor),
      EditorTool.cutout => _cutoutPanel(editor),
      EditorTool.erase => _erasePanel(),
      EditorTool.frames => _framesPanel(editor),
      EditorTool.layers => _layersPanel(editor),
    };
  }

  Widget _panelHeader(EditorTool tool, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            tool.panelTitle,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: context.sm.accent(tool.accent),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _emptyHint(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 12.5,
          color: AppColors.textMuted,
          height: 1.5,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ Adjust
  Widget _adjustPanel(EditorState editor) {
    final selected = editor.selectedLayer;
    if (selected is! ImageLayer) {
      return Column(
        children: [
          _panelHeader(EditorTool.adjust),
          _emptyHint(
            'Adjustments apply to a photo layer.\nAdd a photo (import lands in M1, #21).',
          ),
        ],
      );
    }
    final id = selected.id;
    final adj = selected.adjustments;
    void update(ImageAdjustments next) =>
        _controller.updateImageAdjustments(id, next);
    return Column(
      children: [
        _panelHeader(
          EditorTool.adjust,
          trailing: PillChip(
            label: 'Reset',
            onTap: () {
              _controller.updateImageAdjustments(id, ImageAdjustments.identity);
              _controller.setOpacity(id, 1);
            },
          ),
        ),
        LabeledSlider(
          label: 'Brightness',
          value: adj.brightness * 100,
          min: 0,
          max: 200,
          accent: AppColors.amber,
          valueLabel: '${(adj.brightness * 100).round()}%',
          onChanged: (v) => update(adj.copyWith(brightness: v / 100)),
        ),
        LabeledSlider(
          label: 'Contrast',
          value: adj.contrast * 100,
          min: 0,
          max: 200,
          accent: AppColors.cyan,
          valueLabel: '${(adj.contrast * 100).round()}%',
          onChanged: (v) => update(adj.copyWith(contrast: v / 100)),
        ),
        LabeledSlider(
          label: 'Saturation',
          value: adj.saturation * 100,
          min: 0,
          max: 200,
          accent: AppColors.pink,
          valueLabel: '${(adj.saturation * 100).round()}%',
          onChanged: (v) => update(adj.copyWith(saturation: v / 100)),
        ),
        LabeledSlider(
          label: 'Hue',
          value: adj.hue,
          min: -180,
          max: 180,
          accent: AppColors.violet,
          valueLabel: '${adj.hue.round()}°',
          onChanged: (v) => update(adj.copyWith(hue: v)),
        ),
        LabeledSlider(
          label: 'Opacity',
          value: selected.opacity * 100,
          min: 0,
          max: 100,
          accent: AppColors.green,
          valueLabel: '${(selected.opacity * 100).round()}%',
          onChanged: (v) => _controller.setOpacity(id, v / 100),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Text
  Widget _textPanel(EditorState editor) {
    const colors = [
      Colors.white,
      Color(0xFF111111),
      AppColors.pink,
      AppColors.amber,
      AppColors.green,
      AppColors.cyan,
      AppColors.violet,
      AppColors.rose,
      AppColors.orange,
    ];

    final selected = editor.selectedLayer;
    if (selected is! TextLayer) {
      return Column(
        children: [
          _panelHeader(EditorTool.text),
          _emptyHint('Select a text layer, or add one.'),
          GradientButton(
            label: 'Add text',
            icon: Icons.add,
            gradient: LinearGradient(
              colors: [AppColors.pink, AppColors.pink.withValues(alpha: 0.7)],
            ),
            glowColor: AppColors.pink,
            onPressed: () => _controller.addTextLayer(text: 'Woof!'),
          ),
        ],
      );
    }

    // Sync the field to the selected layer only when the selection changes.
    if (_editingTextId != selected.id) {
      _editingTextId = selected.id;
      _textController.value = TextEditingValue(
        text: selected.text,
        selection: TextSelection.collapsed(offset: selected.text.length),
      );
    }
    final id = selected.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          EditorTool.text,
          trailing: const _PanelHint('Tap a font to preview'),
        ),
        TextField(
          controller: _textController,
          onChanged: (v) => _controller.updateTextLayer(id, text: v),
          style: const TextStyle(
            fontFamily: AppFonts.ui,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Type your caption…',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.inputField,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 11,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: AppFonts.stickerFonts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 9),
            itemBuilder: (_, i) {
              final f = AppFonts.stickerFonts[i];
              final active = selected.fontFamily == f;
              return PillChip(
                label: f,
                accent: AppColors.pink,
                selected: active,
                radius: 12,
                onTap: () => _controller.updateTextLayer(id, fontFamily: f),
                labelStyle: TextStyle(
                  fontFamily: f,
                  fontSize: 16,
                  color: active ? Colors.white : AppColors.textSecondary,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        LabeledSlider(
          label: 'Size',
          value: selected.fontSize,
          min: 16,
          max: 72,
          accent: AppColors.pink,
          valueColor: AppColors.textMuted,
          valueLabel: '${selected.fontSize.round()}px',
          onChanged: (v) => _controller.updateTextLayer(id, fontSize: v),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final c in colors)
              GestureDetector(
                onTap: () => _controller.updateTextLayer(id, color: c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected.color == c
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.15),
                      width: selected.color == c ? 3 : 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Cut out
  Widget _cutoutPanel(EditorState editor) {
    final selected = editor.selectedLayer;
    final image = selected is ImageLayer ? selected : null;
    final removed = image?.maskPath != null;
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'AI Background Removal',
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: AppColors.green,
            ),
          ),
        ),
        _emptyHint(
          image == null
              ? 'Select a photo layer to cut out.\nOn-device AI removal lands in M2 (#26).'
              : "One tap to isolate your pet. We'll auto-detect edges — refine "
                    'anything by hand in the Erase tool.',
        ),
        GradientButton(
          label: removed ? 'Undo removal' : 'Remove background',
          icon: Icons.auto_awesome,
          gradient: removed ? null : context.sm.cutoutGradient,
          solidColor: removed ? AppColors.neutralButton : null,
          foreground: removed ? AppColors.textSecondary : AppColors.cutoutInk,
          glowColor: AppColors.green,
          onPressed: image == null
              ? null
              : () {
                  // Placeholder for the real M2 pipeline: toggle a mask marker.
                  _controller.setImageMask(
                    image.id,
                    removed ? null : '${image.id}.mask',
                  );
                  _toast(
                    removed ? 'Background restored' : 'Background removed',
                  );
                },
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Erase
  Widget _erasePanel() {
    final brushPreview = (_brushSize * 0.4).clamp(8.0, 40.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          EditorTool.erase,
          trailing: const _PanelHint('Brush over the canvas'),
        ),
        Row(
          children: [
            Expanded(
              child: _segTab(
                'Erase',
                _eraseMode,
                AppColors.amber,
                () => setState(() => _eraseMode = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _segTab(
                'Restore',
                !_eraseMode,
                AppColors.green,
                () => setState(() => _eraseMode = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: LabeledSlider(
                label: 'Brush size',
                value: _brushSize,
                min: 8,
                max: 120,
                accent: AppColors.amber,
                valueColor: AppColors.textMuted,
                valueLabel: '${_brushSize.round()}px',
                onChanged: (v) => setState(() => _brushSize = v),
              ),
            ),
            const SizedBox(width: 14),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: brushPreview,
                height: brushPreview,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.amber.withValues(alpha: 0.25),
                  border: Border.all(color: AppColors.amber, width: 2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Soft edges',
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            Switch(
              value: _softEdges,
              activeThumbColor: Colors.white,
              activeTrackColor: AppColors.amber,
              onChanged: (v) => setState(() => _softEdges = v),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ Frames
  Widget _framesPanel(EditorState editor) {
    final frames = editor.project.frames;
    final current = editor.project.currentFrameIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          EditorTool.frames,
          trailing: PillChip(
            label: _isPlaying ? 'Pause' : 'Play',
            icon: _isPlaying ? Icons.pause : Icons.play_arrow,
            accent: AppColors.orange,
            selected: true,
            onTap: () => setState(() => _isPlaying = !_isPlaying),
          ),
        ),
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: frames.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (i == frames.length) return _addFrameButton();
              final active = i == current;
              return GestureDetector(
                onTap: () => _controller.selectFrame(i),
                onLongPress: frames.length > 1
                    ? () => _controller.deleteFrame(i)
                    : null,
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.topLeft,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active
                          ? AppColors.orange
                          : Colors.white.withValues(alpha: 0.08),
                      width: 2,
                    ),
                    color: AppColors.cardAlt,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: active ? AppColors.orange : AppColors.textMuted,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        LabeledSlider(
          label: 'Speed',
          value: _fps,
          min: 2,
          max: 24,
          accent: AppColors.orange,
          valueColor: AppColors.textMuted,
          valueLabel: '${_fps.round()} fps',
          onChanged: (v) => setState(() => _fps = v),
        ),
      ],
    );
  }

  Widget _addFrameButton() {
    return GestureDetector(
      onTap: _controller.addFrame,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.orange.withValues(alpha: 0.4),
            width: 2,
          ),
        ),
        child: const Icon(Icons.add, color: AppColors.orange),
      ),
    );
  }

  // ------------------------------------------------------------ Layers
  Widget _layersPanel(EditorState editor) {
    final layers = editor.layers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          EditorTool.layers,
          trailing: PillChip(
            label: 'Add',
            icon: Icons.add,
            onTap: _showAddMenu,
          ),
        ),
        if (layers.isEmpty)
          _emptyHint('No layers yet. Tap Add to import a photo or add text.')
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: layers.length,
            onReorderItem: (oldIndex, newIndex) =>
                _controller.reorderLayer(oldIndex, newIndex),
            itemBuilder: (context, i) {
              final layer = layers[i];
              return _LayerRow(
                key: ValueKey(layer.id),
                layer: layer,
                selected: editor.selectedLayerId == layer.id,
                onSelect: () => _controller.selectLayer(layer.id),
                onRename: () => _showRenameDialog(layer),
                onToggleVisibility: () =>
                    _controller.toggleVisibility(layer.id),
                onDelete: () => _controller.removeLayer(layer.id),
              );
            },
          ),
      ],
    );
  }

  /// Imports a photo from the given [source] and adds it as an image layer.
  Future<void> _pickPhoto(ImageSource source) async {
    final service = ref.read(imageImportServiceProvider);
    try {
      final path = source == ImageSource.camera
          ? await service.pickFromCamera()
          : await service.pickFromGallery();
      if (path == null) return; // cancelled
      _controller.addImageLayer(assetPath: path);
      _controller.setTool(EditorTool.adjust);
    } catch (_) {
      if (mounted) _toast('Could not import photo');
    }
  }

  /// Bottom sheet to add a layer: a photo (camera / gallery) or text.
  Future<void> _showAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetTile(
              ctx,
              Icons.photo_camera_outlined,
              'Take photo',
              'camera',
            ),
            _sheetTile(
              ctx,
              Icons.photo_library_outlined,
              'Choose photo',
              'gallery',
            ),
            _sheetTile(ctx, Icons.title, 'Add text', 'text'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'camera':
        await _pickPhoto(ImageSource.camera);
      case 'gallery':
        await _pickPhoto(ImageSource.gallery);
      case 'text':
        _controller.addTextLayer();
    }
  }

  Widget _sheetTile(
    BuildContext ctx,
    IconData icon,
    String label,
    String value,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.textPrimary,
        ),
      ),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _showRenameDialog(Layer layer) async {
    var value = layer.name;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Rename layer',
          style: TextStyle(
            fontFamily: AppFonts.display,
            color: AppColors.textPrimary,
          ),
        ),
        // TextFormField owns and disposes its own controller.
        content: TextFormField(
          initialValue: layer.name,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          onChanged: (v) => value = v,
          onFieldSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, value.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      _controller.renameLayer(layer.id, name);
    }
  }

  Widget _segTab(String label, bool active, Color accent, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.18) : AppColors.inputField,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: active ? accent : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- tool bar
  Widget _toolBar(EditorState editor) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF141019)),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Row(
        children: [
          for (final tool in EditorTool.values)
            ToolTab(
              label: tool.tabLabel,
              icon: tool.icon,
              accent: context.sm.accent(tool.accent),
              active: editor.tool == tool,
              onTap: () => _controller.setTool(tool),
            ),
        ],
      ),
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.layer,
    required this.selected,
    required this.onSelect,
    required this.onRename,
    required this.onToggleVisibility,
    required this.onDelete,
  });

  final Layer layer;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  final VoidCallback onToggleVisibility;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isText = layer is TextLayer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onSelect,
          onLongPress: onRename,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.violet.withValues(alpha: 0.14)
                  : AppColors.cardAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.violet : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isText ? AppColors.elevated : null,
                    gradient: isText ? null : context.sm.logoGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: isText
                      ? const Text(
                          'T',
                          style: TextStyle(
                            fontFamily: AppFonts.bangers,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.image_outlined,
                          size: 18,
                          color: Colors.white,
                        ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        layer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        isText ? 'Text layer' : 'Image layer',
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    layer.visible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                    color: layer.visible
                        ? AppColors.textSecondary
                        : AppColors.textFaint,
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CutBadge extends StatelessWidget {
  const _CutBadge();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.green.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.green.withValues(alpha: 0.5)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 13, color: AppColors.greenLight),
            SizedBox(width: 5),
            Text(
              'Cut out',
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.greenLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A static selection indicator drawn around the canvas while a layer is
/// selected. Interactive drag handles arrive with gesture transforms (#19).
class _SelectionFrame extends StatelessWidget {
  const _SelectionFrame({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.cyan, width: 1.5),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Transform.translate(
                offset: const Offset(0, -10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cyan,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF06121A),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.onExport,
    required this.onUndo,
    required this.onRedo,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onExport;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(
              Icons.chevron_left,
              size: 26,
              color: AppColors.textSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Text(
                  '512 × 512 · transparent',
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 10.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onUndo,
            icon: const Icon(Icons.undo, size: 20, color: AppColors.textMuted),
          ),
          IconButton(
            onPressed: onRedo,
            icon: const Icon(Icons.redo, size: 20, color: AppColors.textMuted),
          ),
          const SizedBox(width: 4),
          GradientButton(
            label: 'Export',
            icon: Icons.ios_share,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            fontSize: 13,
            onPressed: onExport,
          ),
        ],
      ),
    );
  }
}

/// Small right-aligned helper text shown next to a panel title.
class _PanelHint extends StatelessWidget {
  const _PanelHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 11,
        color: AppColors.textMuted,
      ),
    );
  }
}

/// The dashed "drop a photo here" placeholder shown on an empty canvas.
class DottedPlaceholder extends StatelessWidget {
  const DottedPlaceholder({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: FractionallySizedBox(
        widthFactor: 0.62,
        heightFactor: 0.62,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 2,
            ),
          ),
          child: const Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 34,
                      color: AppColors.textMuted,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Drop your pet photo',
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
