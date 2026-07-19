import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/layer.dart';

/// Base logical size of a bubble's bounding box (before the layer's own scale).
/// The body occupies the upper portion; the tail draws into the lower band by
/// default, but may point any direction (#78).
const Size kBubbleBaseSize = Size(210, 168);

/// Tail tip in box-pixel space from the normalized [BubbleLayer.tail].
/// dx is in body-half-widths from the body center; dy is in lower-band units
/// from the body's bottom (negative values reach up past the body). The tip is
/// clamped to the box, not the body, so tails can point sideways or up.
Offset bubbleTailTip(BubbleLayer layer, Size size) {
  final body = bubbleBodyRect(size);
  final cx = body.center.dx + layer.tail.dx * (body.width / 2);
  final ty = body.bottom + layer.tail.dy * (size.height - body.bottom);
  return Offset(cx.clamp(0.0, size.width), ty.clamp(0.0, size.height));
}

/// The bubble body rect within a box of [size] (upper ~68%, inset).
Rect bubbleBodyRect(Size size) => Rect.fromLTWH(
  size.width * 0.06,
  size.height * 0.05,
  size.width * 0.88,
  size.height * 0.63,
);

/// Inverse of [bubbleTailTip]: converts a box-pixel point back to the
/// normalized tail value (clamped to what the box can display).
Offset bubbleTailFromLocal(Offset local, Size size) {
  final body = bubbleBodyRect(size);
  final dx = (local.dx - body.center.dx) / (body.width / 2);
  final dy = (local.dy - body.bottom) / (size.height - body.bottom);
  // The box clamps the tip anyway — mirror those limits in normalized space.
  final dxMax = (size.width - body.center.dx) / (body.width / 2);
  final dyMin = (0 - body.bottom) / (size.height - body.bottom);
  return Offset(dx.clamp(-dxMax, dxMax), dy.clamp(dyMin, 1.0));
}

