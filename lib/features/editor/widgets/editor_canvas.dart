import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/frame.dart';
import '../../../core/models/layer.dart';
import '../../../core/models/layer_transform.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/checkerboard.dart';
import '../state/editor_controller.dart';
import '../state/editor_state.dart';
import '../state/editor_tool.dart';
import 'bubble_view.dart';
import 'sticker_canvas.dart';

/// The interactive editing surface: renders the current frame and lets the user
/// tap to select a layer and drag / pinch / rotate the selected layer directly
/// on the canvas (#19). Transform edits are undo-coalesced by the controller.
class EditorCanvas extends ConsumerStatefulWidget {
  const EditorCanvas({
    super.key,
    required this.onEmptyTap,
    required this.dropPlaceholder,
    this.onEraseStroke,
    this.onObjectTap,
    this.onionFrame,
  });

  /// Tapped when the canvas has no layers (kick off image import).
  final VoidCallback onEmptyTap;

  /// Placeholder shown on an empty canvas.
  final Widget dropPlaceholder;

  /// When set, this frame is drawn ghosted behind the current one (onion skin).
  final Frame? onionFrame;

  /// Called with a brush stroke (points in 512-logical canvas units) when the
  /// Erase tool is active over the selected image layer.
  final void Function(List<Offset> pointsLogical)? onEraseStroke;

  /// When non-null and the Cut-out tool is active over the selected image
  /// layer, a tap becomes "remove the object under the finger" (#83) instead
  /// of layer selection. Point in 512-logical canvas units.
  final void Function(Offset pointLogical)? onObjectTap;

