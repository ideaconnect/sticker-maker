import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/models/frame.dart';
import '../../../core/models/layer.dart';
import '../../../core/models/sticker_project.dart';
import '../../../core/rendering/color_matrix.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sticker_caption.dart';
import 'bubble_view.dart';

/// Renders a [Frame]'s layers in z-order (bottom → top), mapping the model's
/// 512-unit logical coordinates onto whatever square size the widget is given.
/// Image layers render as placeholders until image import (#21) provides pixels;
/// text layers render for real with the sticker outline.
///
/// This is the shared rendering surface for the editor canvas and (later) the
/// export renderer.
class StickerCanvas extends StatelessWidget {
  const StickerCanvas({super.key, required this.frame});

  final Frame frame;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        final scale = side / StickerProject.canvasSize;
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        return SizedBox.square(
          dimension: side,
          child: Stack(
            children: [
              for (final layer in frame.layers)
                if (layer.visible) _positioned(layer, side, scale, dpr),
            ],
          ),
        );
      },
    );
  }

  Widget _positioned(Layer layer, double side, double scale, double dpr) {
    final t = layer.transform;
    return Positioned(
      left: t.position.dx * scale,
      top: t.position.dy * scale,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Opacity(
          opacity: layer.opacity.clamp(0.0, 1.0),
          child: Transform.rotate(
            angle: t.rotation,
            child: Transform.scale(
              scale: t.scale,
              child: _content(layer, scale, dpr),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(Layer layer, double scale, double dpr) {
    return switch (layer) {
      TextLayer() => StickerCaption(
        text: layer.text,
        fontFamily: layer.fontFamily,
        fontSize: layer.fontSize * scale,
        color: layer.color,
        rotation: 0, // rotation handled by the enclosing Transform
        decorative: layer.decorative,
      ),
      BubbleLayer() => BubbleView(layer: layer, scale: scale),
      ImageLayer() => _imageContent(layer, scale, dpr),
    };
  }

  Widget _imageContent(ImageLayer layer, double scale, double dpr) {
    final file = File(layer.assetPath);
    // Show the placeholder synchronously for a missing asset (e.g. the demo /
    // gallery fixtures, or a deleted file) instead of flashing an error frame.
    if (!file.existsSync()) {
      return _ImagePlaceholder(name: layer.name, side: 180 * scale);
    }
    final base = 440.0 * scale; // ~0.86 of the canvas; user scale applied above
    // Decode only the pixels this box (and the layer's own zoom) can show —
    // full-res decodes of 2048² sources per widget instance were the top OOM
    // risk with several photos × frame thumbnails (#75).
    final target = stickerDecodeTarget(
      side: base,
      dpr: dpr,
      layerScale: layer.transform.scale,
    );
    final colorFilter = layer.adjustments.isIdentity
        ? null
        : ColorFilter.matrix(layer.adjustments.toColorMatrix());

    // A cut-out layer composites its alpha mask over the photo (background
    // removed). The mask file may be absent (e.g. a project opened without its
    // assets) — fall back to the plain photo in that case.
    final maskPath = layer.maskPath;
    if (maskPath != null && File(maskPath).existsSync()) {
      return _MaskedImage(
        imagePath: layer.assetPath,
        maskPath: maskPath,
        side: base,
        decodeTarget: target,
        colorFilter: colorFilter,
        outlineWidthPx: layer.outlineWidth * scale,
        outlineColor: layer.outlineColor,
      );
    }

    Widget image = Image.file(
      file,
      width: base,
      height: base,
      fit: BoxFit.contain,
      // Shared via Flutter's ImageCache; sized decode instead of full-res.
      cacheWidth: target,
      errorBuilder: (_, _, _) =>
          _ImagePlaceholder(name: layer.name, side: 180 * scale),
    );
    if (colorFilter != null) {
      image = ColorFiltered(colorFilter: colorFilter, child: image);
    }
    return image;
  }
}

/// The decode width (physical px) for a photo shown in a [side]-logical-px
/// contain box at [dpr], keeping the layer's own pinch zoom sharp via
/// [layerScale]. Quantized up to 256-px steps so a pinch doesn't re-decode on
/// every frame, and clamped to sane bounds; the decoder additionally never
/// upscales past the source width (#75).
int stickerDecodeTarget({
  required double side,
  required double dpr,
  double layerScale = 1.0,
}) {
  final raw = side * dpr * layerScale.clamp(1.0, 6.0);
  final quantized = ((raw + 255) ~/ 256) * 256;
  return quantized < 256 ? 256 : (quantized > 4096 ? 4096 : quantized);
}

/// Renders a photo with its alpha mask applied — the visible result of an AI
/// cut-out. Both files are decoded to [ui.Image] and composited with
/// `BlendMode.dstIn` so the photo survives only where the mask is opaque.
/// Non-destructive: the source photo and the mask stay separate on disk.
/// Decodes at [decodeTarget] physical px (never past the source resolution),
/// so a frame thumbnail holds kilobytes instead of a full 2048² bitmap (#75).
class _MaskedImage extends StatefulWidget {
  const _MaskedImage({
    required this.imagePath,
    required this.maskPath,
    required this.side,
    required this.decodeTarget,
    this.colorFilter,
    this.outlineWidthPx = 0,
    this.outlineColor = const Color(0xFFFFFFFF),
  });

  final String imagePath;
  final String maskPath;
  final double side;

  /// Decode width in physical px (see [stickerDecodeTarget]).
  final int decodeTarget;

  final ColorFilter? colorFilter;
  final double outlineWidthPx;
  final Color outlineColor;

  @override
  State<_MaskedImage> createState() => _MaskedImageState();
}

class _MaskedImageState extends State<_MaskedImage> {
  ui.Image? _base;
  ui.Image? _mask;

  /// The target the current `_base`/`_mask` were decoded at.
  int _decodedTarget = 0;

  /// Bumped on each (re)load so an out-of-order decode from a superseded load
  /// discards its result instead of clobbering the newer one.
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_MaskedImage old) {
    super.didUpdateWidget(old);
    if (old.imagePath != widget.imagePath || old.maskPath != widget.maskPath) {
      _load();
    } else if (widget.decodeTarget > _decodedTarget) {
      // More pixels needed (pinch zoom / bigger box) — smaller targets keep
      // the existing decode; downscaling again would only cost CPU.
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_loadGen;
    final target = widget.decodeTarget;
    final base = await _decode(widget.imagePath, target);
    final mask = await _decode(widget.maskPath, target);
    // Superseded by a newer load (or unmounted): drop this stale result.
    if (!mounted || gen != _loadGen) {
      base?.dispose();
      mask?.dispose();
      return;
    }
    setState(() {
      _base?.dispose();
      _mask?.dispose();
      _base = base;
      _mask = mask;
      _decodedTarget = target;
    });
  }

  /// Decodes [path] at most [targetWidth] px wide — never upscaled past the
  /// encoded source size.
  static Future<ui.Image?> _decode(String path, int targetWidth) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      buffer.dispose();
      try {
        final codec = descriptor.width > targetWidth
            ? await descriptor.instantiateCodec(targetWidth: targetWidth)
            : await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          return frame.image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _base?.dispose();
    _mask?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    if (base == null) {
      return SizedBox.square(dimension: widget.side);
    }
    return CustomPaint(
      size: Size.square(widget.side),
      painter: _MaskedImagePainter(
        base: base,
        mask: _mask,
        colorFilter: widget.colorFilter,
        outlineWidthPx: widget.outlineWidthPx,
        outlineColor: widget.outlineColor,
      ),
    );
  }
}

/// Paints [base] fitted (contain) into the box, then multiplies its alpha by
/// [mask] via `BlendMode.dstIn`. [mask] shares the photo's aspect ratio, so it
/// maps onto the same destination rect.
class _MaskedImagePainter extends CustomPainter {
  _MaskedImagePainter({
    required this.base,
    this.mask,
    this.colorFilter,
    this.outlineWidthPx = 0,
    this.outlineColor = const Color(0xFFFFFFFF),
  });

  final ui.Image base;
  final ui.Image? mask;
  final ColorFilter? colorFilter;
  final double outlineWidthPx;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(base.width.toDouble(), base.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imageSize, size);
    final dest = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    final basePaint = Paint()..filterQuality = FilterQuality.medium;
    if (colorFilter != null) basePaint.colorFilter = colorFilter;

    final maskImage = mask;
    if (maskImage == null) {
      canvas.drawImageRect(base, Offset.zero & imageSize, dest, basePaint);
      return;
    }

    final maskSize = Size(
      maskImage.width.toDouble(),
      maskImage.height.toDouble(),
    );
    // Die-cut contour behind the subject.
    if (outlineWidthPx > 0) {
      _paintDieCut(canvas, imageSize, maskSize, dest);
    }
    canvas.saveLayer(dest, Paint());
    canvas.drawImageRect(base, Offset.zero & imageSize, dest, basePaint);
    canvas.drawImageRect(
      maskImage,
      Offset.zero & maskSize,
      dest,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  /// Solid [outlineColor] silhouette of the subject, grown by [outlineWidthPx]
  /// via a morphological dilate, painted before the subject. Mirrors
  /// StickerRenderer._paintDieCut so preview and export match.
  void _paintDieCut(Canvas canvas, Size imageSize, Size maskSize, Rect dest) {
    final inflated = dest.inflate(outlineWidthPx + 2);
    canvas.saveLayer(
      inflated,
      Paint()
        ..imageFilter = ui.ImageFilter.dilate(
          radiusX: outlineWidthPx,
          radiusY: outlineWidthPx,
        ),
    );
    canvas.saveLayer(dest, Paint());
    canvas.drawImageRect(
      base,
      Offset.zero & imageSize,
      dest,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.drawImageRect(
      mask!,
      Offset.zero & maskSize,
      dest,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.medium,
    );
    canvas.drawRect(
      dest,
      Paint()
        ..color = outlineColor
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MaskedImagePainter old) =>
      old.base != base ||
      old.mask != mask ||
      old.colorFilter != colorFilter ||
      old.outlineWidthPx != outlineWidthPx ||
      old.outlineColor != outlineColor;
}

/// Stand-in for an image layer until real pixels arrive in #21.
class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder({required this.name, required this.side});

  final String name;
  final double side;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.cardAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.image_outlined,
            color: AppColors.textMuted,
            size: 28,
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
