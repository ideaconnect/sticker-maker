import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/layer.dart';
import '../../../core/models/layer_transform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/checkerboard.dart';
import '../state/editor_controller.dart';
import '../state/editor_state.dart';
import '../state/editor_tool.dart';
import 'sticker_canvas.dart';

/// The interactive editing surface: renders the current frame and lets the user
/// tap to select a layer and drag / pinch / rotate the selected layer directly
/// on the canvas (#19). Transform edits are undo-coalesced by the controller.
class EditorCanvas extends ConsumerStatefulWidget {
  const EditorCanvas({
    super.key,
    required this.onEmptyTap,
    required this.dropPlaceholder,
  });

  /// Tapped when the canvas has no layers (kick off image import).
  final VoidCallback onEmptyTap;

  /// Placeholder shown on an empty canvas.
  final Widget dropPlaceholder;

  @override
  ConsumerState<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends ConsumerState<EditorCanvas> {
  static const double _logical = 512;

  LayerTransform? _startTransform;
  Offset? _startFocal;
  String? _gestureLayerId;

  EditorController get _controller =>
      ref.read(editorControllerProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final scale = side / _logical;
        final selected = editor.selectedLayer;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTap(d.localPosition / scale, editor),
          onScaleStart: (d) => _onScaleStart(d.localFocalPoint / scale, editor),
          onScaleUpdate: (d) => _onScaleUpdate(d, scale),
          onScaleEnd: (_) {
            _gestureLayerId = null;
            _controller.endEdit();
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Checkerboard(),
              if (editor.layers.isEmpty)
                Center(child: widget.dropPlaceholder)
              else
                StickerCanvas(frame: editor.currentFrame),
              if (selected != null && editor.tool != EditorTool.frames)
                _selectionOverlay(selected, scale),
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ gestures
  void _onTap(Offset pointLogical, EditorState editor) {
    if (editor.layers.isEmpty) {
      widget.onEmptyTap();
      return;
    }
    _controller.selectLayer(_hitTest(editor.layers, pointLogical)?.id);
  }

  void _onScaleStart(Offset focalLogical, EditorState editor) {
    final target =
        _hitTest(editor.layers, focalLogical) ?? editor.selectedLayer;
    if (target == null) {
      _gestureLayerId = null;
      return;
    }
    _controller.selectLayer(target.id);
    _gestureLayerId = target.id;
    _startTransform = target.transform;
    _startFocal = focalLogical;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, double scale) {
    final id = _gestureLayerId;
    final start = _startTransform;
    final startFocal = _startFocal;
    if (id == null || start == null || startFocal == null) return;
    final focalLogical = d.localFocalPoint / scale;
    final delta = focalLogical - startFocal;
    _controller.updateTransform(
      id,
      LayerTransform(
        position: start.position + delta,
        scale: (start.scale * d.scale).clamp(0.2, 6.0),
        rotation: start.rotation + d.rotation,
      ),
    );
  }

  // ------------------------------------------------------------ hit-testing
  Layer? _hitTest(List<Layer> layers, Offset p) {
    for (final layer in layers.reversed) {
      if (!layer.visible) continue;
      final size = _sizeOf(layer);
      final c = layer.transform.position;
      // Rotate the point into the layer's local (un-rotated) frame.
      final rel = p - c;
      final a = -layer.transform.rotation;
      final cosA = math.cos(a);
      final sinA = math.sin(a);
      final local = Offset(
        rel.dx * cosA - rel.dy * sinA,
        rel.dx * sinA + rel.dy * cosA,
      );
      if (local.dx.abs() <= size.width / 2 &&
          local.dy.abs() <= size.height / 2) {
        return layer;
      }
    }
    return null;
  }

  /// The layer's bounding size in 512-logical units, including its own scale.
  Size _sizeOf(Layer layer) {
    final s = layer.transform.scale;
    return switch (layer) {
      ImageLayer() => Size(440 * s, 440 * s),
      TextLayer() => () {
        final tp = TextPainter(
          text: TextSpan(
            text: layer.text.isEmpty ? ' ' : layer.text,
            style: TextStyle(
              fontFamily: layer.fontFamily,
              fontSize: layer.fontSize,
              height: 1,
              letterSpacing: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        return Size(tp.width * s, tp.height * s);
      }(),
    };
  }

  // ------------------------------------------------------------ selection UI
  Widget _selectionOverlay(Layer layer, double scale) {
    const pad = 10.0;
    final size = _sizeOf(layer);
    final wPx = size.width * scale + pad * 2;
    final hPx = size.height * scale + pad * 2;
    final center = layer.transform.position * scale;
    return Positioned(
      left: center.dx - wPx / 2,
      top: center.dy - hPx / 2,
      width: wPx,
      height: hPx,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: layer.transform.rotation,
          child: CustomPaint(painter: _SelectionPainter()),
        ),
      ),
    );
  }
}

/// Draws the selection frame: a rounded border, four corner handles and a top
/// rotate handle, in the selection accent color.
class _SelectionPainter extends CustomPainter {
  static const Color _c = AppColors.cyan;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _c;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(10)),
      border,
    );

    final handle = Paint()..color = _c;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF131019);
    const r = 4.0;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: 8, height: 8),
        handle,
      );
      canvas.drawRect(
        Rect.fromCenter(center: corner, width: 8, height: 8),
        ring,
      );
    }
    // Rotate handle above the top edge.
    final topCenter = Offset(size.width / 2, 0);
    final knob = topCenter.translate(0, -18);
    canvas.drawLine(topCenter, knob, border);
    canvas.drawCircle(knob, r + 1, handle);
    canvas.drawCircle(knob, r + 1, ring);
  }

  @override
  bool shouldRepaint(_SelectionPainter oldDelegate) => false;
}

/// The dashed "drop a photo here" placeholder shown on an empty canvas.
class DropPlaceholder extends StatelessWidget {
  const DropPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
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
    );
  }
}