  @override
  ConsumerState<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends ConsumerState<EditorCanvas> {
  static const double _logical = 512;

  /// Decoded pixel size per photo assetPath, so hit boxes and the selection
  /// frame match the BoxFit.contain content rect instead of the full 440
  /// square (#74). Read from the encoded header only — pixels are never
  /// decoded here.
  final Map<String, Size> _imageDims = {};
  final Set<String> _dimsLoading = {};

  LayerTransform? _startTransform;
  Offset? _startFocal;
  String? _gestureLayerId;

  /// Non-null while a brush stroke is being drawn (Erase tool). Points are in
  /// 512-logical canvas units.
  List<Offset>? _strokePoints;

  EditorController get _controller =>
      ref.read(editorControllerProvider.notifier);

  bool _isErasing(EditorState editor) =>
      editor.tool == EditorTool.erase && editor.selectedLayer is ImageLayer;

  /// Loads (and caches) the pixel dimensions of [path] from the encoded image
  /// header. Fire-and-forget: until it lands, hit-testing falls back to the
  /// full square, which is the pre-#74 behavior. Deliberately NOT timer-based
  /// (a pending zero-duration timer trips widget tests).
  void _ensureDims(String path) {
    if (_imageDims.containsKey(path) || !_dimsLoading.add(path)) return;
    unawaited(_loadDims(path));
  }

  Future<void> _loadDims(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      buffer.dispose();
      final size = Size(
        descriptor.width.toDouble(),
        descriptor.height.toDouble(),
      );
      descriptor.dispose();
      if (mounted) setState(() => _imageDims[path] = size);
    } catch (_) {
      // Unreadable file — keep the square fallback (and don't retry).
      if (mounted) _imageDims[path] = Size.zero;
    } finally {
      _dimsLoading.remove(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorControllerProvider);
    for (final layer in editor.layers.whereType<ImageLayer>()) {
      _ensureDims(layer.assetPath);
    }
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
          onScaleEnd: (_) => _onScaleEnd(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Checkerboard(),
              if (widget.onionFrame != null)
                Opacity(
                  opacity: 0.25,
                  child: StickerCanvas(frame: widget.onionFrame!),
                ),
              if (editor.layers.isEmpty)
                Center(child: widget.dropPlaceholder)
              else
                StickerCanvas(frame: editor.currentFrame),
              if (selected != null && editor.tool != EditorTool.frames) ...[
                _selectionOverlay(selected, scale),
                // Bubbles get a draggable knob at the tail tip (#78) — except
                // caption boxes, which have no tail (#80).
                if (selected is BubbleLayer &&
                    selected.shape != BubbleShape.caption)
                  _tailHandle(selected, scale),
                // Delete the selected layer right on the canvas — previously
                // removal only existed on the Layers-panel rows, so anything
                // added while on Adjust/Text felt undeletable. Hidden for
                // Erase/Cut-out, where canvas taps mean brush dabs / object
                // picks and a stray × would be destructive.
                if (const {
                  EditorTool.layers,
                  EditorTool.adjust,
                  EditorTool.text,
                }.contains(editor.tool))
                  _deleteHandle(selected, scale),
              ],
            ],
          ),
        );
      },
    );
  }

  // ------------------------------------------------------------ tail handle
  /// The bubble's tail tip in this widget's pixel space.
  Offset _tailTipPx(BubbleLayer layer, double scale) {
    final t = layer.transform;
    final local =
        bubbleTailTip(layer, kBubbleBaseSize) -
        Offset(kBubbleBaseSize.width / 2, kBubbleBaseSize.height / 2);
    final scaled = local * t.scale;
    final cosA = math.cos(t.rotation);
    final sinA = math.sin(t.rotation);
    final rotated = Offset(
      scaled.dx * cosA - scaled.dy * sinA,
      scaled.dx * sinA + scaled.dy * cosA,
    );
    return (t.position + rotated) * scale;
  }

  Widget _tailHandle(BubbleLayer layer, double scale) {
    const touch = 15.0; // touch radius in screen px
    final px = _tailTipPx(layer, scale);
    return Positioned(
      left: px.dx - touch,
      top: px.dy - touch,
      width: touch * 2,
      height: touch * 2,
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _ImmediatePanRecognizer:
              GestureRecognizerFactoryWithHandlers<_ImmediatePanRecognizer>(
                _ImmediatePanRecognizer.new,
                (r) {
                  r.onUpdate = (d) =>
                      _dragTail(layer.id, d.globalPosition, scale);
                  r.onEnd = (_) => _controller.endEdit();
                },
              ),
        },
        child: Center(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cyan,
              border: Border.all(color: const Color(0xFF131019), width: 2),
            ),
          ),
        ),
      ),
    );
  }

  /// A tappable × on the selection frame's top-right corner (rotating with
  /// the layer) that removes the selected layer — one undo step.
  Widget _deleteHandle(Layer layer, double scale) {
    const pad = 10.0; // matches _selectionOverlay's frame padding
    final size = _sizeOf(layer);
    final t = layer.transform;
    // Top-right corner of the padded frame, rotated around the layer center.
    final cx = size.width * scale / 2 + pad;
    final cy = -(size.height * scale / 2 + pad);
    final cosA = math.cos(t.rotation);
    final sinA = math.sin(t.rotation);
    final corner =
        t.position * scale +
        Offset(cx * cosA - cy * sinA, cx * sinA + cy * cosA);
    const touch = 16.0;
    return Positioned(
      key: const ValueKey('layer-delete-handle'),
      left: corner.dx - touch,
      top: corner.dy - touch,
      width: touch * 2,
      height: touch * 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _controller.removeLayer(layer.id),
        child: Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.rose,
              border: Border.all(color: const Color(0xFF131019), width: 2),
            ),
            child: const Icon(Icons.close, size: 13, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// Maps a drag position back through the layer transform into the bubble's
  /// normalized tail space and applies it (coalesced into one undo step).
  void _dragTail(String layerId, Offset globalPos, double scale) {
    final canvasBox = context.findRenderObject() as RenderBox?;
    final layer = ref
        .read(editorControllerProvider)
        .layers
        .whereType<BubbleLayer>()
        .where((l) => l.id == layerId)
        .firstOrNull;
    if (canvasBox == null || layer == null) return;
    final t = layer.transform;
    final logical = canvasBox.globalToLocal(globalPos) / scale;
    final rel = logical - t.position;
    final cosA = math.cos(-t.rotation);
    final sinA = math.sin(-t.rotation);
    final unrotated =
        Offset(rel.dx * cosA - rel.dy * sinA, rel.dx * sinA + rel.dy * cosA) /
        t.scale;
    final local =
        unrotated +
        Offset(kBubbleBaseSize.width / 2, kBubbleBaseSize.height / 2);
    _controller.updateBubbleLayer(
      layerId,
      tail: bubbleTailFromLocal(local, kBubbleBaseSize),
    );
  }

  // ------------------------------------------------------------ gestures
  void _onTap(Offset pointLogical, EditorState editor) {
    // Erase tool: a tap lays down a single dab on the selected photo.
    if (_isErasing(editor)) {
      widget.onEraseStroke?.call([pointLogical]);
      return;
    }
    // Cut-out tool in Remove-object mode: the tap picks an object (#83).
    if (widget.onObjectTap != null &&
        editor.tool == EditorTool.cutout &&
        editor.selectedLayer is ImageLayer) {
      widget.onObjectTap!(pointLogical);
      return;
    }
    if (editor.layers.isEmpty) {
      widget.onEmptyTap();
      return;
    }
    final hit = _hitTest(editor.layers, pointLogical);
    _controller.selectLayer(hit?.id);
    // Tapping a bubble opens its editor right away — previously the bubble
    // panel appeared only if the Text tool happened to be active (#82).
    if (hit is BubbleLayer && editor.tool != EditorTool.text) {
      _controller.setTool(EditorTool.text);
    }
  }

  void _onScaleStart(Offset focalLogical, EditorState editor) {
    // Erase tool: start collecting a brush stroke on the selected photo,
    // instead of moving/scaling a layer.
    if (_isErasing(editor)) {
      _strokePoints = [focalLogical];
      return;
    }
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
    if (_strokePoints != null) {
      _strokePoints!.add(d.localFocalPoint / scale);
      return;
    }
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

  void _onScaleEnd() {
    final stroke = _strokePoints;
    if (stroke != null) {
      _strokePoints = null;
      if (stroke.isNotEmpty) widget.onEraseStroke?.call(stroke);
      return;
    }
    _gestureLayerId = null;
    _controller.endEdit();
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
  /// Image layers shrink to their BoxFit.contain content rect (once the header
  /// dims are cached) so a letterboxed photo doesn't blanket the canvas and
  /// block taps on the layer underneath (#74).
  Size _sizeOf(Layer layer) {
    final s = layer.transform.scale;
    return switch (layer) {
      ImageLayer(:final assetPath) => () {
        const box = 440.0;
        final dims = _imageDims[assetPath];
        if (dims == null || dims.width <= 0 || dims.height <= 0) {
          return Size(box * s, box * s);
        }
        final ar = dims.width / dims.height;
        return ar >= 1
            ? Size(box * s, box / ar * s)
            : Size(box * ar * s, box * s);
      }(),
      BubbleLayer() => kBubbleBaseSize * s,
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

/// Wins the gesture arena on pointer-down, so a drag that starts on the tail
/// knob can never lose to the canvas-wide scale recognizer (#78).
class _ImmediatePanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
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
