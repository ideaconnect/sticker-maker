import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/sm_tokens.dart';
import '../../core/widgets/checkerboard.dart';
import '../../core/widgets/gradient_button.dart';
import '../../core/widgets/labeled_slider.dart';
import '../../core/widgets/pill_chip.dart';
import '../../core/widgets/sm_toast.dart';
import '../../core/widgets/sticker_caption.dart';
import '../../core/widgets/tool_tab.dart';

/// Editor shell: top bar, sticker canvas, a contextual panel that swaps per
/// tool, and the six-tab tool bar. The real editing engine (canvas gestures,
/// AI cut-out, encoders) arrives in later milestones — this establishes the
/// chrome and design language.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  SmAccent _tool = SmAccent.adjust;

  // Adjust
  double _brightness = 104,
      _contrast = 108,
      _saturation = 118,
      _hue = 0,
      _opacity = 100;

  // Text
  late final TextEditingController _textController = TextEditingController(
    text: _textValue,
  );
  String _textValue = 'WOOF!';
  String _textFont = AppFonts.bangers;
  Color _textColor = Colors.white;
  double _textSize = 40;
  final bool _hasText = true;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // Cut out
  bool _bgRemoved = false;

  // Erase
  double _brushSize = 40;
  bool _eraseMode = true; // true=erase, false=restore
  bool _softEdges = true;

  // Frames
  int _frameCount = 3;
  int _currentFrame = 0;
  double _fps = 8;
  bool _isPlaying = false;

  void _toast(String m) => showSmToast(context, m);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Cap the panel so the fixed chrome (top bar + tool bar + panel)
            // can never exceed the available height — e.g. when the keyboard
            // opens in the Text tool, or in split-screen. The canvas Expanded
            // absorbs the rest; the panel's own scroll view handles overflow.
            final panelMax = math.min(300.0, constraints.maxHeight * 0.5);
            return Column(
              children: [
                _TopBar(
                  onBack: () => context.pop(),
                  onExport: () => context.pushNamed(Routes.export),
                  onUndo: () => _toast('Undo'),
                  onRedo: () => _toast('Redo'),
                ),
                Expanded(child: _canvas()),
                _panel(panelMax),
                _toolBar(),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- canvas
  Widget _canvas() {
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
                    const Checkerboard(),
                    _subject(),
                    if (_bgRemoved) _cutBadge(),
                    if (_hasText) _textOverlay(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _subject() {
    return Center(
      child: Opacity(
        opacity: (_opacity / 100).clamp(0, 1),
        child: DottedPlaceholder(
          onTap: () => _toast('Photo import arrives in M1'),
        ),
      ),
    );
  }

  Widget _cutBadge() {
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

  Widget _textOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 24,
      child: Center(
        child: StickerCaption(
          text: _textValue,
          fontFamily: _textFont,
          fontSize: _textSize,
          color: _textColor,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- panel
  Widget _panel(double maxHeight) {
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
      child: SingleChildScrollView(child: _panelBody()),
    );
  }

  Widget _panelBody() {
    switch (_tool) {
      case SmAccent.adjust:
        return _adjustPanel();
      case SmAccent.text:
        return _textPanel();
      case SmAccent.cutout:
        return _cutoutPanel();
      case SmAccent.erase:
        return _erasePanel();
      case SmAccent.frames:
        return _framesPanel();
      case SmAccent.layers:
        return _layersPanel();
    }
  }

  Widget _panelHeader(String title, SmAccent accent, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: context.sm.accent(accent),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _adjustPanel() {
    return Column(
      children: [
        _panelHeader(
          'Adjust',
          SmAccent.adjust,
          trailing: PillChip(
            label: 'Reset',
            onTap: () => setState(() {
              _brightness = 100;
              _contrast = 100;
              _saturation = 100;
              _hue = 0;
              _opacity = 100;
            }),
          ),
        ),
        LabeledSlider(
          label: 'Brightness',
          value: _brightness,
          min: 0,
          max: 200,
          accent: AppColors.amber,
          valueLabel: '${_brightness.round()}%',
          onChanged: (v) => setState(() => _brightness = v),
        ),
        LabeledSlider(
          label: 'Contrast',
          value: _contrast,
          min: 0,
          max: 200,
          accent: AppColors.cyan,
          valueLabel: '${_contrast.round()}%',
          onChanged: (v) => setState(() => _contrast = v),
        ),
        LabeledSlider(
          label: 'Saturation',
          value: _saturation,
          min: 0,
          max: 200,
          accent: AppColors.pink,
          valueLabel: '${_saturation.round()}%',
          onChanged: (v) => setState(() => _saturation = v),
        ),
        LabeledSlider(
          label: 'Hue',
          value: _hue,
          min: -180,
          max: 180,
          accent: AppColors.violet,
          valueLabel: '${_hue.round()}°',
          onChanged: (v) => setState(() => _hue = v),
        ),
        LabeledSlider(
          label: 'Opacity',
          value: _opacity,
          min: 0,
          max: 100,
          accent: AppColors.green,
          valueLabel: '${_opacity.round()}%',
          onChanged: (v) => setState(() => _opacity = v),
        ),
      ],
    );
  }

  Widget _textPanel() {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          'Text',
          SmAccent.text,
          trailing: const _PanelHint('Tap a font to preview'),
        ),
        TextField(
          controller: _textController,
          onChanged: (v) => setState(() => _textValue = v),
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
              return PillChip(
                label: f,
                accent: AppColors.pink,
                selected: _textFont == f,
                radius: 12,
                onTap: () => setState(() => _textFont = f),
                labelStyle: TextStyle(
                  fontFamily: f,
                  fontSize: 16,
                  color: _textFont == f
                      ? Colors.white
                      : AppColors.textSecondary,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        LabeledSlider(
          label: 'Size',
          value: _textSize,
          min: 16,
          max: 72,
          accent: AppColors.pink,
          valueColor: AppColors.textMuted,
          valueLabel: '${_textSize.round()}px',
          onChanged: (v) => setState(() => _textSize = v),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final c in colors)
              GestureDetector(
                onTap: () => setState(() => _textColor = c),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _textColor == c
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.15),
                      width: _textColor == c ? 3 : 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _cutoutPanel() {
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
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            "One tap to isolate your pet. We'll auto-detect edges — refine "
            'anything by hand in the Erase tool.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 12.5,
              color: AppColors.textMuted,
              height: 1.5,
            ),
          ),
        ),
        GradientButton(
          label: _bgRemoved ? 'Undo removal' : 'Remove background',
          icon: Icons.auto_awesome,
          gradient: _bgRemoved ? null : context.sm.cutoutGradient,
          solidColor: _bgRemoved ? AppColors.neutralButton : null,
          foreground: _bgRemoved
              ? AppColors.textSecondary
              : AppColors.cutoutInk,
          glowColor: AppColors.green,
          onPressed: () {
            setState(() => _bgRemoved = !_bgRemoved);
            _toast(_bgRemoved ? 'Background removed' : 'Background restored');
          },
        ),
      ],
    );
  }

  Widget _erasePanel() {
    final brushPreview = (_brushSize * 0.4).clamp(8.0, 40.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          'Manual erase',
          SmAccent.erase,
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

  Widget _framesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          'Animation frames',
          SmAccent.frames,
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
            itemCount: _frameCount + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              if (i == _frameCount) {
                return _addFrameButton();
              }
              final active = i == _currentFrame;
              return GestureDetector(
                onTap: () => setState(() => _currentFrame = i),
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
      onTap: () => setState(() {
        _frameCount++;
        _currentFrame = _frameCount - 1;
      }),
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

  Widget _layersPanel() {
    final rows = [
      ('WOOF!', 'Text layer', true),
      ('Rex (photo)', 'Image layer', false),
      ('Background', 'Image layer', false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelHeader(
          'Layers',
          SmAccent.layers,
          trailing: PillChip(
            label: 'Add',
            icon: Icons.add,
            onTap: () => _toast('Layer added'),
          ),
        ),
        for (final (name, type, isText) in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardAlt,
              borderRadius: BorderRadius.circular(14),
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
                      : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        type,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
      ],
    );
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
  Widget _toolBar() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF141019)),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Row(
        children: [
          _tab('Layers', Icons.layers_outlined, SmAccent.layers),
          _tab('Adjust', Icons.tune, SmAccent.adjust),
          _tab('Text', Icons.text_fields, SmAccent.text),
          _tab('Erase', Icons.brush_outlined, SmAccent.erase),
          _tab('Cut out', Icons.auto_awesome_outlined, SmAccent.cutout),
          _tab('Frames', Icons.animation, SmAccent.frames),
        ],
      ),
    );
  }

  Widget _tab(String label, IconData icon, SmAccent accent) {
    return ToolTab(
      label: label,
      icon: icon,
      accent: context.sm.accent(accent),
      active: _tool == accent,
      onTap: () => setState(() => _tool = accent),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onExport,
    required this.onUndo,
    required this.onRedo,
  });

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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rex woof',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
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
