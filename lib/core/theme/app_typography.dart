import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Font families bundled in `assets/fonts` and declared in `pubspec.yaml`.
abstract final class AppFonts {
  AppFonts._();

  /// Primary UI typeface.
  static const String ui = 'PlusJakartaSans';

  /// Display / heading typeface (rounded, friendly).
  static const String display = 'Fredoka';

  // Sticker caption typefaces (used inside the canvas, offered in the Text tool).
  static const String bangers = 'Bangers';
  static const String luckiestGuy = 'LuckiestGuy';
  static const String pacifico = 'Pacifico';
  static const String rubik = 'Rubik';

  /// The sticker fonts offered in the Text tool, in display order.
  static const List<String> stickerFonts = [
    bangers,
    luckiestGuy,
    pacifico,
    display,
    rubik,
  ];
}

/// Builds the app-wide [TextTheme] on the primary UI font.
TextTheme buildTextTheme() {
  const base = TextStyle(fontFamily: AppFonts.ui, color: AppColors.textPrimary);
  return TextTheme(
    displayLarge: base.copyWith(
      fontFamily: AppFonts.display,
      fontWeight: FontWeight.w700,
    ),
    displayMedium: base.copyWith(
      fontFamily: AppFonts.display,
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: base.copyWith(
      fontFamily: AppFonts.display,
      fontSize: 20,
      fontWeight: FontWeight.w700,
    ),
    titleLarge: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    titleMedium: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
    bodyLarge: base.copyWith(fontSize: 14, fontWeight: FontWeight.w500),
    bodyMedium: base.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
    bodySmall: base.copyWith(fontSize: 12, color: AppColors.textMuted),
    labelLarge: base.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
    labelMedium: base.copyWith(fontSize: 11.5, fontWeight: FontWeight.w600),
    labelSmall: base.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w600,
      color: AppColors.textMuted,
    ),
  );
}