/// The largest font size ≤ [maxSize] at which [text] (width-wrapped) fits
/// inside [bounds]. Shared by the live [BubbleView] and the export renderer so
/// what the user sees is what the sticker ships — long captions used to clip
/// in preview but spill outside the bubble in export (#79).
double bubbleFitFontSize({
  required String text,
  required String fontFamily,
  required double maxSize,
  required Size bounds,
}) {
  if (text.trim().isEmpty || bounds.isEmpty) return maxSize;
  bool fits(double size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: fontFamily,
          fontSize: size,
          height: 1.05,
          fontWeight: FontWeight.w700,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: bounds.width);
    final ok = tp.height <= bounds.height && tp.width <= bounds.width;
    tp.dispose();
    return ok;
  }

  if (fits(maxSize)) return maxSize;
  var lo = 6.0;
  var hi = maxSize;
  for (var i = 0; i < 7; i++) {
    final mid = (lo + hi) / 2;
    if (fits(mid)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  // `lo` is the largest *tried* size that fits, but the 6.0 floor is returned
  // unverified: a pathologically long caption can overflow even at 6 pt. The
  // render paths ([BubbleView] and StickerRenderer._paintBubble) cap the line
  // count via [bubbleCaptionMaxLines] + ellipsis and clip to the body so that
  // floor can never paint over the outline/tail (#79 / WYSIWYG).
  return lo;
}

/// The largest number of whole lines of [fontSize] text (at the caption's 1.05
/// line-height) that fit within [height]. Used to cap and ellipsize a caption
/// that overflows even the [bubbleFitFontSize] floor, so it can never spill past
/// the bubble body. Shared by [BubbleView] and the export renderer so the editor
/// preview and the exported sticker clamp identically (#79 / WYSIWYG).
int bubbleCaptionMaxLines(double fontSize, double height) {
  if (fontSize <= 0 || height <= 0) return 1;
  final lines = (height / (fontSize * 1.05)).floor();
  return lines < 1 ? 1 : lines;
}

/// Renders a [BubbleLayer] as crisp vector paths (a shape body + tail) with a
/// centered, reflowing caption. Sized in logical units × [scale]; the layer's
/// own transform (scale/rotation) is applied by the enclosing widgets.
class BubbleView extends StatelessWidget {
  const BubbleView({super.key, required this.layer, required this.scale});

  final BubbleLayer layer;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final size = kBubbleBaseSize * scale;
    // The caption sits inside the body (upper ~68% of the box), padded.
    final bodyRect = bubbleBodyRect(size);
    final captionRect = bodyRect.deflate(10 * scale);
    final fontSize = bubbleFitFontSize(
      text: layer.text,
      fontFamily: layer.fontFamily,
      maxSize: layer.fontSize * scale,
      bounds: captionRect.size,
    );
    // A caption too long to fit even at the floor size is capped to whole lines
    // and ellipsized, then clipped to the body — so it can never paint over the
    // outline/tail. Normal captions fit within maxLines and are unaffected.
    final maxLines = bubbleCaptionMaxLines(fontSize, captionRect.height);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: BubblePainter(layer))),
          Positioned.fromRect(
            rect: captionRect,
            child: ClipRect(
              child: Center(
                child: Text(
                  layer.text,
                  textAlign: TextAlign.center,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: layer.fontFamily,
                    fontSize: fontSize,
                    height: 1.05,
                    color: layer.textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints the bubble body + tail as vector paths. Exposed (not private) so a
/// golden test can drive it directly.
class BubblePainter extends CustomPainter {
  BubblePainter(this.layer);

  final BubbleLayer layer;

  @override
  void paint(Canvas canvas, Size size) {
    final body = bubbleBodyRect(size);
    final path = switch (layer.shape) {
      BubbleShape.speech => _speech(body, size),
      BubbleShape.thought => _thought(body, size),
      BubbleShape.shout => _shout(body, size),
      BubbleShape.caption => _captionBox(body),
      // Same silhouette as speech; the outline goes dashed below (#80).
      BubbleShape.whisper => _speech(body, size),
    };

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = layer.fillColor;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.018
      ..strokeJoin = StrokeJoin.round
      ..color = layer.strokeColor;

    // Soft drop shadow for the sticker feel — elevation scales with the box
    // so preview and 512-px export keep the same proportion (#79).
    canvas.drawShadow(
      path,
      const Color(0x55000000),
      size.shortestSide * 0.024,
      false,
    );
    canvas.drawPath(path, fill);
    if (layer.shape == BubbleShape.whisper) {
      canvas.drawPath(
        _dashedOutline(
          path,
          size.shortestSide * 0.055,
          size.shortestSide * 0.035,
        ),
        stroke..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawPath(path, stroke);
    }

    if (layer.shape == BubbleShape.thought) {
      _thoughtDots(canvas, body, size, fill, stroke);
    }
  }

  /// Rebuilds [source]'s outline as dash segments (whisper).
  static Path _dashedOutline(Path source, double dash, double gap) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
        distance = end + gap;
      }
    }
    return dashed;
  }

  /// Tail-less rounded narration box (#80).
  static Path _captionBox(Rect body) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(body, Radius.circular(body.height * 0.14)),
    );

  Offset _tailTip(Size size) => bubbleTailTip(layer, size);

  /// The point where the center→[tip] ray leaves the body ellipse, used to
  /// anchor tails/dots for any direction.
  static Offset _ellipseEdge(Rect body, Offset tip) {
    final d = tip - body.center;
    if (d.distance < 1) return body.bottomCenter;
    final rx = body.width / 2;
    final ry = body.height / 2;
    final k =
        1 / math.sqrt((d.dx * d.dx) / (rx * rx) + (d.dy * d.dy) / (ry * ry));
    return body.center + d * k;
  }

  /// A triangular tail from just inside the body edge to [tip], unioned with
  /// the body path so any direction yields one clean outline (#78).
  static Path _tailTriangle(Rect body, Offset tip, {double halfWidth = 0}) {
    final edge = _ellipseEdge(body, tip);
    final d = tip - edge;
    if (d.distance < 4) return Path();
    final unit = d / d.distance;
    final perp = Offset(-unit.dy, unit.dx);
    final half = halfWidth > 0 ? halfWidth : body.width * 0.12;
    // Pull the base inward so the union fully swallows it.
    final base = edge - unit * math.min(14, d.distance / 2);
    return Path()
      ..moveTo(base.dx + perp.dx * half, base.dy + perp.dy * half)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(base.dx - perp.dx * half, base.dy - perp.dy * half)
      ..close();
  }

  Path _speech(Rect body, Size size) {
    final r = Radius.circular(body.height * 0.42);
    final bodyPath = Path()..addRRect(RRect.fromRectAndRadius(body, r));
    final tail = _tailTriangle(body, _tailTip(size));
    return tail.getBounds().isEmpty
        ? bodyPath
        : Path.combine(PathOperation.union, bodyPath, tail);
  }

  /// Cloud-scalloped thought body — quadratic bumps around the body ellipse
  /// (replaces the old plain oval, which was the weakest-looking shape) (#80).
  Path _thought(Rect body, Size size) {
    const bumps = 9;
    final rx = body.width / 2;
    final ry = body.height / 2;
    final center = body.center;
    Offset onEllipse(double a) =>
        Offset(center.dx + math.cos(a) * rx, center.dy + math.sin(a) * ry);
    final path = Path();
    const step = 2 * math.pi / bumps;
    var prev = onEllipse(0);
    path.moveTo(prev.dx, prev.dy);
    for (var i = 1; i <= bumps; i++) {
      final next = onEllipse(step * i);
      final mid = Offset.lerp(prev, next, 0.5)!;
      final ctrl = center + (mid - center) * 1.38;
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, next.dx, next.dy);
      prev = next;
    }
    return path..close();
  }

  void _thoughtDots(
    Canvas canvas,
    Rect body,
    Size size,
    Paint fill,
    Paint stroke,
  ) {
    final tip = _tailTip(size);
    // The chain starts where the tail leaves the body — following the tail's
    // direction instead of always hanging from bottom-center (#78).
    final start = _ellipseEdge(body, tip);
    for (var i = 0; i < 3; i++) {
      final t = (i + 1) / 4;
      final c = Offset.lerp(start, tip, t)!;
      final rad = body.height * 0.09 * (1 - t * 0.5);
      canvas.drawCircle(c, rad, fill);
      canvas.drawCircle(c, rad, stroke);
    }
  }

  Path _shout(Rect body, Size size) {
    // Spiky "burst" star around the body ellipse.
    final center = body.center;
    final rx = body.width / 2;
    final ry = body.height / 2;
    const points = 14;
    final star = Path();
    for (var i = 0; i < points * 2; i++) {
      final a = math.pi * i / points - math.pi / 2;
      final spike = i.isEven ? 1.0 : 0.72;
      final p = Offset(
        center.dx + math.cos(a) * rx * spike,
        center.dy + math.sin(a) * ry * spike,
      );
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();

    // A jagged lightning-style tail — shout no longer ignores the tail (#78).
    final tip = _tailTip(size);
    final edge = _ellipseEdge(body, tip);
    final d = tip - edge;
    if (d.distance < 10) return star;
    final unit = d / d.distance;
    final perp = Offset(-unit.dy, unit.dx);
    final half = body.width * 0.10;
    final base = edge - unit * math.min(14, d.distance / 2);
    final kinkOut = Offset.lerp(base, tip, 0.55)! + perp * (half * 0.55);
    final kinkBack = Offset.lerp(base, tip, 0.45)! - perp * (half * 0.55);
    final tail = Path()
      ..moveTo(base.dx + perp.dx * half, base.dy + perp.dy * half)
      ..lineTo(kinkOut.dx, kinkOut.dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(kinkBack.dx, kinkBack.dy)
      ..lineTo(base.dx - perp.dx * half, base.dy - perp.dy * half)
      ..close();
    return Path.combine(PathOperation.union, star, tail);
  }

  @override
  bool shouldRepaint(BubblePainter old) => old.layer != layer;
}
