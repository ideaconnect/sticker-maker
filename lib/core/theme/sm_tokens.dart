import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Design tokens exposed as a [ThemeExtension] so widgets read them from the
/// active [Theme] instead of importing raw palette constants. Mirrors the
/// tokens in `design/Sticker Maker.dc.html`.
@immutable
class SmTokens extends ThemeExtension<SmTokens> {
  const SmTokens({
    required this.panel,
    required this.card,
    required this.cardAlt,
    required this.inputField,
    required this.border,
    required this.textMuted,
    required this.textSecondary,
    required this.accents,
    required this.heroGradient,
    required this.cutoutGradient,
    required this.logoGradient,
    required this.radiusCard,
    required this.radiusPanel,
    required this.radiusCanvas,
    required this.radiusChip,
  });

  final Color panel;
  final Color card;
  final Color cardAlt;
  final Color inputField;
  final Color border;
  final Color textMuted;
  final Color textSecondary;

  /// Per-tool accent colors, keyed by [SmAccent].
  final Map<SmAccent, Color> accents;

  final Gradient heroGradient;
  final Gradient cutoutGradient;
  final Gradient logoGradient;

  final double radiusCard;
  final double radiusPanel;
  final double radiusCanvas;
  final double radiusChip;

  Color accent(SmAccent a) => accents[a]!;

  static const SmTokens dark = SmTokens(
    panel: AppColors.panel,
    card: AppColors.card,
    cardAlt: AppColors.cardAlt,
    inputField: AppColors.inputField,
    border: AppColors.border,
    textMuted: AppColors.textMuted,
    textSecondary: AppColors.textSecondary,
    accents: {
      SmAccent.layers: AppColors.violet,
      SmAccent.adjust: AppColors.cyan,
      SmAccent.text: AppColors.pink,
      SmAccent.erase: AppColors.amber,
      SmAccent.cutout: AppColors.green,
      SmAccent.frames: AppColors.orange,
    },
    heroGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.heroGradient,
      stops: [0.0, 0.45, 1.0],
    ),
    cutoutGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.cutoutGradient,
    ),
    logoGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: AppColors.logoGradient,
    ),
    radiusCard: 18,
    radiusPanel: 22,
    radiusCanvas: 24,
    radiusChip: 14,
  );

  @override
  SmTokens copyWith({
    Color? panel,
    Color? card,
    Color? cardAlt,
    Color? inputField,
    Color? border,
    Color? textMuted,
    Color? textSecondary,
    Map<SmAccent, Color>? accents,
    Gradient? heroGradient,
    Gradient? cutoutGradient,
    Gradient? logoGradient,
    double? radiusCard,
    double? radiusPanel,
    double? radiusCanvas,
    double? radiusChip,
  }) {
    return SmTokens(
      panel: panel ?? this.panel,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      inputField: inputField ?? this.inputField,
      border: border ?? this.border,
      textMuted: textMuted ?? this.textMuted,
      textSecondary: textSecondary ?? this.textSecondary,
      accents: accents ?? this.accents,
      heroGradient: heroGradient ?? this.heroGradient,
      cutoutGradient: cutoutGradient ?? this.cutoutGradient,
      logoGradient: logoGradient ?? this.logoGradient,
      radiusCard: radiusCard ?? this.radiusCard,
      radiusPanel: radiusPanel ?? this.radiusPanel,
      radiusCanvas: radiusCanvas ?? this.radiusCanvas,
      radiusChip: radiusChip ?? this.radiusChip,
    );
  }

  @override
  SmTokens lerp(covariant SmTokens? other, double t) {
    if (other == null) return this;
    return SmTokens(
      panel: Color.lerp(panel, other.panel, t)!,
      card: Color.lerp(card, other.card, t)!,
      cardAlt: Color.lerp(cardAlt, other.cardAlt, t)!,
      inputField: Color.lerp(inputField, other.inputField, t)!,
      border: Color.lerp(border, other.border, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      accents: t < 0.5 ? accents : other.accents,
      heroGradient: Gradient.lerp(heroGradient, other.heroGradient, t)!,
      cutoutGradient: Gradient.lerp(cutoutGradient, other.cutoutGradient, t)!,
      logoGradient: Gradient.lerp(logoGradient, other.logoGradient, t)!,
      radiusCard: lerpDouble(radiusCard, other.radiusCard, t),
      radiusPanel: lerpDouble(radiusPanel, other.radiusPanel, t),
      radiusCanvas: lerpDouble(radiusCanvas, other.radiusCanvas, t),
      radiusChip: lerpDouble(radiusChip, other.radiusChip, t),
    );
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;
}

/// The six editor tools, each with its own accent color.
enum SmAccent { layers, adjust, text, erase, cutout, frames }

/// Ergonomic access: `context.sm.accent(SmAccent.text)`.
extension SmTokensContext on BuildContext {
  SmTokens get sm => Theme.of(this).extension<SmTokens>()!;
}
