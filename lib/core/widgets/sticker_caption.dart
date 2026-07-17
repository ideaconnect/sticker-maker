import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The on-canvas sticker caption: fill text with a chunky contrasting outline
/// and a drop shadow — the defining "sticker" look from the design
/// (`WebkitTextStroke` + `paint-order: stroke fill`). Rendered as two stacked
/// [Text] layers with identical layout so the glyphs register exactly.
class StickerCaption extends StatelessWidget {
  const StickerCaption({
    super.key,
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    this.color = Colors.white,
    this.rotation = -0.087, // ~ -5deg
    this.strokeWidth = 3.5,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final Color color;
  final double rotation;
  final double strokeWidth;

  /// Light fills (white / amber) get a dark outline; everything else white.
  Color get _strokeColor => (color == Colors.white || color == AppColors.amber)
      ? const Color(0xFF14101A)
      : Colors.white;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1,
      letterSpacing: 1,
      fontWeight: FontWeight.w700,
    );

    return Transform.rotate(
      angle: rotation,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outline layer (carries the drop shadow, drawn behind the fill).
          Text(
            text,
            style: baseStyle.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = strokeWidth
                ..strokeJoin = StrokeJoin.round
                ..color = _strokeColor,
              shadows: const [
                Shadow(color: Color(0x40000000), offset: Offset(0, 4)),
              ],
            ),
          ),
          // Fill layer.
          Text(text, style: baseStyle.copyWith(color: color)),
        ],
      ),
    );
  }
}
