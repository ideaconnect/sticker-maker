import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/checkerboard.dart';
import '../editor/widgets/sticker_canvas.dart';
import 'sticker_templates.dart';

/// Bottom sheet that shows the curated [stickerTemplates] as live previews.
/// Resolves to the chosen template, or null if dismissed.
Future<StickerTemplate?> showTemplatePicker(BuildContext context) {
  return showModalBottomSheet<StickerTemplate>(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Templates',
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Pick a look — add your photo after.',
              style: TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 12.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
                children: [
                  for (final t in stickerTemplates)
                    _TemplateCard(
                      template: t,
                      onTap: () => Navigator.pop(ctx, t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final StickerTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final frame = template.previewProject().frames.first;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderFaint),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Checkerboard(cell: 8),
                      StickerCanvas(frame: frame),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppFonts.ui,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
