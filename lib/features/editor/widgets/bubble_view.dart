import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/layer.dart';

/// Base logical size of a bubble's bounding box (before the layer's own scale).
/// The body occupies the upper portion; the tail draws into the lower band.
const Size kBubbleBaseSize = Size(210, 168);

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
    final bodyRect = Rect.fromLTWH(
      size.width * 0.06,
      size.height * 0.05,
      size.width * 0.88,
      size.height * 0.63,
    );
    return SizedBox(
      width: size.width,
      height: size.height,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: BubblePainter(layer))),
          Positioned.fromRect(
            rect: bodyRect.deflate(10 * scale),
            child: Center(
              child: Text(
                layer.text,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: layer.fontFamily,
                  fontSize: layer.fontSize * scale,
                  height: 1.05,
                  color: layer.textColor,
                  fontWeight: FontWeight.w700,
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
    final body = Rect.fromLTWH(
      size.width * 0.06,
      size.height * 0.05,
      size.width * 0.88,
      size.height * 0.63,
    );
    final path = switch (layer.shape) {
      BubbleShape.speech => _speech(body, size),
      BubbleShape.thought => _thought(body, size),
      BubbleShape.shout => _shout(body),
    };

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = layer.fillColor;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.018
      ..strokeJoin = StrokeJoin.round
      ..color = layer.strokeColor;

    // Soft drop shadow for the sticker feel.
    canvas.drawShadow(path, const Color(0x55000000), 4, false);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);

    if (layer.shape == BubbleShape.thought) {
      _thoughtDots(canvas, body, size, fill, stroke);
    }
  }

  /// Tail tip in pixel space from the normalized [BubbleLayer.tail].
  Offset _tailTip(Rect body, Size size) {
    final halfW = body.width / 2;
    final cx = body.center.dx + layer.tail.dx * halfW;
    final ty = body.bottom + layer.tail.dy * (size.height - body.bottom);
    return Offset(
      cx.clamp(body.left, body.right),
      ty.clamp(body.bottom, size.height),
    );
  }

  Path _speech(Rect body, Size size) {
    final r = Radius.circular(body.height * 0.42);
    final path = Path()..addRRect(RRect.fromRectAndRadius(body, r));
    // Triangular tail from the bottom edge to the tip.
    final tip = _tailTip(body, size);
    final baseHalf = body.width * 0.12;
    path.moveTo(tip.dx - baseHalf, body.bottom - 2);
    path.lineTo(tip.dx, tip.dy);
    path.lineTo(tip.dx + baseHalf, body.bottom - 2);
    path.close();
    return path;
  }

  Path _thought(Rect body, Size size) {
    return Path()..addOval(body);
  }

  void _thoughtDots(
    Canvas canvas,
    Rect body,
    Size size,
    Paint fill,
    Paint stroke,
  ) {
    final tip = _tailTip(body, size);
    for (var i = 0; i < 3; i++) {
      final t = (i + 1) / 4;
      final c = Offset.lerp(body.bottomCenter, tip, t)!;
      final rad = body.height * 0.09 * (1 - t * 0.5);
      canvas.drawCircle(c, rad, fill);
      canvas.drawCircle(c, rad, stroke);
    }
  }

  Path _shout(Rect body) {
    // Spiky "burst" star around the body ellipse.
    final center = body.center;
    final rx = body.width / 2;
    final ry = body.height / 2;
    const points = 14;
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final a = math.pi * i / points - math.pi / 2;
      final spike = i.isEven ? 1.0 : 0.72;
      final p = Offset(
        center.dx + math.cos(a) * rx * spike,
        center.dy + math.sin(a) * ry * spike,
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(BubblePainter old) => old.layer != layer;
}
