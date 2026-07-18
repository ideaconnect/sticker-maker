import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/router.dart';
import '../../core/models/frame.dart';
import '../../core/models/image_adjustments.dart';
import '../../core/models/layer.dart';
import '../../core/models/sticker_project.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sm_tokens.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/labeled_slider.dart';
import '../../core/widgets/pill_chip.dart';
import '../../core/widgets/sm_toast.dart';
import '../../core/widgets/tool_tab.dart';
import '../home/project_repository.dart';
import '../segmentation/alpha_mask.dart';
import '../segmentation/mask_brush.dart';
import '../segmentation/mask_processing.dart';
import '../segmentation/mask_store.dart';
import '../segmentation/segmentation_engine.dart';
import '../segmentation/segmentation_registry.dart';
import 'mask_mapper.dart';
import 'services/image_import.dart';
import 'state/editor_controller.dart';
import 'state/editor_state.dart';
import 'state/editor_tool.dart';
import 'widgets/editor_canvas.dart';
import 'widgets/emoji_picker.dart';
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
  final TextEditingController _bubbleTextController = TextEditingController();
  String? _editingBubbleId;

  // Transient tool UI state not yet backed by the model.
  bool _isPlaying = false; // frame playback (M4)
  double _fps = 8; // (M4)
  Timer? _playTimer;
  bool _onionSkin = false; // ghost the previous frame (M4 #37)
  bool _eraseMode = true; // erase vs restore (M2)
  bool _softEdges = true;
  double _brushSize = 40;
  bool _removingBg = false; // AI cut-out in progress

  // Working mask cached across strokes of the Erase tool, so we don't reload
  // and decode the mask file on every dab. Keyed by (layerId, maskPath) so an
  // undo/redo or a layer switch transparently reloads.
  AlphaMask? _workingMask;
  String? _workingMaskLayerId;
  String? _workingMaskPath;
  Size? _workingImageSize;
  // Serializes erase strokes so overlapping async applies can't race and lose
  // dabs (each stroke starts only after the previous one has fully applied).
  Future<void> _strokeLock = Future<void>.value();

  Timer? _saveTimer;
  StickerProject? _pendingSave;
  // Captured during build so dispose() can save without touching `ref`
  // (which is unsafe once the widget is unmounting).
  ProjectRepository? _repo;

  EditorController get _controller =>
      ref.read(editorControllerProvider.notifier);

  void _toast(String m) => showSmToast(context, m);

  /// Closes the current undo step when a slider drag ends.
  void _endSliderEdit(double _) => _controller.endEdit();

  /// Whether two projects are the same *document* — everything that gets
  /// persisted except the transient current-frame index (frame navigation and
  /// playback must not count as edits).
  bool _sameDocument(StickerProject a, StickerProject b) =>
      a.id == b.id && a.name == b.name && listEquals(a.frames, b.frames);

  /// Debounced auto-save of the document to disk.
  void _scheduleSave(StickerProject project) {
    _pendingSave = project;
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 800),
      () => _flushSave(refreshHome: true),
    );
  }

  void _flushSave({bool refreshHome = false}) {
    final project = _pendingSave;
    if (project == null) return;
    _pendingSave = null;
    _repo?.save(project.copyWith(updatedAt: DateTime.now()));
    if (refreshHome && mounted) ref.invalidate(savedProjectsProvider);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _playTimer?.cancel();
    _flushSave(); // persist any pending edit on the way out (no ref use)
    _textController.dispose();
    _bubbleTextController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------- playback
  void _togglePlayback(EditorState editor) {
    if (_isPlaying) {
      _stopPlayback();
    } else if (editor.project.frameCount > 1) {
      setState(() => _isPlaying = true);
      _restartPlayTimer();
    }
  }

  void _restartPlayTimer() {
    _playTimer?.cancel();
    final ms = (1000 / _fps).round().clamp(20, 1000);
    _playTimer = Timer.periodic(Duration(milliseconds: ms), (_) {
      final project = ref.read(editorControllerProvider).project;
      if (project.frameCount <= 1) {
        _stopPlayback();
        return;
      }
      final next = (project.currentFrameIndex + 1) % project.frameCount;
      _controller.selectFrame(next);
    });
  }

  void _stopPlayback() {
    _playTimer?.cancel();
    _playTimer = null;
    if (_isPlaying && mounted) setState(() => _isPlaying = false);
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorControllerProvider);
    _repo = ref.read(projectRepositoryProvider);
    ref.listen(editorControllerProvider, (prev, next) {
      // Persist only real document edits — not frame navigation / playback,
      // which change currentFrameIndex only. Otherwise scrubbing the timeline
      // (or a playback tick) would rewrite the file and bump it to the top of
      // Home's "recent" list with no actual edit.
      if (prev == null || !_sameDocument(prev.project, next.project)) {
        _scheduleSave(next.project);
      }
      // Stop looping playback when the user leaves the Frames tool.
      if (next.tool != EditorTool.frames && _isPlaying) {
        _stopPlayback();
      }
    });
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelMax = math.min(300.0, constraints.maxHeight * 0.5);
            return Column(
              children: [
                _TopBar(
                  title: editor.project.name,
                  canUndo: _controller.canUndo,
                  canRedo: _controller.canRedo,
                  onBack: () => context.pop(),
                  onExport: () => context.pushNamed(Routes.export),
                  onUndo: _controller.undo,
                  onRedo: _controller.redo,
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
                    EditorCanvas(
                      onEmptyTap: () => _pickPhoto(ImageSource.gallery),
                      dropPlaceholder: const DropPlaceholder(),
                      onEraseStroke: _applyEraseStroke,
                      onionFrame: _onionFrame(editor),
                    ),
                    if (_hasCutout(editor)) const _CutBadge(),
                    if (_removingBg) const _RemovingOverlay(),
                    // Which frame you're editing — shown in every tool while the
                    // project is animated (per-frame editing indicator, #36).
                    if (editor.project.frameCount > 1)
                      _FrameCounter(
                        current: editor.project.safeFrameIndex + 1,
                        total: editor.project.frameCount,
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

  bool _hasCutout(EditorState editor) =>
      editor.layers.any((l) => l is ImageLayer && l.maskPath != null);

  /// The previous frame to ghost behind the current one (onion skin), or null
  /// when disabled / not applicable. Suppressed during playback.
  Frame? _onionFrame(EditorState editor) {
    if (!_onionSkin ||
        _isPlaying ||
        editor.tool != EditorTool.frames ||
        editor.project.frameCount < 2) {
      return null;
    }
    final frames = editor.project.frames;
    final prev =
        (editor.project.safeFrameIndex - 1 + frames.length) % frames.length;
    return frames[prev];
  }

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
      EditorTool.text =>
        editor.selectedLayer is BubbleLayer
            ? _bubblePanel(editor)
            : _textPanel(editor),
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
              _controller.updateImageOutline(id, width: 0);
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
          onChangeEnd: _endSliderEdit,
        ),
        LabeledSlider(
          label: 'Contrast',
          value: adj.contrast * 100,
          min: 0,
          max: 200,
          accent: AppColors.cyan,
          valueLabel: '${(adj.contrast * 100).round()}%',
          onChanged: (v) => update(adj.copyWith(contrast: v / 100)),
          onChangeEnd: _endSliderEdit,
        ),
        LabeledSlider(
          label: 'Saturation',
          value: adj.saturation * 100,
          min: 0,
          max: 200,
          accent: AppColors.pink,
          valueLabel: '${(adj.saturation * 100).round()}%',
          onChanged: (v) => update(adj.copyWith(saturation: v / 100)),
          onChangeEnd: _endSliderEdit,
        ),
        LabeledSlider(
          label: 'Hue',
          value: adj.hue,
          min: -180,
          max: 180,
          accent: AppColors.violet,
          valueLabel: '${adj.hue.round()}°',
          onChanged: (v) => update(adj.copyWith(hue: v)),
          onChangeEnd: _endSliderEdit,
        ),
        LabeledSlider(
          label: 'Opacity',
          value: selected.opacity * 100,
          min: 0,
          max: 100,
          accent: AppColors.green,
          valueLabel: '${(selected.opacity * 100).round()}%',
          onChanged: (v) => _controller.setOpacity(id, v / 100),
          onChangeEnd: _endSliderEdit,
        ),
        LabeledSlider(
          label: 'Die-cut outline',
          value: selected.outlineWidth,
          min: 0,
          max: 40,
          accent: AppColors.violetLight,
          valueLabel: selected.outlineWidth < 0.5
              ? 'Off'
              : selected.outlineWidth.round().toString(),
          onChanged: (v) => _controller.updateImageOutline(id, width: v),
          onChangeEnd: _endSliderEdit,
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

    // Resync the field when the selection changes OR when the model text
    // diverges from the field (e.g. after an undo, which clears the selection
    // and reverts the text but leaves the field id/content stale).
    if (_editingTextId != selected.id ||
        _textController.text != selected.text) {
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
          onChangeEnd: _endSliderEdit,
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

  // ------------------------------------------------------------ Bubble
  Widget _bubblePanel(EditorState editor) {
    final bubble = editor.selectedLayer! as BubbleLayer;
    if (_editingBubbleId != bubble.id ||
        _bubbleTextController.text != bubble.text) {
      _editingBubbleId = bubble.id;
      _bubbleTextController.value = TextEditingValue(
        text: bubble.text,
        selection: TextSelection.collapsed(offset: bubble.text.length),
      );
    }
    final id = bubble.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          EditorTool.text,
          trailing: const _PanelHint('Comic bubble'),
        ),
        Row(
          children: [
            for (final s in BubbleShape.values) ...[
              Expanded(
                child: _segTab(
                  _bubbleShapeLabel(s),
                  bubble.shape == s,
                  AppColors.pink,
                  () => _controller.updateBubbleLayer(id, shape: s),
                ),
              ),
              if (s != BubbleShape.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bubbleTextController,
          onChanged: (v) => _controller.updateBubbleLayer(id, text: v),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppFonts.ui,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: 'Bubble text…',
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
        _swatchRow(
          'Fill',
          bubble.fillColor,
          (c) => _controller.updateBubbleLayer(
            id,
            fillColor: c,
            textColor: _inkFor(c),
          ),
        ),
        const SizedBox(height: 10),
        _swatchRow(
          'Outline',
          bubble.strokeColor,
          (c) => _controller.updateBubbleLayer(id, strokeColor: c),
        ),
        const SizedBox(height: 4),
        LabeledSlider(
          label: 'Tail',
          value: bubble.tail.dx,
          min: -1,
          max: 1,
          accent: AppColors.pink,
          valueColor: AppColors.textMuted,
          valueLabel: bubble.tail.dx < -0.15
              ? 'left'
              : (bubble.tail.dx > 0.15 ? 'right' : 'center'),
          onChanged: (v) => _controller.updateBubbleLayer(
            id,
            tail: Offset(v, bubble.tail.dy),
          ),
          onChangeEnd: _endSliderEdit,
        ),
      ],
    );
  }

  String _bubbleShapeLabel(BubbleShape s) => switch (s) {
    BubbleShape.speech => 'Speech',
    BubbleShape.thought => 'Thought',
    BubbleShape.shout => 'Shout',
  };

  /// A labelled row of 9 color swatches for the bubble fill / outline.
  Widget _swatchRow(String label, Color selected, ValueChanged<Color> onPick) {
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
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in colors)
                GestureDetector(
                  onTap: () => onPick(c),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected == c
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.15),
                        width: selected == c ? 3 : 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Contrasting ink for text on a given fill.
  Color _inkFor(Color fill) => (fill == Colors.white || fill == AppColors.amber)
      ? const Color(0xFF14101A)
      : Colors.white;

  // ------------------------------------------------------------ Cut out
  Widget _cutoutPanel(EditorState editor) {
    final selected = editor.selectedLayer;
    final image = selected is ImageLayer ? selected : null;
    final removed = image?.maskPath != null;
    final label = _removingBg
        ? 'Working…'
        : (removed ? 'Undo removal' : 'Remove background');
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
              ? 'Select a photo layer to cut out.'
              : "One tap to isolate your subject. We'll auto-detect the edges — "
                    'refine anything by hand in the Erase tool.',
        ),
        GradientButton(
          label: label,
          icon: Icons.auto_awesome,
          busy: _removingBg,
          gradient: removed ? null : context.sm.cutoutGradient,
          solidColor: removed ? AppColors.neutralButton : null,
          foreground: removed ? AppColors.textSecondary : AppColors.cutoutInk,
          glowColor: AppColors.green,
          onPressed: image == null
              ? null
              : () {
                  if (removed) {
                    _controller.setImageMask(image.id, null);
                    _toast('Background restored');
                  } else {
                    _removeBackground(image);
                  }
                },
        ),
      ],
    );
  }

  /// Runs the AI cut-out for [image]: pick the best available segmentation
  /// engine, clean up the mask, persist it and apply it to the layer (undoable
  /// via the controller's history). Gracefully reports when no engine can run.
  Future<void> _removeBackground(ImageLayer image) async {
    setState(() => _removingBg = true);
    try {
      final registry = ref.read(segmentationRegistryProvider);
      final result = await registry.segment(
        SegmentationRequest(imagePath: image.assetPath),
      );
      if (result == null) {
        if (mounted) {
          _toast("Background removal isn't available on this device yet");
        }
        return;
      }
      final mask = MaskProcessing.process(
        result.mask,
        const MaskProcessingOptions(),
      );
      final path = await ref.read(maskStoreProvider).save(mask, id: image.id);
      _controller.setImageMask(image.id, path);
      if (mounted) _toast('Background removed');
    } catch (_) {
      if (mounted) _toast("Couldn't remove the background — try again");
    } finally {
      if (mounted) setState(() => _removingBg = false);
    }
  }

  /// Enqueues an erase stroke onto [_strokeLock] so strokes apply strictly in
  /// order — overlapping async applies (esp. the cold-cache rebuild-after-await)
  /// can't interleave and drop each other's dabs.
  void _applyEraseStroke(List<Offset> pointsLogical) {
    _strokeLock = _strokeLock
        .then((_) => _runEraseStroke(pointsLogical))
        .catchError((Object _) {});
  }

  /// Applies an Erase/Restore brush stroke (points in 512-logical canvas units)
  /// to the selected photo's alpha mask: map into mask pixels, paint, persist
  /// and apply — undoable per stroke. A working mask is cached across dabs so we
  /// don't decode the mask file every time; it reloads on a layer/mask change.
  Future<void> _runEraseStroke(List<Offset> pointsLogical) async {
    final layer = ref.read(editorControllerProvider).selectedLayer;
    if (layer is! ImageLayer) return;
    try {
      if (_workingMask == null ||
          _workingImageSize == null ||
          _workingMaskLayerId != layer.id ||
          _workingMaskPath != layer.maskPath) {
        final size = await MaskStore.decodeImageSize(layer.assetPath);
        final mask = layer.maskPath != null
            ? await ref.read(maskStoreProvider).load(layer.maskPath!)
            : AlphaMask.filled(size.width.round(), size.height.round(), 255);
        if (!mounted) return;
        _workingImageSize = size;
        _workingMask = mask;
        _workingMaskLayerId = layer.id;
        _workingMaskPath = layer.maskPath;
      }
      final mapper = MaskMapper(
        imageSize: _workingImageSize!,
        position: layer.transform.position,
        layerScale: layer.transform.scale,
        rotation: layer.transform.rotation,
      );
      final maskPoints = <Offset>[
        for (final p in pointsLogical) ?mapper.canvasToMask(p),
      ];
      if (maskPoints.isEmpty) return;
      final painted = MaskBrush.paint(
        _workingMask!,
        BrushStroke(
          points: maskPoints,
          radius: mapper.radiusToMask(_brushSize / 2),
          erase: _eraseMode,
          soft: _softEdges,
        ),
      );
      _workingMask = painted;
      final path = await ref
          .read(maskStoreProvider)
          .save(painted, id: layer.id);
      if (!mounted) return;
      _workingMaskPath = path;
      _controller.setImageMask(layer.id, path);
    } catch (_) {
      if (mounted) _toast("Couldn't apply the brush");
    }
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
            onTap: () => _togglePlayback(editor),
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
              return _FrameThumb(
                index: i,
                frame: frames[i],
                active: i == current,
                onTap: () => _controller.selectFrame(i),
                onMenu: () => _showFrameMenu(i, frames.length),
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
          onChanged: (v) {
            setState(() => _fps = v);
            if (_isPlaying) _restartPlayTimer();
          },
        ),
        if (frames.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'New layers to all frames',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Switch(
                  value: _controller.addToAllFrames,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.orange,
                  onChanged: (v) =>
                      setState(() => _controller.addToAllFrames = v),
                ),
              ],
            ),
          ),
        if (frames.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Onion skin (ghost previous)',
                  style: TextStyle(
                    fontFamily: AppFonts.ui,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Switch(
                value: _onionSkin,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.orange,
                onChanged: (v) => setState(() => _onionSkin = v),
              ),
            ],
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

  /// Long-press menu for a frame: duplicate, or delete (when >1 frame).
  Future<void> _showFrameMenu(int index, int frameCount) async {
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
              Icons.copy_all_outlined,
              'Duplicate frame',
              'duplicate',
            ),
            if (frameCount > 1)
              _sheetTile(ctx, Icons.delete_outline, 'Delete frame', 'delete'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'duplicate':
        _controller.duplicateFrame(index);
      case 'delete':
        _controller.deleteFrame(index);
    }
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

  /// Pastes an image from the clipboard as a new image layer.
  Future<void> _pastePhoto() async {
    final service = ref.read(imageImportServiceProvider);
    try {
      final path = await service.pasteFromClipboard();
      if (path == null) {
        if (mounted) _toast('No image in clipboard');
        return;
      }
      _controller.addImageLayer(assetPath: path);
      _controller.setTool(EditorTool.adjust);
    } catch (_) {
      if (mounted) _toast('Could not paste image');
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
            _sheetTile(ctx, Icons.content_paste, 'Paste image', 'paste'),
            _sheetTile(ctx, Icons.title, 'Add text', 'text'),
            _sheetTile(ctx, Icons.chat_bubble_outline, 'Add bubble', 'bubble'),
            _sheetTile(
              ctx,
              Icons.emoji_emotions_outlined,
              'Add emoji',
              'emoji',
            ),
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
      case 'paste':
        await _pastePhoto();
      case 'text':
        _controller.addTextLayer();
      case 'bubble':
        _controller.addBubbleLayer();
        _controller.setTool(EditorTool.text);
      case 'emoji':
        if (!mounted) return;
        final emoji = await showEmojiPicker(context);
        if (emoji == null) return;
        _controller.addEmoji(emoji);
        _controller.setTool(EditorTool.adjust);
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
    final (Widget badge, String typeLabel) = switch (layer) {
      TextLayer() => (
        const Text(
          'T',
          style: TextStyle(
            fontFamily: AppFonts.bangers,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        'Text layer',
      ),
      BubbleLayer() => (
        const Icon(Icons.chat_bubble_outline, size: 18, color: Colors.white),
        'Bubble layer',
      ),
      ImageLayer() => (
        const Icon(Icons.image_outlined, size: 18, color: Colors.white),
        'Image layer',
      ),
    };
    final flatBadge = layer is! ImageLayer;
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
                    color: flatBadge ? AppColors.elevated : null,
                    gradient: flatBadge ? null : context.sm.logoGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: badge,
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
                        typeLabel,
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

/// Full-canvas overlay shown while the AI cut-out runs.
class _RemovingOverlay extends StatelessWidget {
  const _RemovingOverlay();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: ColoredBox(
        color: Color(0xB2131019),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppColors.greenLight),
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Removing background…',
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Frame N / M" badge shown on the canvas while the Frames tool is active.
class _FrameCounter extends StatelessWidget {
  const _FrameCounter({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xB8131019),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.orange.withValues(alpha: 0.4)),
        ),
        child: Text(
          'Frame $current / $total',
          style: const TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.orange,
          ),
        ),
      ),
    );
  }
}

/// A 64px frame thumbnail in the Frames strip: a live [StickerCanvas] preview
/// over a checkerboard, an active highlight, and a numbered badge.
class _FrameThumb extends StatelessWidget {
  const _FrameThumb({
    required this.index,
    required this.frame,
    required this.active,
    required this.onTap,
    required this.onMenu,
  });

  final int index;
  final Frame frame;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onMenu,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppColors.orange
                : Colors.white.withValues(alpha: 0.08),
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Checkerboard(cell: 6),
              StickerCanvas(frame: frame),
              Positioned(
                top: 3,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xB8131019),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: active ? AppColors.orange : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.canUndo,
    required this.canRedo,
    required this.onBack,
    required this.onExport,
    required this.onUndo,
    required this.onRedo,
  });

  final String title;
  final bool canUndo;
  final bool canRedo;
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
            onPressed: canUndo ? onUndo : null,
            disabledColor: AppColors.textFaint,
            icon: const Icon(Icons.undo, size: 20, color: AppColors.textMuted),
          ),
          IconButton(
            onPressed: canRedo ? onRedo : null,
            disabledColor: AppColors.textFaint,
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
