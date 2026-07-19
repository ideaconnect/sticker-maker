import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/models/frame.dart';
import '../../core/models/layer.dart';
import '../../core/rendering/color_matrix.dart';
import '../../core/theme/app_colors.dart';
import '../editor/widgets/bubble_view.dart';

/// Flattens a sticker [Frame] to a transparent raster image at an arbitrary
/// target size, matching the on-canvas rendering (StickerCanvas). This is the
/// single source of truth for export pixels — the PNG/WebP/GIF encoders all
/// build on it. Painting happens against a [Canvas] (origin = layer centre) so
/// it renders headlessly without a widget pipeline.
abstract final class StickerRenderer {
  StickerRenderer._();

  /// The model's logical canvas edge (see [StickerProject.canvasSize]).
  static const double _logical = 512;

  /// Renders [frame] to a [size]×[size] RGBA image (transparent background).
  static Future<ui.Image> renderImage(Frame frame, {int size = 512}) async {
    final decoded = await _decodeImages(frame);
    try {
      final recorder = ui.PictureRecorder();
      final bounds = Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble());
      final canvas = Canvas(recorder, bounds);
      final scale = size / _logical;

      for (final layer in frame.layers) {
        if (!layer.visible) continue;
        final t = layer.transform;
        canvas.save();
        canvas.translate(t.position.dx * scale, t.position.dy * scale);
        canvas.rotate(t.rotation);
        canvas.scale(t.scale);
        final opacity = layer.opacity.clamp(0.0, 1.0);
        final fade = opacity < 1.0;
        if (fade) {
          canvas.saveLayer(
            null,
            Paint()..color = Color.fromRGBO(0, 0, 0, opacity),
          );
        }
        switch (layer) {
          case ImageLayer():
            _paintImage(canvas, layer, scale, decoded);
          case TextLayer():
            _paintText(canvas, layer, scale);
          case BubbleLayer():
            _paintBubble(canvas, layer, scale);
        }
        if (fade) canvas.restore();
        canvas.restore();
      }

      final picture = recorder.endRecording();
      final image = await picture.toImage(size, size);
      picture.dispose();
      return image;
    } finally {
      for (final image in decoded.values) {
        image.dispose();
      }
    }
  }

  /// Renders [frame] to PNG bytes (transparent).
  static Future<Uint8List> renderPng(Frame frame, {int size = 512}) async {
    final image = await renderImage(frame, size: size);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('failed to encode sticker PNG');
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  // ------------------------------------------------- layer painters
  // The canvas has been translated to the layer's centre, so each painter draws
  // around the origin.

  static void _paintImage(
    Canvas canvas,
    ImageLayer layer,
    double scale,
    Map<String, ui.Image> decoded,
  ) {
    final base = decoded[layer.assetPath];
    if (base == null) return; // missing source file → nothing to export
    final boxSide = 440.0 * scale;
    final box = Rect.fromCenter(
      center: Offset.zero,
      width: boxSide,
      height: boxSide,
    );
    final imgSize = Size(base.width.toDouble(), base.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, imgSize, box.size);
    final dest = Alignment.center.inscribe(fitted.destination, box);
    final basePaint = Paint()..filterQuality = FilterQuality.high;
    if (!layer.adjustments.isIdentity) {
      basePaint.colorFilter = ColorFilter.matrix(
        layer.adjustments.toColorMatrix(),
      );
    }
    final mask = layer.maskPath == null ? null : decoded[layer.maskPath];
    if (mask == null) {
      canvas.drawImageRect(base, Offset.zero & imgSize, dest, basePaint);
      return;
    }
    final maskSize = Size(mask.width.toDouble(), mask.height.toDouble());
    // Die-cut contour (behind the subject), so a white ring shows at the edges.
    if (layer.hasOutline) {
      _paintDieCut(
        canvas,
        base,
        mask,
        imgSize,
        maskSize,
        dest,
        layer.outlineColor,
        layer.outlineWidth * scale,
      );
    }
    canvas.saveLayer(dest, Paint());
    canvas.drawImageRect(base, Offset.zero & imgSize, dest, basePaint);
    canvas.drawImageRect(
      mask,
      Offset.zero & maskSize,
      dest,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  /// Paints a solid [color] die-cut silhouette of the cut-out subject, grown by
  /// [radiusPx] via a morphological dilate — drawn *before* the subject so only
  /// the surrounding ring remains visible. Shared technique with the on-canvas
  /// painter (`_MaskedImagePainter`).
  static void _paintDieCut(
    Canvas canvas,
    ui.Image base,
    ui.Image mask,
    Size imgSize,
    Size maskSize,
    Rect dest,
    Color color,
    double radiusPx,
  ) {
    if (radiusPx <= 0) return;
    final inflated = dest.inflate(radiusPx + 2);
    canvas.saveLayer(
      inflated,
      Paint()
        ..imageFilter = ui.ImageFilter.dilate(
          radiusX: radiusPx,
          radiusY: radiusPx,
        ),
    );
    // Subject alpha silhouette (base ∩ mask), then flattened to a solid color.
    canvas.saveLayer(dest, Paint());
    canvas.drawImageRect(
      base,
      Offset.zero & imgSize,
      dest,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.drawImageRect(
      mask,
      Offset.zero & maskSize,
      dest,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.high,
    );
    canvas.drawRect(
      dest,
      Paint()
        ..color = color
        ..blendMode = BlendMode.srcIn,
    );
    canvas.restore();
    canvas.restore();
  }

  static void _paintText(Canvas canvas, TextLayer layer, double scale) {
    final strokeColor =
        (layer.color == Colors.white || layer.color == AppColors.amber)
        ? const Color(0xFF14101A)
        : Colors.white;
    final style = TextStyle(
      fontFamily: layer.fontFamily,
      fontSize: layer.fontSize * scale,
      height: 1,
      // Tracking scales with the font so the outline/shadow/spacing stay in the
      // same proportion at every output size (512-px reference down the budget
      // ladder) and match the on-canvas StickerCaption preview (WYSIWYG).
      letterSpacing: 1 * scale,
      fontWeight: FontWeight.w700,
    );
    // Emoji / props (#61) render as a plain glyph — no caption stroke/shadow.
    if (layer.decorative) {
      final glyph = TextPainter(
        text: TextSpan(
          text: layer.text,
          style: style.copyWith(color: layer.color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      glyph.paint(canvas, Offset(-glyph.width / 2, -glyph.height / 2));
      return;
    }
    // Outline (drawn behind) carries the drop shadow.
    final stroke = TextPainter(
      text: TextSpan(
        text: layer.text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5 * scale
            ..strokeJoin = StrokeJoin.round
            ..color = strokeColor,
          shadows: [
            Shadow(
              color: const Color(0x40000000),
              offset: Offset(0, 4 * scale),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    stroke.paint(canvas, Offset(-stroke.width / 2, -stroke.height / 2));
    final fill = TextPainter(
      text: TextSpan(
        text: layer.text,
        style: style.copyWith(color: layer.color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    fill.paint(canvas, Offset(-fill.width / 2, -fill.height / 2));
  }

  static void _paintBubble(Canvas canvas, BubbleLayer layer, double scale) {
    final size = kBubbleBaseSize * scale;
    canvas.save();
    canvas.translate(-size.width / 2, -size.height / 2);
    BubblePainter(layer).paint(canvas, size);
    // Caption centred in the body rect — the SAME auto-fit as BubbleView, so
    // a long caption that wraps in the editor wraps identically in the
    // exported sticker instead of spilling outside the bubble (#79).
    final captionRect = bubbleBodyRect(size).deflate(10 * scale);
    final fontSize = bubbleFitFontSize(
      text: layer.text,
      fontFamily: layer.fontFamily,
      maxSize: layer.fontSize * scale,
      bounds: captionRect.size,
    );
    // Match BubbleView exactly: cap the line count + ellipsize a caption too
    // long to fit even at the floor size, and clip to the body rect, so it can
    // never spill over the outline/tail in the exported sticker (#79 / WYSIWYG).
    final tp = TextPainter(
      text: TextSpan(
        text: layer.text,
        style: TextStyle(
          fontFamily: layer.fontFamily,
          fontSize: fontSize,
          height: 1.05,
          color: layer.textColor,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: bubbleCaptionMaxLines(fontSize, captionRect.height),
      ellipsis: '…',
    )..layout(maxWidth: captionRect.width);
    canvas.save();
    canvas.clipRect(captionRect);
    tp.paint(
      canvas,
      Offset(
        captionRect.center.dx - tp.width / 2,
        captionRect.center.dy - tp.height / 2,
      ),
    );
    canvas.restore();
    canvas.restore();
  }

  static Future<Map<String, ui.Image>> _decodeImages(Frame frame) async {
    final paths = <String>{};
    for (final layer in frame.layers) {
      if (layer is ImageLayer) {
        paths.add(layer.assetPath);
        if (layer.maskPath != null) paths.add(layer.maskPath!);
      }
    }
    final map = <String, ui.Image>{};
    for (final path in paths) {
      final image = await _decode(path);
      if (image != null) map[path] = image;
    }
    return map;
  }

  static Future<ui.Image?> _decode(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }
}
