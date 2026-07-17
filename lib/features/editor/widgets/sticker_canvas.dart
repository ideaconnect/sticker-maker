import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/models/frame.dart';
import '../../../core/models/layer.dart';
import '../../../core/models/sticker_project.dart';
import '../../../core/rendering/color_matrix.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/sticker_caption.dart';

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
        return SizedBox.square(
          dimension: side,
          child: Stack(
            children: [
              for (final layer in frame.layers)
                if (layer.visible) _positioned(layer, side, scale),
            ],
          ),
        );
      },
    );
  }

  Widget _positioned(Layer layer, double side, double scale) {
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
              child: _content(layer, scale),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(Layer layer, double scale) {
    return switch (layer) {
      TextLayer() => StickerCaption(
        text: layer.text,
        fontFamily: layer.fontFamily,
        fontSize: layer.fontSize * scale,
        color: layer.color,
        rotation: 0, // rotation handled by the enclosing Transform
      ),
      ImageLayer() => _imageContent(layer, scale),
    };
  }

  Widget _imageContent(ImageLayer layer, double scale) {
    final file = File(layer.assetPath);
    // Show the placeholder synchronously for a missing asset (e.g. the demo /
    // gallery fixtures, or a deleted file) instead of flashing an error frame.
    if (!file.existsSync()) {
      return _ImagePlaceholder(name: layer.name, side: 180 * scale);
    }
    final base = 440.0 * scale; // ~0.86 of the canvas; user scale applied above
    Widget image = Image.file(
      file,
      width: base,
      height: base,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          _ImagePlaceholder(name: layer.name, side: 180 * scale),
    );
    if (!layer.adjustments.isIdentity) {
      image = ColorFiltered(
        colorFilter: ColorFilter.matrix(layer.adjustments.toColorMatrix()),
        child: image,
      );
    }
    return image;
  }
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
