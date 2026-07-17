import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// A labeled slider row used across the Adjust, Text, Erase and Frames tools:
/// a title on the left, the current value on the right, and an accent-tinted
/// slider beneath. The value text defaults to the accent color (as the Adjust
/// panel uses); pass [valueColor] to override it (the Text/Erase/Frames panels
/// use a muted gray per the design).
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    this.onChanged,
    this.valueLabel,
    this.valueColor,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final Color accent;
  final ValueChanged<double>? onChanged;

  /// Text shown on the right (e.g. "118%"). Defaults to the rounded value.
  final String? valueLabel;

  /// Color of the value text. Defaults to [accent].
  final Color? valueColor;
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                valueLabel ?? value.round().toString(),
                style: TextStyle(
                  fontFamily: AppFonts.ui,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? accent,
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            thumbColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
            overlayColor: accent.withValues(alpha: 0.18),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
