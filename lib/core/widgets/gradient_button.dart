import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../theme/sm_tokens.dart';

/// The primary call-to-action: a rounded button with an optional leading icon.
/// By default it is gradient-filled with a soft glow (used for "New Sticker",
/// "Export", "Remove background"). Pass [solidColor] for a flat, shadowless
/// variant (e.g. the muted "Undo removal" state).
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.gradient,
    this.solidColor,
    this.foreground = Colors.white,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
    this.fontSize = 15.5,
    this.glowColor,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Gradient fill. Defaults to the hero gradient from [SmTokens]. Ignored when
  /// [solidColor] is set.
  final Gradient? gradient;

  /// When set, the button renders a flat solid fill with no glow, overriding
  /// [gradient].
  final Color? solidColor;

  /// Icon + label color.
  final Color foreground;

  final EdgeInsets padding;
  final double fontSize;
  final Color? glowColor;

  /// When true, shows a spinner and ignores taps.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.sm;
    final solid = solidColor != null;
    final grad = solid ? null : (gradient ?? tokens.heroGradient);
    final glow = glowColor ?? AppColors.violetBright;
    final enabled = onPressed != null && !busy;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.7,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: solidColor,
            gradient: grad,
            borderRadius: BorderRadius.circular(16),
            boxShadow: solid
                ? null
                : [
                    BoxShadow(
                      color: glow.withValues(alpha: 0.35),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: padding,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (busy)
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(foreground),
                        ),
                      )
                    else if (icon != null)
                      Icon(icon, size: 19, color: foreground),
                    if (busy || icon != null) const SizedBox(width: 9),
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: AppFonts.ui,
                        color: foreground,
                        fontSize: fontSize,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
