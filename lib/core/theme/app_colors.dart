import 'package:flutter/material.dart';

/// Raw color tokens taken directly from the approved design
/// (`design/Sticker Maker.dc.html`). This is a dark-only app with no theme
/// switching, so widgets may reference these semantic constants directly.
/// Gradients, radii, per-tool accents and any value that could vary with a
/// future theme are exposed through [SmTokens]; read those from the [Theme].
abstract final class AppColors {
  AppColors._();

  // Surfaces (dark theme only).
  static const Color pageBackground = Color(0xFF0C0A11);
  static const Color background = Color(0xFF131019);
  static const Color panel = Color(0xFF1A1624);
  static const Color card = Color(0xFF1C1826);
  static const Color cardAlt = Color(0xFF221D2E);
  static const Color inputField = Color(0xFF242030);
  static const Color chipSurface = Color(0xFF2A2436);
  static const Color elevated = Color(0xFF3A3350);

  // Text.
  static const Color textPrimary = Color(0xFFEFEAF4);
  static const Color textSecondary = Color(0xFFCFC9DB);
  static const Color textMuted = Color(0xFF8B8399);
  static const Color textFaint = Color(0xFF5F596E);

  // Accents — each editor tool owns one.
  static const Color violet = Color(0xFFA78BFA); // Layers
  static const Color cyan = Color(0xFF38BDF8); // Adjust / selection
  static const Color pink = Color(0xFFF472B6); // Text
  static const Color amber = Color(0xFFFBBF24); // Erase
  static const Color green = Color(0xFF34D399); // Cut out
  static const Color orange = Color(0xFFFB923C); // Frames

  // Accent support tints.
  static const Color violetBright = Color(0xFF7C5CFF);
  static const Color violetLight = Color(0xFFC4B5FD);
  static const Color magenta = Color(0xFFB06BFF);
  static const Color greenLight = Color(0xFF6EE7B7);
  static const Color teal = Color(0xFF22D3EE);
  static const Color rose = Color(0xFFFB7185);
  static const Color cutoutInk = Color(0xFF06231B);
  static const Color neutralButton = Color(
    0xFF2F2840,
  ); // muted "Undo removal" CTA

  // Hairline borders.
  static const Color border = Color(0x14FFFFFF); // ~8% white
  static const Color borderFaint = Color(0x0FFFFFFF); // ~6% white

  // Gradient stops.
  static const List<Color> heroGradient = [violetBright, magenta, pink];
  static const List<Color> cutoutGradient = [green, teal];
  static const List<Color> logoGradient = [violet, pink];
}
