import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A compact rounded "pill" button used for actions like Reset, Add, Play/Pause
/// and the font chips. Tints to [accent] when [selected].
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.label,
    this.onTap,
    this.icon,
    this.accent = AppColors.violet,
    this.selected = false,
    this.labelStyle,
    this.radius = 20,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color accent;
  final bool selected;

  /// Overrides the label text style (e.g. to preview a sticker font).
  final TextStyle? labelStyle;

  /// Corner radius. Fully-rounded pills use 20 (default); the squarer font
  /// swatches use 12.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : AppColors.textSecondary;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: icon != null ? 12 : 15,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.15)
                : AppColors.inputField,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? accent : Colors.white.withValues(alpha: 0.10),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style:
                    labelStyle ??
                    TextStyle(
                      fontFamily: AppFonts.ui,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
