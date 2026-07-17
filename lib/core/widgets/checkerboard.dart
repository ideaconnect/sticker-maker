import 'package:flutter/material.dart';

/// The transparency checkerboard used behind sticker canvases and thumbnails,
/// matching the design's `background-image` checker pattern.
class Checkerboard extends StatelessWidget {
  const Checkerboard({
    super.key,
    this.cell = 13,
    this.base = const Color(0xFF221D2E),
    this.tile = const Color(0xFF2B2638),
  });

  /// Side length of one checker square, in logical pixels.
  final double cell;
  final Color base;
  final Color tile;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _CheckerPainter(cell: cell, base: base, tile: tile),
      size: Size.infinite,
    );
  }
}

class _CheckerPainter extends CustomPainter {
  _CheckerPainter({required this.cell, required this.base, required this.tile});

  final double cell;
  final Color base;
  final Color tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()..color = tile;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if ((r + c).isEven) continue;
        canvas.drawRect(Rect.fromLTWH(c * cell, r * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) =>
      old.cell != cell || old.base != base || old.tile != tile;
}
