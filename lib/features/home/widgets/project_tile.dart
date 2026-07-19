import 'package:flutter/material.dart';

import '../../../core/models/sticker_project.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/checkerboard.dart';
import '../../editor/widgets/sticker_canvas.dart';

/// A saved-sticker card: live canvas preview, GIF/PNG badge, name + layer/frame
/// count. Tap to open; long‑press for a menu — Open / Rename / Duplicate /
/// Delete (delete keeps its confirmation). Shared by the Home "Recent" grid
/// and the "All stickers" screen (#63).
class ProjectTile extends StatelessWidget {
  const ProjectTile({
    super.key,
    required this.project,
    required this.radius,
    required this.onTap,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final StickerProject project;
  final double radius;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

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
        onLongPress: () => _showMenu(context),
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

  /// Long-press menu. Open mirrors a plain tap; Delete keeps its confirm.
  Future<void> _showMenu(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuTile(ctx, Icons.open_in_full, 'Open', 'open'),
            _menuTile(ctx, Icons.drive_file_rename_outline, 'Rename', 'rename'),
            _menuTile(ctx, Icons.content_copy, 'Duplicate', 'duplicate'),
            _menuTile(ctx, Icons.delete_outline, 'Delete', 'delete'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'open':
        onTap();
      case 'rename':
        onRename();
      case 'duplicate':
        onDuplicate();
      case 'delete':
        if (context.mounted) await _confirmDelete(context);
    }
  }

  Widget _menuTile(
    BuildContext ctx,
    IconData icon,
    String label,
    String value,
  ) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(
        label,
        style: const TextStyle(
          fontFamily: AppFonts.ui,
          color: AppColors.textPrimary,
        ),
      ),
      onTap: () => Navigator.pop(ctx, value),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: Text(
          'Delete "${project.name}"?',
          style: const TextStyle(
            fontFamily: AppFonts.display,
            color: AppColors.textPrimary,
            fontSize: 17,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.rose),
            ),
          ),
        ],
      ),
    );
    if (ok ?? false) onDelete();
  }
}
