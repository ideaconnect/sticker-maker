import 'package:flutter/material.dart';

import '../../../core/models/sticker_project.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/checkerboard.dart';
import '../../editor/widgets/sticker_canvas.dart';

/// A saved-sticker card: live canvas preview, GIF/PNG badge, name + layer/frame
/// count. Tap to open; long‑press to delete. Shared by the Home "Recent" grid
/// and the "All stickers" screen (#63).
///
/// The owner handles confirmation in [onDeleteRequested] (see
/// `confirmAndDeleteProject`), so the dialog can warn about pack membership —
/// something this tile can't know.
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.radius,
    required this.onTap,
    required this.onDeleteRequested,
  });

  final StickerProject project;
  final double radius;
  final VoidCallback onTap;

  /// Invoked on long-press; the owner confirms (and cascades) the delete.
  final VoidCallback onDeleteRequested;

  @override
  Widget build(BuildContext context) {
    final isGif = project.isAnimated;
    final layerCount = project.frames.isEmpty
        ? 0
        : project.frames.first.layers.length;
    final count = isGif
        ? '${project.frameCount} frames'
        : '$layerCount ${layerCount == 1 ? 'layer' : 'layers'}';

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        onLongPress: onDeleteRequested,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: AppColors.borderFaint),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(radius),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const Checkerboard(cell: 9),
                      if (project.frames.isNotEmpty)
                        StickerCanvas(frame: project.frames.first),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xB8131019),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isGif ? 'GIF' : 'PNG',
                            style: TextStyle(
                              fontFamily: AppFonts.ui,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                              color: isGif
                                  ? AppColors.orange
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 12, 11),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        project.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppFonts.ui,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      count,
                      style: const TextStyle(
                        fontFamily: AppFonts.ui,
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
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
}
